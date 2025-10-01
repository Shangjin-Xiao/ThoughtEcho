import 'package:flutter/foundation.dart';
import '../utils/mmkv_ffi_fix.dart';

/// 功能引导服务
/// 负责管理功能引导的显示状态
class FeatureGuideService extends ChangeNotifier {
  static const String _keyPrefix = 'feature_guide_shown_';
  final SafeMMKV _storage;

  FeatureGuideService(this._storage);

  /// 检查某个引导是否已经显示过
  bool hasShown(String guideId) {
    try {
      return _storage.getBool('$_keyPrefix$guideId') ?? false;
    } catch (e) {
      debugPrint('读取引导状态失败: $e');
      return false;
    }
  }

  /// 标记某个引导已显示
  Future<void> markAsShown(String guideId) async {
    try {
      await _storage.setBool('$_keyPrefix$guideId', true);
      notifyListeners();
      debugPrint('功能引导已标记: $guideId');
    } catch (e) {
      debugPrint('保存引导状态失败: $e');
    }
  }

  /// 重置某个引导（用于测试或重新显示）
  Future<void> resetGuide(String guideId) async {
    try {
      await _storage.remove('$_keyPrefix$guideId');
      notifyListeners();
      debugPrint('功能引导已重置: $guideId');
    } catch (e) {
      debugPrint('重置引导状态失败: $e');
    }
  }

  /// 重置所有引导（用于测试）
  Future<void> resetAllGuides() async {
    try {
      final keys = _storage.getKeys();
      for (final key in keys) {
        if (key.startsWith(_keyPrefix)) {
          await _storage.remove(key);
        }
      }
      notifyListeners();
      debugPrint('所有功能引导已重置');
    } catch (e) {
      debugPrint('重置所有引导失败: $e');
    }
  }

  /// 获取所有已显示的引导ID列表
  List<String> getShownGuides() {
    try {
      final keys = _storage.getKeys();
      return keys
          .where((key) => key.startsWith(_keyPrefix))
          .map((key) => key.substring(_keyPrefix.length))
          .toList();
    } catch (e) {
      debugPrint('获取已显示引导列表失败: $e');
      return [];
    }
  }

  /// 批量检查多个引导是否都已显示
  bool hasShownAll(List<String> guideIds) {
    return guideIds.every((id) => hasShown(id));
  }

  /// 批量检查多个引导是否有任意一个已显示
  bool hasShownAny(List<String> guideIds) {
    return guideIds.any((id) => hasShown(id));
  }
}
