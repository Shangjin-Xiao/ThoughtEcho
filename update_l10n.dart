import 'dart:io';

void addKeys(String filePath, Map<String, String> keys) {
  var file = File(filePath);
  var lines = file.readAsLinesSync();
  // Find the last closing brace
  int lastBraceIndex = lines.lastIndexWhere((line) => line.trim() == '}');
  if (lastBraceIndex != -1) {
    // Check if the previous line has a comma, if not, add one
    int prevLineIndex = lastBraceIndex - 1;
    while(prevLineIndex >= 0 && lines[prevLineIndex].trim().isEmpty) {
        prevLineIndex--;
    }
    if (prevLineIndex >= 0 && !lines[prevLineIndex].trim().endsWith(',')) {
      lines[prevLineIndex] = lines[prevLineIndex] + ',';
    }

    // Insert new keys
    int insertIndex = lastBraceIndex;
    var newLines = <String>[];
    keys.forEach((key, value) {
      newLines.add('  "$key": "$value",');
    });
    // Remove the last comma from the newly added lines
    if (newLines.isNotEmpty) {
      newLines[newLines.length - 1] = newLines.last.substring(0, newLines.last.length - 1);
    }
    lines.insertAll(insertIndex, newLines);

    file.writeAsStringSync(lines.join('\n') + '\n');
  }
}

void main() {
  addKeys('lib/l10n/app_zh.arb', {
    'webdavDisableSyncSuccess': '已关闭 WebDAV 云同步。本地数据完全保留。',
    'webdavDisableSync': '关闭并停用云同步',
    'webdavGoToResolve': '去处理',
    'webdavNoConflicts': '没有检测到冲突笔记',
    'webdavAllConflictsResolved': '您的所有同步冲突均已处理干净。',
    'webdavProviderNutstore': '坚果云 (Nutstore)',
    'webdavProviderCustom': '自定义 (Custom)'
  });
  addKeys('lib/l10n/app_en.arb', {
    'webdavDisableSyncSuccess': 'WebDAV sync disabled. Local data retained.',
    'webdavDisableSync': 'Disable Cloud Sync',
    'webdavGoToResolve': 'Resolve Now',
    'webdavNoConflicts': 'No Conflicts Detected',
    'webdavAllConflictsResolved': 'All sync conflicts have been resolved.',
    'webdavProviderNutstore': 'Nutstore',
    'webdavProviderCustom': 'Custom'
  });
}
