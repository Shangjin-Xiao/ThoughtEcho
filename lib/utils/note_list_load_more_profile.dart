import 'package:flutter/foundation.dart' show visibleForTesting;

/// 记录页分页（load more）一次的分段耗时。
///
/// 2026-08-25 的日志里，唯一带 `dataΔ=1` 的那段滑动出现 `worstVsync=77.1ms`、
/// `worstGap=357.5ms`，而 `avgBuild` 只有 1.3ms —— 成本全在「vsync 到 build 之间」，
/// 也就是帧之外的 UI 线程。实例复用（#510）之后整列表重建已经不是它了，剩下的只能
/// 是取下一页这件事本身：SQL、标签批查、50 条 `Quote.fromJson`、以及数据事件送到
/// 列表之后的复用比较和 setState。
///
/// 这些段落横跨 service 和 widget 两层，所以用一个静态累加器串起来，最后由滚动性能
/// 日志的 `loadMore={}` 一行打出来。**记的是最近一次分页**，不是增量 —— 要看的是
/// 「那一下 77ms 花在哪」，把多次平均掉反而看不见。
///
/// widget 那半边（`reuse` / `apply`）只在确认是分页带来的那次数据事件时才记账，
/// 搜索、筛选刷新、回填分块都进不来。
///
/// 查询那半边（`sql` / `tags` / `parse` / `rows`）没有请求 token：`getUserQuotes`
/// 埋得太深，为一个诊断一路穿下去不划算。改成**把窗口关严**：[begin] 开窗，
/// `loadMoreQuotes` 一返回就 [recordServiceCall] 关窗，之后的查询一律不计。
/// 窗口内仍可能挤进并发查询，所以采样次数一并打出来 —— `q=1` 才说明这份查询拆分
/// 干净，大于 1 就是混进了别的查询，别照着它下结论。
///
/// 2026-08-26 的日志证明了关窗的必要：冷启动那段 `q=4,rows=410,sql=131.5ms`，
/// 而 `service` 只有 127.4ms —— `sql` 竟然比包着它的 `service` 还大，因为窗口一直
/// 开到日志打印，把分页之后的查询全算了进来。
class NoteListLoadMoreProfile {
  NoteListLoadMoreProfile._();

  static int _sqlMicros = 0;
  static int _tagsMicros = 0;
  static int _parseMicros = 0;
  static int _rowCount = 0;
  static int _serviceMicros = 0;
  static int _reuseMicros = 0;
  static int _applyMicros = 0;

  /// 这一轮窗口里 [recordQuery] / [recordReuse] + [recordApply] 各被调用了几次。
  /// `q` 大于 1 说明有别的查询混进来了；`ev` 已经按分页事件过滤，正常就是 1，
  /// 是 0 说明那次分页的数据事件还没到（或者根本没触发），见类文档。
  static int _queryCount = 0;
  static int _eventCount = 0;

  /// 采样窗口是否还开着。分开两个：查询窗口在 `loadMoreQuotes` 返回时就关，
  /// 而分页带来的数据事件往往晚于它到达，所以事件窗口要多留一会儿。
  static bool _queryWindowOpen = false;
  static bool _eventWindowOpen = false;

  /// 累计完成过几次分页 —— **这个不随 [begin] 清零**：下面那些分段描述的是第几次
  /// 分页，这个数就是它的序号。清零的话它永远是 1，什么也说明不了。
  static int _completedCount = 0;

  /// 一次分页开始：把上一轮的分段清零，避免两次分页的数字混在一起。
  static void begin() {
    _sqlMicros = 0;
    _tagsMicros = 0;
    _parseMicros = 0;
    _rowCount = 0;
    _serviceMicros = 0;
    _reuseMicros = 0;
    _applyMicros = 0;
    _queryCount = 0;
    _eventCount = 0;
    _queryWindowOpen = true;
    _eventWindowOpen = true;
  }

  /// 查询层的三段，由 `getUserQuotes` 写入。
  ///
  /// 分页之外的查询（搜索、筛选、导出）也走同一个方法，落在窗口里就会一起记进来 ——
  /// 靠 `q=` 暴露，见类文档。
  static void recordQuery({
    required int sqlMicros,
    required int tagsMicros,
    required int parseMicros,
    required int rowCount,
  }) {
    if (!_queryWindowOpen) return;
    _sqlMicros += sqlMicros;
    _tagsMicros += tagsMicros;
    _parseMicros += parseMicros;
    _rowCount += rowCount;
    _queryCount++;
  }

  /// `db.loadMoreQuotes()` 这个 await 一共花了多久（含上面三段）。
  static void recordServiceCall(int micros) {
    _serviceMicros = micros;
    _completedCount++;
    // 查询已经做完了，关窗：再往后记就是别人的查询。
    _queryWindowOpen = false;
  }

  /// 数据事件送到列表之后：内容比较复用的耗时。
  static void recordReuse(int micros) {
    if (!_eventWindowOpen) return;
    _reuseMicros += micros;
    _eventCount++;
  }

  /// 把新列表落进 state 的那一下（clear/addAll/清理展开控制器）。
  ///
  /// **不包含随后的重建**：`setState` 只是排一帧，卡片真正重建的成本在下一帧里，
  /// 由日志的 `built=`、`itemMemo` 和 `worstBuild` 反映。名字叫 `apply` 而不是
  /// `state`，就是为了不让人把这个数当成「整列表重建花了多久」。
  static void recordApply(int micros) {
    if (!_eventWindowOpen) return;
    _applyMicros += micros;
  }

  /// 分页带来的那个数据事件处理完了，关掉事件窗口。
  static void endEventWindow() => _eventWindowOpen = false;

  @visibleForTesting
  static void resetForTesting() {
    begin();
    _completedCount = 0;
  }

  @visibleForTesting
  static bool get debugQueryWindowOpen => _queryWindowOpen;

  @visibleForTesting
  static bool get debugEventWindowOpen => _eventWindowOpen;

  @visibleForTesting
  static int get debugQueryCount => _queryCount;

  @visibleForTesting
  static int get debugEventCount => _eventCount;

  static String toCompactText() {
    String ms(int micros) => (micros / 1000.0).toStringAsFixed(1);
    return 'seq=$_completedCount,q=$_queryCount,ev=$_eventCount,'
        'rows=$_rowCount,'
        'service=${ms(_serviceMicros)}ms,'
        'sql=${ms(_sqlMicros)}ms,tags=${ms(_tagsMicros)}ms,'
        'parse=${ms(_parseMicros)}ms,'
        'reuse=${ms(_reuseMicros)}ms,apply=${ms(_applyMicros)}ms';
  }
}
