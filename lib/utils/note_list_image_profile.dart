/// 折叠卡片图片从「provider 解析」到「第一帧出图」的分段计时。
///
/// 这一格是为了**证伪或坐实**上一轮留下的那条推断开的。
///
/// 2026-08-26 起的日志里有一个很稳的相关性：`worstVsync`（vsync 到 build 开始
/// 之间的等待，也就是**帧与帧之间**被占掉的 UI 线程时间）跟着「这一段建了几张新
/// 卡片」走，跟「重建了几张」无关：
///
/// | 会话 | built | itemMount | worstVsync |
/// |---|---|---|---|
/// | Android scroll-2 | 178 | 31 | **143.6ms** |
/// | Android scroll-27 | 121 | **0** | 2.8ms |
/// | iPad scroll-45 | 234 | **0** | 3.2ms |
///
/// 而卡片自己的 build 和 layout 都在预算内（`avgBuild` 1.0ms、`itemLayout worst`
/// 7ms）。所以成本不在 build 阶段，在挂载**引出的**异步工作上 —— 最大的嫌疑就是
/// 图片：文件读取、`ImmutableBuffer` 拷贝、编解码器建立、解码完成回调，这一串的
/// 头尾都落在 UI isolate 上，而且正好落在帧与帧之间。
///
/// 但这是**推断，不是证据**。这一格给出证据：
///
/// - `async` 跟着 `built` 涨、`worstWaitMs` 和 `worstVsync` 一个量级 → 坐实，
///   接下来优化图片管线（提前解码、错开完成时机、降低解码尺寸）。
/// - `async=0` 而 `worstVsync` 照样一两百毫秒 → **推断被证伪**，图片不是主因，
///   省下一整轮走错方向的优化。
///
/// 这条线上「先量再改」已经对了四次，其中一次直接推翻了看起来无懈可击的分页假设。
///
/// **`wait` 是延迟，不是 UI 线程占用**：解码本身在 worker 线程。它大 ≠ 主线程被
/// 占住那么久。要的是它和 `worstVsync` 的**相关性**，不是拿它当占用量直接读。
///
/// **仅限 UI Isolate（主线程）使用**：所有会话状态均为静态字段；Dart 中 Isolate
/// 间内存独立，跨 Isolate 调用会落入独立副本而无法聚合统计。
class NoteListImageProfile {
  NoteListImageProfile._();

  /// 只在滚动会话记录期间累计：平时一个字段都不碰，避免给正常路径加钱。
  static bool _recording = false;

  /// 会话代号，每开一段自增。
  ///
  /// 解码可以跨会话：A 段里开始解析的图，第一帧可能在 B 段才到。没有这个代号的话
  /// B 段会凭空多一个 `async`（没有对应的 `resolve`），等待时长还横跨两段 ——
  /// 又一个「在边界上给出看起来合理、其实是错的数」。带上代号之后这类完成单独
  /// 记进 `stale`，既不污染当段统计，本身也是个有用的信号：它大说明解码正在往后
  /// 面的会话里堆。
  static int _session = 0;

  static int _resolveCount = 0;
  static int _syncCount = 0;
  static int _asyncCount = 0;
  static int _failedCount = 0;
  static int _staleCount = 0;
  static int _asyncWaitMicros = 0;
  static int _worstWaitMicros = 0;

  static void beginSession() {
    _recording = true;
    _session++;
    _resolveCount = 0;
    _syncCount = 0;
    _asyncCount = 0;
    _failedCount = 0;
    _staleCount = 0;
    _asyncWaitMicros = 0;
    _worstWaitMicros = 0;
  }

  static void endSession() {
    _recording = false;
  }

  static bool get isRecording => _recording;

  /// 一张图开始解析。返回这次解析的凭据；不在记录期返回 null，调用方据此跳过记账。
  static NoteListImageResolve? markResolveStart() {
    if (!_recording) return null;
    _resolveCount++;
    return NoteListImageResolve(
      session: _session,
      startMicros: DateTime.now().microsecondsSinceEpoch,
    );
  }

  /// 这张图出第一帧了。
  ///
  /// [synchronous] 为真表示 `imageCache` 直接命中、没有任何异步工作 —— 那正是
  /// 预热要达到的状态，它涨说明预热在起作用。
  static void markFirstFrame({
    required NoteListImageResolve? resolve,
    required bool synchronous,
  }) {
    if (!_recording || resolve == null) return;
    if (resolve.session != _session) {
      _staleCount++;
      return;
    }
    if (synchronous) {
      _syncCount++;
      return;
    }
    _asyncCount++;
    final waited = DateTime.now().microsecondsSinceEpoch - resolve.startMicros;
    if (waited <= 0) return;
    _asyncWaitMicros += waited;
    if (waited > _worstWaitMicros) _worstWaitMicros = waited;
  }

  /// 这张图**加载或解码失败了**。
  ///
  /// 失败和出图一样是终态。不记的话它会一直躺在 `pending` 里，看起来像「解码排到
  /// 了下一段」，把「延迟解码有多严重」这个判断整体夸大 —— 而那正是要拿来和
  /// `worstVsync` 对相关性的那个数。
  static void markFailed({required NoteListImageResolve? resolve}) {
    if (!_recording || resolve == null) return;
    if (resolve.session != _session) {
      _staleCount++;
      return;
    }
    _failedCount++;
  }

  static String toCompactText() {
    final avgWaitMs =
        _asyncCount == 0 ? 0.0 : (_asyncWaitMicros / _asyncCount) / 1000.0;
    // pending = 解析了但这一段结束时既没出图也没失败的。它大说明解码排在了会话
    // 结束之后，那些成本会记到下一段的 `stale` 里去。
    final pending = _resolveCount - _syncCount - _asyncCount - _failedCount;
    return 'resolve=$_resolveCount,sync=$_syncCount,async=$_asyncCount,'
        'failed=$_failedCount,pending=$pending,stale=$_staleCount,'
        'avgWait=${avgWaitMs.toStringAsFixed(1)}ms,'
        'worstWait=${(_worstWaitMicros / 1000.0).toStringAsFixed(1)}ms';
  }
}

/// 一次图片解析的凭据：记着它是哪一段会话开的、什么时候开的。
///
/// 带会话代号是为了让跨会话完成的那些图不被算进错误的一段，见
/// [NoteListImageProfile._session]。
class NoteListImageResolve {
  const NoteListImageResolve({
    required this.session,
    required this.startMicros,
  });

  final int session;
  final int startMicros;
}
