import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'large_file_manager.dart';
import '../utils/app_logger.dart';

class DraftService {
  static const String _draftDirName = 'drafts';

  // Singleton pattern
  static final DraftService _instance = DraftService._internal();
  factory DraftService() => _instance;
  DraftService._internal();

  /// 获取草稿目录
  Future<Directory> get _draftDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(appDir.path, _draftDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取草稿文件路径
  Future<File> _getDraftFile(String id) async {
    final dir = await _draftDir;
    // 使用简单的文件名映射，避免特殊字符问题
    final safeId = id.replaceAll(RegExp(r'[^\w\-]'), '_');
    return File(path.join(dir.path, '$safeId.json'));
  }

  /// 保存草稿
  Future<void> saveDraft(String id, Map<String, dynamic> data) async {
    try {
      final file = await _getDraftFile(id);
      await LargeFileManager.encodeJsonToFileStreaming(data, file);
      logDebug('草稿已保存: $id -> ${file.path}');
    } catch (e) {
      logError('保存草稿失败: $id', error: e, source: 'DraftService');
    }
  }

  /// 读取草稿
  Future<Map<String, dynamic>?> getDraft(String id) async {
    try {
      final file = await _getDraftFile(id);
      if (!await file.exists()) return null;

      logDebug('正在加载草稿: $id');
      return await LargeFileManager.decodeJsonFromFileStreaming(file);
    } catch (e) {
      logError('读取草稿失败: $id', error: e, source: 'DraftService');
      return null;
    }
  }

  /// 删除草稿
  Future<void> deleteDraft(String id) async {
    try {
      final file = await _getDraftFile(id);
      if (await file.exists()) {
        await file.delete();
        logDebug('草稿已删除: $id');
      }
    } catch (e) {
      logError('删除草稿失败: $id', error: e, source: 'DraftService');
    }
  }

  /// 检查是否存在草稿
  Future<bool> hasDraft(String id) async {
    try {
      final file = await _getDraftFile(id);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// 获取所有草稿中引用的媒体文件路径
  Future<Set<String>> getAllMediaPathsInDrafts() async {
    final mediaPaths = <String>{};
    try {
      final dir = await _draftDir;
      if (!await dir.exists()) return mediaPaths;

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'));

      for (final file in files) {
        try {
          // 为了性能，我们可能不想完全解析每个草稿
          // 但为了准确性，我们需要解析。
          // 优化：使用简单的字符串搜索，或者如果文件很大，使用流式解析
          // 这里暂时假设草稿数量不多，直接解析
          final data = await LargeFileManager.decodeJsonFromFileStreaming(file);
          if (data.containsKey('deltaContent')) {
            final deltaContent = data['deltaContent'];
            if (deltaContent is String) {
              // 解析 Delta JSON
              try {
                final delta = jsonDecode(deltaContent);
                _extractMediaFromDelta(delta, mediaPaths);
              } catch (_) {}
            }
          }
        } catch (e) {
          logDebug('扫描草稿媒体失败: ${file.path}, $e');
        }
      }
    } catch (e) {
      logError('获取草稿媒体路径失败', error: e, source: 'DraftService');
    }
    return mediaPaths;
  }

  void _extractMediaFromDelta(dynamic delta, Set<String> paths) {
    if (delta is List) {
      for (final op in delta) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is Map) {
            if (insert.containsKey('image'))
              paths.add(insert['image'].toString());
            if (insert.containsKey('video'))
              paths.add(insert['video'].toString());
            if (insert.containsKey('custom') && insert['custom'] is Map) {
              final custom = insert['custom'];
              if (custom.containsKey('audio'))
                paths.add(custom['audio'].toString());
            }
          }
        }
      }
    }
  }
}
