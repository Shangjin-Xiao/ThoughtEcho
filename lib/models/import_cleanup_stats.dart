/// 一次导入里「数据被动过哪里」的统计。
///
/// 覆盖导入没有 [MergeReport]（它不是合并），但用户同样有权知道自己选的文件里有多少
/// 东西不是本应用能认的。清洗和跳过都发生在入库前，报出来才算不静默——只写日志的话，
/// 除非用户主动去翻日志页，否则和没说一样。
///
/// 合并导入走 `MergeReport` 的同名字段，两条路径的口径保持一致。
class ImportCleanupStats {
  const ImportCleanupStats({
    this.sanitizedFields = 0,
    this.skippedEmptyQuotes = 0,
  });

  /// 被收敛掉的字段值个数（越界的 `sentiment`、非 `#RRGGBB` 的颜色、坏日期）。
  final int sanitizedFields;

  /// 因正文为空而没有导入的笔记条数。
  final int skippedEmptyQuotes;

  /// 这次导入是不是原样通过、什么都没动。
  bool get isClean => sanitizedFields == 0 && skippedEmptyQuotes == 0;

  @override
  String toString() => 'ImportCleanupStats(sanitizedFields: $sanitizedFields, '
      'skippedEmptyQuotes: $skippedEmptyQuotes)';
}
