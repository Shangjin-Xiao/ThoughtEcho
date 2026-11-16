import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'app_preferences_service.dart';

/// 功能引导服务
/// 负责管理功能引导的显示状态
class FeatureGuideService extends ChangeNotifier {
  static const String _keyPrefix = 'feature_guide_shown_';
  final AppPreferencesService _storage;

  FeatureGuideService([AppPreferencesService? storage])
      : _storage = storage ?? AppPreferencesService();

  /// 检查某个引导是否已经显示过
  bool hasShown(String guideId) {
    try {
      return _storage.getBool('$_keyPrefix$guideId') ?? false;
    } catch (e, stackTrace) {
      logError(
        '读取引导状态失败',
        error: e,
        stackTrace: stackTrace,
        source: 'FeatureGuideService',
      );
      return false;
    }
  }

  /// 标记某个引导已显示
  Future<void> markAsShown(String guideId) async {
    try {
      final saved = await _storage.setBool('$_keyPrefix$guideId', true);
      if (!saved) {
        logError(
          '保存引导状态失败: setBool returned false for $_keyPrefix$guideId',
          source: 'FeatureGuideService',
        );
        return;
      }
      notifyListeners();
      debugPrint('功能引导已标记: $guideId');
    } catch (e, stackTrace) {
      logError(
        '保存引导状态失败',
        error: e,
        stackTrace: stackTrace,
        source: 'FeatureGuideService',
      );
    }
  }

  /// 重置某个引导（用于测试或重新显示）
  Future<void> resetGuide(String guideId) async {
    try {
      final removed = await _storage.remove('$_keyPrefix$guideId');
      if (!removed) {
        logError(
          '重置引导状态失败: remove returned false for $_keyPrefix$guideId',
          source: 'FeatureGuideService',
        );
        return;
      }
      notifyListeners();
      debugPrint('功能引导已重置: $guideId');
    } catch (e, stackTrace) {
      logError(
        '重置引导状态失败',
        error: e,
        stackTrace: stackTrace,
        source: 'FeatureGuideService',
      );
    }
  }

  /// 重置所有引导（用于测试）
  Future<void> resetAllGuides() async {
    try {
      final keys = _storage.getAllKeys();
      var allRemoved = true;
      for (final key in keys) {
        if (key.startsWith(_keyPrefix)) {
          final removed = await _storage.remove(key);
          if (!removed) {
            allRemoved = false;
            logError(
              '重置所有引导失败: remove returned false for $key',
              source: 'FeatureGuideService',
            );
          }
        }
      }
      if (!allRemoved) {
        return;
      }
      notifyListeners();
      debugPrint('所有功能引导已重置');
    } catch (e, stackTrace) {
      logError(
        '重置所有引导失败',
        error: e,
        stackTrace: stackTrace,
        source: 'FeatureGuideService',
      );
    }
  }

  /// 获取所有已显示的引导ID列表
  List<String> getShownGuides() {
    try {
      final keys = _storage.getAllKeys();
      return keys
          .where((key) => key.startsWith(_keyPrefix))
          .map((key) => key.substring(_keyPrefix.length))
          .toList();
    } catch (e, stackTrace) {
      logError(
        '获取已显示引导列表失败',
        error: e,
        stackTrace: stackTrace,
        source: 'FeatureGuideService',
      );
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
