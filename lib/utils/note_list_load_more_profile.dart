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
class NoteListLoadMoreProfile {
  NoteListLoadMoreProfile._();

  static int _sqlMicros = 0;
  static int _tagsMicros = 0;
  static int _parseMicros = 0;
  static int _rowCount = 0;
  static int _serviceMicros = 0;
  static int _reuseMicros = 0;
  static int _applyMicros = 0;
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
  }

  /// 查询层的三段，由 `getUserQuotes` 写入。
  ///
  /// 分页之外的查询（搜索、筛选、导出）也会走同一个方法，这里照记不误：
  /// 它们不在 [begin] 与日志之间，不会污染分页那一次的读数。
  static void recordQuery({
    required int sqlMicros,
    required int tagsMicros,
    required int parseMicros,
    required int rowCount,
  }) {
    _sqlMicros += sqlMicros;
    _tagsMicros += tagsMicros;
    _parseMicros += parseMicros;
    _rowCount += rowCount;
  }

  /// `db.loadMoreQuotes()` 这个 await 一共花了多久（含上面三段）。
  static void recordServiceCall(int micros) {
    _serviceMicros = micros;
    _completedCount++;
  }

  /// 数据事件送到列表之后：内容比较复用的耗时。
  static void recordReuse(int micros) => _reuseMicros += micros;

  /// 把新列表落进 state 的那一下（clear/addAll/清理展开控制器）。
  ///
  /// **不包含随后的重建**：`setState` 只是排一帧，卡片真正重建的成本在下一帧里，
  /// 由日志的 `built=`、`itemMemo` 和 `worstBuild` 反映。名字叫 `apply` 而不是
  /// `state`，就是为了不让人把这个数当成「整列表重建花了多久」。
  static void recordApply(int micros) => _applyMicros += micros;

  static String toCompactText() {
    String ms(int micros) => (micros / 1000.0).toStringAsFixed(1);
    return 'n=$_completedCount,rows=$_rowCount,'
        'service=${ms(_serviceMicros)}ms,'
        'sql=${ms(_sqlMicros)}ms,tags=${ms(_tagsMicros)}ms,'
        'parse=${ms(_parseMicros)}ms,'
        'reuse=${ms(_reuseMicros)}ms,apply=${ms(_applyMicros)}ms';
  }
}
