/// 版本号比较。
///
/// 独立成工具是因为它有两个调用方（检查更新、更新说明页），而两边一旦各写一份，
/// 迟早有一份会写成 `a.compareTo(b)`。
library;

/// 比较两个版本号：[a] 小于 / 等于 / 大于 [b] 时分别返回 -1 / 0 / 1。
///
/// **逐段比数字，绝不能比字符串**：`'3.10.0'.compareTo('3.7.0')` 是负数，
/// 按字符串比会认为 3.10 比 3.7 旧。
///
/// 容错覆盖项目里实际出现的几种写法：GitHub tag 的 `v` 前缀、pubspec 的 `+1`
/// 构建号、可能出现的 `-beta.1` 预发布后缀。**预发布后缀只剥离、不参与排序**——
/// 项目没有预发布渠道，为它引入 semver 的完整优先级规则是没有用户的复杂度。
///
/// 段数不同时短的一方补 0，所以 `4.0` 与 `4.0.0` 相等。无法解析的段按 0 处理，
/// 不抛异常：调用方拿到的版本号来自存储或网络，坏值不该让升级流程崩掉。
int compareVersions(String a, String b) {
  final aParts = _parse(a);
  final bParts = _parse(b);
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;

  for (var i = 0; i < length; i++) {
    final av = i < aParts.length ? aParts[i] : 0;
    final bv = i < bParts.length ? bParts[i] : 0;
    if (av != bv) return av < bv ? -1 : 1;
  }
  return 0;
}

List<int> _parse(String version) {
  final core = version
      .trim()
      .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
      .split(RegExp(r'[+-]'))
      .first;
  return core.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}
