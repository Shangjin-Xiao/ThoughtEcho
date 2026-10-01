import 'package:flutter/foundation.dart';

import 'package:aptabase_flutter/aptabase_flutter.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// Aptabase 匿名统计工具类
///
/// 遵循隐私第一原则，仅在用户显式开启设置且配置了 [AppConstants.aptabaseAppKey] 时上报。
/// 绝不上报任何笔记内容、搜索词、个人标识符或敏感数据。
class AptabaseHelper {
  AptabaseHelper._();

  static bool _initialized = false;
  static bool _enabled = false;
  static Future<void>? _initFuture;

  /// 配置或切换统计开关状态
  static Future<void> configure({required bool enabled}) async {
    _enabled = enabled;
    if (!enabled) return;
    if (_initialized) return;

    final inFlight = _initFuture;
    if (inFlight != null) return inFlight;

    final appKey = AppConstants.aptabaseAppKey;
    if (appKey.isEmpty) {
      if (kDebugMode) {
        logDebug('Aptabase App Key 为空，跳过初始化', source: 'Aptabase');
      }
      return;
    }

    final initFuture = () async {
      try {
        await Aptabase.init(appKey);
        _initialized = true;
        logInfo('Aptabase 初始化成功', source: 'Aptabase');
      } catch (e) {
        logWarning('Aptabase 初始化失败: $e', source: 'Aptabase');
      } finally {
        _initFuture = null;
      }
    }();
    _initFuture = initFuture;
    return initFuture;
  }

  /// 记录自定义事件
  ///
  /// [eventName] 事件名称，例如 'feature_used', 'page_view'
  /// [props] 可选属性键值对（必须是固定枚举或数字/布尔，严禁携带用户输入内容）
  static void trackEvent(String eventName, [Map<String, Object>? props]) {
    if (!_enabled || !_initialized) return;
    try {
      Aptabase.instance.trackEvent(eventName, props);
    } catch (e) {
      if (kDebugMode) {
        logDebug('Aptabase trackEvent 失败: $e', source: 'Aptabase');
      }
    }
  }

  /// 记录核心页面浏览事件
  ///
  /// [pageName] 页面名称：如 'home', 'notes', 'explore', 'settings', 'thoughter'
  static void trackPageView(String pageName) {
    trackEvent('page_view', {'page': pageName});
  }
}
