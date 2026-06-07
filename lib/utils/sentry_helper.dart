// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/utils/app_logger.dart';

const _databaseDescriptionPrefixes = <String>[
  'Open DB:',
  'Close DB:',
  'Transaction DB:',
];

void configureSentryOptions(SentryFlutterOptions options) {
  options.dsn = AppConstants.sentryDsn;
  options.tracesSampleRate = 0.05;
  options.profilesSampleRate = null;
  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  options.attachViewHierarchy = false;
  options.enableAutoSessionTracking = false;
  options.enablePrintBreadcrumbs = false;
  options.enableUserInteractionBreadcrumbs = false;
  options.enableUserInteractionTracing = false;
  options.enableAutoPerformanceTracing = true;
  options.environment = kDebugMode ? 'debug' : 'production';
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
  return description;
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
      span.setData('url', sanitizeSentryUrl(url));
    }
    span.removeData('http.query');
    span.removeData('http.fragment');
    final description = span.context.description;
    if (description != null) {
      span.context.description = sanitizeSentryDatabaseDescription(description);
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
