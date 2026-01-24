import 'dart:convert';
import 'mmkv_service.dart';
import '../utils/app_logger.dart';

class DraftService {
  // Singleton pattern
  static final DraftService _instance = DraftService._internal();
  factory DraftService() => _instance;
  DraftService._internal();

  String _makeKey(String id) {
    final safeId = id.replaceAll(RegExp(r'[^\w\-]'), '_');
    return 'draft_$safeId';
  }

  /// 保存草稿（跨平台）
  Future<void> saveDraft(String id, Map<String, dynamic> data) async {
    try {
      final key = _makeKey(id);
      // 使用 MMKV 服务作为跨平台存储，避免在 Web 上引用 dart:io
      await MMKVService().setJson(key, data);
      logDebug('草稿已保存: $id (MMKV)');
    } catch (e) {
      logError('保存草稿失败: $id', error: e, source: 'DraftService');
    }
  }

  /// 读取草稿（跨平台）
  Future<Map<String, dynamic>?> getDraft(String id) async {
    try {
      final key = _makeKey(id);
      final dynamic stored = MMKVService().getJson(key);
      if (stored == null) return null;
      if (stored is Map<String, dynamic>) return stored;
      if (stored is String) return jsonDecode(stored) as Map<String, dynamic>?;
      return Map<String, dynamic>.from(stored);
    } catch (e) {
      logError('读取草稿失败: $id', error: e, source: 'DraftService');
      return null;
    }
  }

  /// 删除草稿（跨平台）
  Future<void> deleteDraft(String id) async {
    try {
      final key = _makeKey(id);
      await MMKVService().remove(key);
      logDebug('草稿已删除: $id (MMKV)');
    } catch (e) {
      logError('删除草稿失败: $id', error: e, source: 'DraftService');
    }
  }

  /// 删除所有草稿
  Future<void> deleteAllDrafts() async {
    try {
      final keys = MMKVService().getAllKeys();
      for (final key in keys) {
        if (key.startsWith('draft_')) {
          await MMKVService().remove(key);
        }
      }
      logDebug('所有草稿已删除 (MMKV)');
    } catch (e) {
      logError('删除所有草稿失败', error: e, source: 'DraftService');
    }
  }

  /// 检查是否存在草稿（跨平台）
  Future<bool> hasDraft(String id) async {
    try {
      final key = _makeKey(id);
      final v = MMKVService().getString(key);
      return v != null && v.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 获取最新的草稿信息（用于启动恢复）
  Future<Map<String, dynamic>?> getLatestDraft() async {
    try {
      final keys = MMKVService().getAllKeys();
      String? latestKey;
      DateTime? latestTime;
      Map<String, dynamic>? latestData;

      for (final key in keys) {
        if (!key.startsWith('draft_')) continue;

        try {
          final dynamic stored = MMKVService().getJson(key);
          Map<String, dynamic>? data;
          if (stored == null) continue;
          if (stored is Map<String, dynamic>) {
            data = stored;
          } else if (stored is String) {
            data = jsonDecode(stored) as Map<String, dynamic>;
          } else {
            data = Map<String, dynamic>.from(stored);
          }

          if (data.containsKey('timestamp')) {
            final tsStr = data['timestamp'] as String;
            final ts = DateTime.tryParse(tsStr);
            if (ts != null) {
              if (latestTime == null || ts.isAfter(latestTime)) {
                latestTime = ts;
                latestKey = key;
                latestData = data;
              }
            }
          }
        } catch (e) {
          logDebug('解析草稿失败: $key, $e');
        }
      }

      if (latestKey != null && latestData != null) {
        // 返回包含原始ID的数据（从key中提取）
        // key format: draft_xxx
        final originalId = latestKey.substring(6);
        return {
          'id': originalId,
          ...latestData,
        };
      }
      return null;
    } catch (e) {
      logError('获取最新草稿失败', error: e, source: 'DraftService');
      return null;
    }
  }

  /// 获取所有草稿中引用的媒体文件路径（跨平台）
  Future<Set<String>> getAllMediaPathsInDrafts() async {
    final mediaPaths = <String>{};
    try {
      final keys = MMKVService().getAllKeys();
      for (final key in keys) {
        if (!key.startsWith('draft_')) continue;
        try {
          final dynamic stored = MMKVService().getJson(key);
          Map<String, dynamic>? data;
          if (stored == null) continue;
          if (stored is Map<String, dynamic>) {
            data = stored;
          } else if (stored is String) {
            data = jsonDecode(stored) as Map<String, dynamic>;
          } else {
            data = Map<String, dynamic>.from(stored);
          }

          if (data.containsKey('deltaContent')) {
            final deltaContent = data['deltaContent'];
            if (deltaContent is String) {
              try {
                final delta = jsonDecode(deltaContent);
                _extractMediaFromDelta(delta, mediaPaths);
              } catch (_) {}
            }
          }
        } catch (e) {
          logDebug('扫描草稿媒体失败: $key, $e');
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
            if (insert.containsKey('image')) {
              paths.add(insert['image'].toString());
            }
            if (insert.containsKey('video')) {
              paths.add(insert['video'].toString());
            }
            if (insert.containsKey('custom') && insert['custom'] is Map) {
              final custom = insert['custom'];
              if (custom.containsKey('audio')) {
                paths.add(custom['audio'].toString());
              }
            }
          }
        }
      }
    }
  }
}
