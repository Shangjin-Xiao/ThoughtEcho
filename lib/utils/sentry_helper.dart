// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/services/device_identity_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

const _databaseDescriptionPrefixes = <String>[
  'Open DB:',
  'Close DB:',
  'Transaction DB:',
];

void configureSentryOptions(SentryFlutterOptions options) {
  options.dsn = AppConstants.sentryDsn;

  // 既然数据收集默认关闭，开启用户的意愿较强，将链路采样率设为 1.0 获取充足性能样本
  options.tracesSampleRate = 1.0;

  // CPU Profiling 深度性能剖析 (目前仅支持 iOS/macOS)
  // TODO: 当前无 iOS 发行版暂不开启，后续发布 iOS 版时可将其设为 1.0 或 0.5 开启深度剖析
  options.profilesSampleRate = null;

  // 开启 TTFD (完全渲染时间监控)
  // 在异步数据加载完成的页面手动调用 SentryFlutter.currentDisplay()?.reportFullyDisplayed();
  options.enableTimeToFullDisplayTracing = true;

  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  options.attachViewHierarchy = false;
  options.enableAutoSessionTracking = false;
  options.enablePrintBreadcrumbs = false;
  options.enableUserInteractionBreadcrumbs = false;
  options.enableUserInteractionTracing = false;
  options.enableAutoPerformanceTracing = true;

  // 1. 开启安卓底层崩溃与 ANR 监控 (针对安卓端的救星)
  options.anrEnabled = true;
  options.enableNativeCrashHandling = true;
  options.enableNdkScopeSync = true;

  // 使用底层标志更精确地区分真实生产环境与开发环境
  options.environment = kReleaseMode ? 'production' : 'development';

  options.beforeSend = sanitizeSentryEvent;
  options.beforeBreadcrumb = sanitizeSentryBreadcrumb;
  options.beforeSendTransaction = sanitizeSentryTransaction;
  options.debug = kDebugMode;
}

String sanitizeSentryDatabaseDescription(String description) {
  for (final prefix in _databaseDescriptionPrefixes) {
    if (description.startsWith(prefix)) {
      return '$prefix main';
    }
  }
  final lowerDescription = description.toLowerCase();
  final normalized = description.trimLeft().toUpperCase();
  if (lowerDescription.contains('app_logs') ||
      lowerDescription.contains('log_database')) {
    return 'Log database write';
  }
  if (normalized.startsWith('SELECT ') ||
      normalized.startsWith('INSERT ') ||
      normalized.startsWith('UPDATE ') ||
      normalized.startsWith('DELETE ') ||
      normalized.startsWith('CREATE ') ||
      normalized.startsWith('ALTER ') ||
      normalized.startsWith('DROP ') ||
      normalized.startsWith('PRAGMA ')) {
    return 'SQL query';
  }
  return description;
}

String sanitizeSentrySpanDescription(String description) {
  final parts = description.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && Uri.tryParse(parts[1])?.hasScheme == true) {
    return [
      parts.first,
      sanitizeSentryUrl(parts[1]),
      if (parts.length > 2) ...parts.skip(2),
    ].join(' ');
  }
  return sanitizeSentryDatabaseDescription(description);
}

String? sanitizeSentryUrl(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (!uri.hasScheme) return uri.path;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

SentryEvent? sanitizeSentryEvent(SentryEvent event, Hint hint) {
  _sanitizeSentryRequest(event);
  return event;
}

void _sanitizeSentryRequest(SentryEvent event) {
  final request = event.request;
  if (request != null) {
    event.request = SentryRequest(
      url: sanitizeSentryUrl(request.url),
      method: request.method,
      apiTarget: request.apiTarget,
    );
  }
}

Breadcrumb? sanitizeSentryBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb?.message != null) {
    breadcrumb!.message = sanitizeSentryDatabaseDescription(
      breadcrumb.message!,
    );
  }
  final url = breadcrumb?.data?['url'];
  if (url is String) {
    breadcrumb?.data?['url'] = sanitizeSentryUrl(url);
  }
  breadcrumb?.data?.remove('http.query');
  breadcrumb?.data?.remove('http.fragment');
  return breadcrumb;
}

SentryTransaction? sanitizeSentryTransaction(
  SentryTransaction transaction,
  Hint hint,
) {
  _sanitizeSentryRequest(transaction);
  for (final span in transaction.spans) {
    final url = span.data['url'];
    if (url is String) {
      span.data['url'] = sanitizeSentryUrl(url);
    }
    span.data.remove('http.query');
    span.data.remove('http.fragment');
    final description = span.context.description;
    if (description != null) {
      span.context.description = sanitizeSentrySpanDescription(description);
    }
  }
  return transaction;
}

class SentryHelper {
  SentryHelper._();

  static bool _initialized = false;
  static bool _desiredEnabled = false;
  static Future<void>? _initialization;
  static Future<void>? _closing;

  static bool get isInitialized => _initialized;

  /// 获取 Sentry 路由观察者
  static NavigatorObserver get navigatorObserver => SentryNavigatorObserver();

  /// 初始化 Sentry SDK
  static Future<void> init() async {
    final closing = _closing;
    if (closing != null) {
      await closing;
    }
    if (_initialized) return;

    final initialization = _initialization;
    if (initialization != null) {
      return initialization;
    }

    final future = _initialize();
    _initialization = future;
    try {
      await future;
    } finally {
      if (identical(_initialization, future)) {
        _initialization = null;
      }
    }
  }

  static Future<void> _initialize() async {
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
          configureSentryOptions(options);
        },
      );

      // 5. 绑定完全脱敏的匿名 Device ID，用于 Sentry 统计影响的用户百分比
      try {
        final deviceId = await DeviceIdentityManager.I.getFingerprint();
        Sentry.configureScope(
            (scope) => scope.setUser(SentryUser(id: deviceId)));
      } catch (e) {
        if (kDebugMode) print('[Sentry] Failed to set User ID: $e');
      }

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

  /// 在后台应用 Sentry 开关，不阻塞调用方。
  static void startIfEnabled(bool enabled) {
    unawaited(initIfEnabled(enabled));
  }

  /// 尝试根据是否启用初始化 Sentry SDK，并记录或反初始化 SDK
  static Future<void> initIfEnabled(bool enabled) async {
    _desiredEnabled = enabled;
    if (enabled) {
      try {
        await init();
        if (_desiredEnabled) {
          logInfo('Sentry 初始化成功', source: 'BackgroundInit');
        }
      } catch (e) {
        logWarning('Sentry 初始化失败: $e', source: 'BackgroundInit');
      }
    } else {
      await _close();
    }
  }

  static Future<void> _close() async {
    final closing = _closing;
    if (closing != null) {
      return closing;
    }

    final future = _closeAfterInitialization();
    _closing = future;
    try {
      await future;
    } finally {
      if (identical(_closing, future)) {
        _closing = null;
      }
    }
  }

  static Future<void> _closeAfterInitialization() async {
    try {
      await _initialization;
    } catch (_) {
      // 初始化失败时无需额外处理，原始错误已由初始化调用方记录。
    }
    if (!_initialized || _desiredEnabled) return;

    try {
      await Sentry.close();
      logInfo('Sentry 关闭成功', source: 'BackgroundInit');
    } catch (e) {
      logWarning('Sentry 关闭失败: $e', source: 'BackgroundInit');
    } finally {
      _initialized = false;
    }
  }
}
