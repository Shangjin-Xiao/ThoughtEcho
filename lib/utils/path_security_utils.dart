import 'package:path/path.dart' as path;

class PathSecurityUtils {
  /// 将 ZIP 条目名称中的所有 Windows 反斜杠 `\` 转换为 POSIX 正斜杠 `/`
  /// 并且移除前导斜杠，防止绝对路径解释
  static String sanitizeZipEntryName(String entryName) {
    String sanitized = entryName.replaceAll('\\', '/');
    while (sanitized.startsWith('/')) {
      sanitized = sanitized.substring(1);
    }
    return sanitized;
  }

  /// 验证解压路径安全性，防止 Zip Slip 漏洞
  ///
  /// [targetPath] - 目标文件的完整路径
  /// [extractDir] - 解压根目录
  ///
  /// 如果路径安全，返回 true；否则抛出异常
  static void validateExtractionPath(String targetPath, String extractDir) {
    final normalizedTarget = path.normalize(path.absolute(targetPath));
    final normalizedExtractDir = path.normalize(path.absolute(extractDir));
    final extractDirWithSep = normalizedExtractDir.endsWith(path.separator)
        ? normalizedExtractDir
        : '$normalizedExtractDir${path.separator}';

    if (normalizedTarget != normalizedExtractDir &&
        !normalizedTarget.startsWith(extractDirWithSep)) {
      throw Exception('安全警告：路径尝试穿越到父目录 ($targetPath)');
    }

    // 额外的相对路径检查作为深度防御
    final relative =
        path.relative(normalizedTarget, from: normalizedExtractDir);
    if (relative.startsWith('..') || path.isAbsolute(relative)) {
      throw Exception('安全警告：路径尝试穿越到父目录 ($targetPath)');
    }
  }
}
