import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class SentryHelper {
  SentryHelper._();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// 获取 Sentry 路由观察者
  static NavigatorObserver get navigatorObserver => SentryNavigatorObserver();

  /// 初始化 Sentry SDK
  static Future<void> init() async {
    if (_initialized) return;

    // Avoid initializing Sentry in unit tests to prevent errors/logs
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialized = true;
      return;
    }

    final dsn = AppConstants.sentryDsn;
    if (dsn.isEmpty) {
      throw StateError('Sentry DSN is empty');
    }

    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = dsn;
          options.tracesSampleRate =
              kDebugMode ? 1.0 : 0.2; // 开启性能监控，生产环境采用较低采样率
          options.environment = kDebugMode ? 'debug' : 'production';
          // 仅开启必要级别的打印调试
          options.debug = kDebugMode;
        },
      );
      _initialized = true;
      if (kDebugMode) {
        print('[Sentry] Sentry SDK initialized successfully.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Sentry] Failed to initialize Sentry: $e');
      }
      rethrow;
    }
  }

  /// 尝试根据是否启用初始化 Sentry SDK，并记录或反初始化 SDK
  static Future<void> initIfEnabled(bool enabled) async {
    if (enabled) {
      try {
        await init();
        logInfo('Sentry 初始化成功', source: 'BackgroundInit');
      } catch (e) {
        logWarning('Sentry 初始化失败: $e', source: 'BackgroundInit');
      }
    } else {
      if (_initialized) {
        try {
          await Sentry.close();
          _initialized = false;
          logInfo('Sentry 关闭成功', source: 'BackgroundInit');
        } catch (e) {
          logWarning('Sentry 关闭失败: $e', source: 'BackgroundInit');
        }
      }
    }
  }
}
