/// 地图回忆页用的轻量笔记坐标点。
///
/// 地图一次要摆下**全部**有坐标的笔记。走完整的 `Quote` 会把 `delta_content`、
/// `ai_analysis` 这些大字段一并读进内存，而 marker 只需要一个坐标；点开某个
/// marker 时再按 [id] 取完整笔记。
class QuoteMapPoint {
  const QuoteMapPoint({
    required this.id,
    required this.date,
    required this.latitude,
    required this.longitude,
  });

  final String id;

  /// 笔记的创建时间（ISO 8601 字符串，与 `Quote.date` 同源）。
  final String date;

  final double latitude;
  final double longitude;
}
