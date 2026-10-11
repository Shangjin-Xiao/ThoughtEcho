/// 安全解析 SQLite 聚合整数结果，支持 num 与 String 编码跨平台兜底。
///
/// 统一处理 SQLite 聚合函数在跨平台（Windows FFI / Android sqflite / iOS）
/// 下返回类型不一致（int / double / String）的问题，防止类型转换异常。
/// 严格检查 isFinite，避免 NaN / Infinity 调用 toInt() 抛异常。
int safeParseInt(Object? value, [int defaultValue = 0]) {
  if (value is num) {
    return value.isFinite ? value.toInt() : defaultValue;
  }
  if (value is String) {
    final directInt = int.tryParse(value);
    if (directInt != null) return directInt;
    final parsedNum = num.tryParse(value);
    if (parsedNum != null && parsedNum.isFinite) {
      return parsedNum.toInt();
    }
    return defaultValue;
  }
  return defaultValue;
}
