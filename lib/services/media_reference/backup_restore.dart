part of '../media_reference_service.dart';

/// Extension for backup and restore utilities
extension MediaBackupRestore on MediaReferenceService {
  /// 提供给备份使用的引用快照（避免重复全量扫描）
  static Future<ReferenceSnapshot> buildReferenceSnapshotForBackup() async {
    return MediaReferenceCleanup._buildReferenceSnapshot();
  }

  /// 备份/恢复使用的路径标准化（避免重复获取目录）
  static Future<String> normalizePathForBackup(
    String filePath, {
    required String appPath,
  }) async {
    try {
      if (filePath.isEmpty) {
        return filePath;
      }

      var sanitized = filePath.trim();

      if (sanitized.startsWith('file://')) {
        final uri = Uri.tryParse(sanitized);
        if (uri != null && uri.scheme == 'file') {
          sanitized = uri.toFilePath();
        }
      }

      sanitized = path.normalize(sanitized);

      if (sanitized.startsWith(appPath)) {
        return path.normalize(path.relative(sanitized, from: appPath));
      }

      return sanitized;
    } catch (_) {
      return filePath;
    }
  }

  /// 备份/恢复使用的统一比较Key
  static String canonicalKeyForBackup(String value) {
    return MediaReferenceCleanup._canonicalComparisonKey(value);
  }
}
