/// 版本号比较与语义化版本工具。
///
/// 独立成工具是因为它有多个调用方（检查更新、更新说明页、版本迁移等），
/// 避免各写一份容易出现字符串比较或构建号解析问题。
library;

/// 比较两个版本号：[a] 小于 / 等于 / 大于 [b] 时分别返回 -1 / 0 / 1。
///
/// **逐段比数字，绝不能比字符串**：`'3.10.0'.compareTo('3.7.0')` 是负数，
/// 按字符串比会认为 3.10 比 3.7 旧。
///
/// 容错覆盖项目里实际出现的几种写法：GitHub tag 的 `v` 前缀、pubspec 的 `+1`
/// 构建号、可能出现的 `-beta.1` 预发布后缀。
///
/// 当 [compareSemver] 为 false（默认）时，**预发布后缀与构建号只剥离、不参与排序**——
/// 满足 GitHub release 检查与常规更新说明展示的需求，`4.0.0+12` 与 `4.0.0` 相等。
///
/// 当 [compareSemver] 为 true 时，在核心段（major.minor.patch）相同的情况下，
/// 进一步根据语义化规则比较预发布后缀（如 `-beta.1` < `-beta.2` < 正式版）与构建号（如 `+11` < `+12`），
/// 适用于升级迁移判定（MigrationService）等需要精确识别子版本演进的场景。
///
/// 段数不同时短的一方补 0，所以 `4.0` 与 `4.0.0` 相等。无法解析的段按 0 处理，
/// 不抛异常：调用方拿到的版本号来自存储或网络，坏值不该让升级流程崩掉。
int compareVersions(String a, String b, {bool compareSemver = false}) =>
    _compareVersionsImpl(a, b, compareSemver: compareSemver);

/// 语义化完整版本比较，等同于 `compareVersions(a, b, compareSemver: true)`。
int compareSemver(String a, String b) => _compareSemverInternal(a, b);

/// 规范化版本字符串。
///
/// 支持纯构建号（如 '11' / '12' -> '1.0.0+11' / '1.0.0+12'）、
/// 带前缀（'v4.0.0' -> '4.0.0'）以及标准 semver。
/// 若为空或异常格式，安全降级为 '0.0.0'。
String normalizeVersion(String? version) => _normalizeVersionImpl(version);

/// 合并 packageInfo 的 version 与 buildNumber 构建完整的语义化版本字符串。
///
/// 容错处理 buildNumber 已包含完整语义化版本（如 '4.0.0-beta.1'、'1.2.0+15'）、
/// 仅含 buildNumber（如 '12'）、仅含预发布标识（如 'beta.1'）等渠道情况。
String formatVersion({String? version, String? buildNumber}) =>
    _formatVersionImpl(version: version, buildNumber: buildNumber);

final RegExp _vPrefixRegex = RegExp(r'^v', caseSensitive: false);
final RegExp _plusMinusRegex = RegExp(r'[+-]');

List<int> _parse(String version) {
  final core = version
      .trim()
      .replaceFirst(_vPrefixRegex, '')
      .split(_plusMinusRegex)
      .first;
  return core.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}

int _compareVersionsImpl(String a, String b, {bool compareSemver = false}) {
  if (compareSemver) {
    return _compareSemverInternal(a, b);
  }

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

String _normalizeVersionImpl(String? version) {
  if (version == null) return '0.0.0';
  var v = version.trim();
  if (v.isEmpty) return '0.0.0';

  if (v.startsWith('v') || v.startsWith('V')) {
    v = v.substring(1).trim();
  }
  if (v.isEmpty) return '0.0.0';

  // 纯整数历史构建号处理（如 MMKV 中存留的 '11' 或 '12'）
  final pureInt = int.tryParse(v);
  if (pureInt != null &&
      !v.contains('.') &&
      !v.contains('-') &&
      !v.contains('+')) {
    if (pureInt == 0) return '0.0.0';
    return '1.0.0+$pureInt';
  }

  return v;
}

String _formatVersionImpl({String? version, String? buildNumber}) {
  final v = (version ?? '').trim();
  final b = (buildNumber ?? '').trim();

  if (v.isEmpty && b.isEmpty) {
    return '0.0.0';
  }

  // 若 buildNumber 自身已为完整版本标识（含点号及主次版本，或带 v 前缀）
  if (b.startsWith('v') ||
      b.startsWith('V') ||
      (b.contains('.') && RegExp(r'^\d+\.\d+').hasMatch(b))) {
    return _normalizeVersionImpl(b);
  }

  if (v.isEmpty) {
    return _normalizeVersionImpl(b);
  }

  final cleanV =
      v.startsWith('v') || v.startsWith('V') ? v.substring(1).trim() : v;

  if (b.isEmpty) {
    return cleanV.isEmpty ? '0.0.0' : cleanV;
  }

  // 若 version 已包含构建元数据
  if (cleanV.contains('+')) {
    return cleanV;
  }

  if (b.startsWith('+') || b.startsWith('-')) {
    return '$cleanV$b';
  }

  if (RegExp(r'^(alpha|beta|rc|dev|preview)', caseSensitive: false)
      .hasMatch(b)) {
    return '$cleanV-$b';
  }

  return '$cleanV+$b';
}

class _ParsedSemver {
  final List<int> core;
  final String? prerelease;
  final String? build;

  const _ParsedSemver({
    required this.core,
    this.prerelease,
    this.build,
  });
}

_ParsedSemver _parseSemver(String raw) {
  final normalized = _normalizeVersionImpl(raw);

  String withoutBuild;
  String? build;
  final plusIdx = normalized.indexOf('+');
  if (plusIdx != -1) {
    build = normalized.substring(plusIdx + 1);
    withoutBuild = normalized.substring(0, plusIdx);
  } else {
    withoutBuild = normalized;
  }

  String coreStr;
  String? prerelease;
  final dashIdx = withoutBuild.indexOf('-');
  if (dashIdx != -1) {
    prerelease = withoutBuild.substring(dashIdx + 1);
    coreStr = withoutBuild.substring(0, dashIdx);
  } else {
    coreStr = withoutBuild;
  }

  final core =
      coreStr.split('.').map((part) => int.tryParse(part) ?? 0).toList();

  return _ParsedSemver(core: core, prerelease: prerelease, build: build);
}

int _compareSemverInternal(String a, String b) {
  final pa = _parseSemver(a);
  final pb = _parseSemver(b);

  // 1. 核心数字逐段比较
  final maxCoreLen =
      pa.core.length > pb.core.length ? pa.core.length : pb.core.length;
  for (var i = 0; i < maxCoreLen; i++) {
    final av = i < pa.core.length ? pa.core[i] : 0;
    final bv = i < pb.core.length ? pb.core[i] : 0;
    if (av != bv) return av < bv ? -1 : 1;
  }

  // 2. 预发布标识比较（依据 SemVer 2.0：正式版优先级高于预发布版）
  if (pa.prerelease == null && pb.prerelease != null) {
    return 1;
  }
  if (pa.prerelease != null && pb.prerelease == null) {
    return -1;
  }
  if (pa.prerelease != null && pb.prerelease != null) {
    final diff = _compareIdentifiers(pa.prerelease!, pb.prerelease!);
    if (diff != 0) return diff;
  }

  // 3. 构建元数据比较（为迁移场景区分同核心下的不同构建演进）
  if (pa.build != null && pb.build != null) {
    final diff = _compareIdentifiers(pa.build!, pb.build!);
    if (diff != 0) return diff;
  } else if (pa.build != null && pb.build == null) {
    return 1;
  } else if (pa.build == null && pb.build != null) {
    return -1;
  }

  return 0;
}

int _compareIdentifiers(String a, String b) {
  final partsA = a.split('.');
  final partsB = b.split('.');
  final maxLen = partsA.length > partsB.length ? partsA.length : partsB.length;

  for (var i = 0; i < maxLen; i++) {
    if (i >= partsA.length) return -1;
    if (i >= partsB.length) return 1;

    final segA = partsA[i];
    final segB = partsB[i];
    if (segA == segB) continue;

    final numA = int.tryParse(segA);
    final numB = int.tryParse(segB);

    if (numA != null && numB != null) {
      if (numA != numB) return numA < numB ? -1 : 1;
    } else if (numA != null) {
      return -1;
    } else if (numB != null) {
      return 1;
    } else {
      final cmp = segA.compareTo(segB);
      if (cmp != 0) return cmp < 0 ? -1 : 1;
    }
  }

  return 0;
}

/// VersionUtils 工具类，提供命名空间静态方法访问
abstract final class VersionUtils {
  static int compareVersions(String a, String b,
          {bool compareSemver = false}) =>
      _compareVersionsImpl(a, b, compareSemver: compareSemver);

  static int compareSemver(String a, String b) => _compareSemverInternal(a, b);

  static String normalizeVersion(String? version) =>
      _normalizeVersionImpl(version);

  static String formatVersion({String? version, String? buildNumber}) =>
      _formatVersionImpl(version: version, buildNumber: buildNumber);
}
