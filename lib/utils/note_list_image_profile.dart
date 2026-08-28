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
class NoteListImageProfile {
  NoteListImageProfile._();

  /// 只在滚动会话记录期间累计：平时一个字段都不碰，避免给正常路径加钱。
  static bool _recording = false;

  static int _resolveCount = 0;
  static int _syncCount = 0;
  static int _asyncCount = 0;
  static int _asyncWaitMicros = 0;
  static int _worstWaitMicros = 0;

  static void beginSession() {
    _recording = true;
    _resolveCount = 0;
    _syncCount = 0;
    _asyncCount = 0;
    _asyncWaitMicros = 0;
    _worstWaitMicros = 0;
  }

  static void endSession() {
    _recording = false;
  }

  static bool get isRecording => _recording;

  /// 一张图开始解析。返回起点时间戳；不在记录期返回 null，调用方据此跳过记账。
  static int? markResolveStart() {
    if (!_recording) return null;
    _resolveCount++;
    return DateTime.now().microsecondsSinceEpoch;
  }

  /// 这张图出第一帧了。
  ///
  /// [synchronous] 为真表示 `imageCache` 直接命中、没有任何异步工作 —— 那正是
  /// 预热要达到的状态，它涨说明预热在起作用。
  static void markFirstFrame({
    required int? startMicros,
    required bool synchronous,
  }) {
    if (!_recording) return;
    if (synchronous) {
      _syncCount++;
      return;
    }
    _asyncCount++;
    if (startMicros == null) return;
    final waited = DateTime.now().microsecondsSinceEpoch - startMicros;
    if (waited <= 0) return;
    _asyncWaitMicros += waited;
    if (waited > _worstWaitMicros) _worstWaitMicros = waited;
  }

  static String toCompactText() {
    final avgWaitMs =
        _asyncCount == 0 ? 0.0 : (_asyncWaitMicros / _asyncCount) / 1000.0;
    // resolve 和 sync+async 对不上的差额是「这一段里还没出图的」：它大说明解码
    // 排在了会话结束之后，那些成本会记到下一段去。
    return 'resolve=$_resolveCount,sync=$_syncCount,async=$_asyncCount,'
        'pending=${_resolveCount - _syncCount - _asyncCount},'
        'avgWait=${avgWaitMs.toStringAsFixed(1)}ms,'
        'worstWait=${(_worstWaitMicros / 1000.0).toStringAsFixed(1)}ms';
  }
}
