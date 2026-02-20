import 'package:path/path.dart' as path;

/// 路径安全异常
class PathSecurityException implements Exception {
  final String message;
  const PathSecurityException(this.message);

  @override
  String toString() => message;
}

class PathSecurityUtils {
  /// 验证解压路径安全性，防止 Zip Slip 漏洞
  ///
  /// [targetPath] - 目标文件的完整路径
  /// [extractDir] - 解压根目录
  ///
  /// 如果路径安全，则正常返回；否则抛出 [PathSecurityException]
  static void validateExtractionPath(String targetPath, String extractDir) {
    final normalizedTarget = path.normalize(path.absolute(targetPath));
    final normalizedExtractDir = path.normalize(path.absolute(extractDir));

    // 使用 path.isWithin 替代 startsWith，更健壮地防止路径穿越
    // 确保 targetPath 严格位于 extractDir 内部（不包括 extractDir 本身）
    if (!path.isWithin(normalizedExtractDir, normalizedTarget)) {
      throw PathSecurityException('安全警告：检测到非法路径穿越尝试 ($targetPath)');
    }
  }
}
