// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/services/device_identity_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/app_tracer.dart';

const _databaseDescriptionPrefixes = <String>[
  'Open DB:',
  'Close DB:',
  'Transaction DB:',
];

void configureSentryOptions(SentryFlutterOptions options) {
  options.dsn = AppConstants.sentryDsn;

  // 既然数据收集默认关闭，开启用户的意愿较强，将链路采样率设为 1.0 获取充足性能样本
  options.tracesSampleRate = 1.0;

  // CPU Profiling 深度性能剖析。
  //
  // 这个采样率是**架在已采样事务之上的第二层**：配合上面的 tracesSampleRate = 1.0，
  // 1.0 等于「每条上报的事务都带一份采样式 CPU profile」。SDK 自己会判平台，只在
  // iOS/macOS 真正启动 profiler（见 SentryNativeProfilerFactory.attachTo），Android
  // 和 Windows 上设了也不会有任何开销，所以这里不再重复写一层平台分支。
  //
  // 记录页滚动的掉帧一直卡在「build 只有 1ms，整帧却拖到 40ms 以上」这种形状 ——
  // vsyncOverhead 说明时间花在帧与帧之间，逐帧计数器再怎么加也指不到具体函数。
  // 这一份 profile 就是为它开的；对应的取样只留下真卡过的那几段，见
  // [sanitizeSentryTransaction]。
  options.profilesSampleRate = 1.0;

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

class _QueryPattern {
  final String prefix;
  final RegExp regExp;
  final String formatPrefix;

  _QueryPattern(this.prefix, this.regExp, this.formatPrefix);
}

final _queryPatterns = <_QueryPattern>[
  _QueryPattern(
    'SELECT ',
    RegExp(r'\bFROM\s+([a-zA-Z0-9_]+)', caseSensitive: false),
    'SELECT FROM',
  ),
  _QueryPattern(
    'INSERT ',
    RegExp(r'\bINTO\s+([a-zA-Z0-9_]+)', caseSensitive: false),
    'INSERT INTO',
  ),
  _QueryPattern(
    'UPDATE ',
    RegExp(r'\bUPDATE\s+([a-zA-Z0-9_]+)', caseSensitive: false),
    'UPDATE',
  ),
  _QueryPattern(
    'DELETE ',
    RegExp(r'\bFROM\s+([a-zA-Z0-9_]+)', caseSensitive: false),
    'DELETE FROM',
  ),
  _QueryPattern(
    'CREATE ',
    RegExp(r'\bTABLE\s+([a-zA-Z0-9_]+)', caseSensitive: false),
    'CREATE TABLE',
  ),
];

String sanitizeSentryDatabaseDescription(String description) {
  for (final prefix in _databaseDescriptionPrefixes) {
    if (description.startsWith(prefix)) {
      return '$prefix main';
    }
  }
  final lowerDescription = description.toLowerCase();
  if (lowerDescription.contains('app_logs') ||
      lowerDescription.contains('log_database')) {
    return 'Log database write';
  }
  final normalized = description.trimLeft().toUpperCase();
  for (final pattern in _queryPatterns) {
    if (normalized.startsWith(pattern.prefix)) {
      final match = pattern.regExp.firstMatch(normalized);
      if (match != null) {
        return '${pattern.formatPrefix} ${match.group(1)}';
      }
      return '${pattern.prefix.trim()} query';
    }
  }
  if (normalized.startsWith('ALTER ') ||
      normalized.startsWith('DROP ') ||
      normalized.startsWith('PRAGMA ')) {
    return 'SQL schema/pragma query';
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

/// 一段滚动会话值不值得上报。
///
/// 记录页每滑一次就是一个事务，随手翻一分钟就是几十条：全量上报会把面板淹掉，
/// 在 iOS 上还给每条都附一份 CPU profile，白烧用户的流量。判据取收尾地标里已经
/// 算好的帧统计（见 `FrameTimingStats`），只留两种：这一段里有帧超了预算，或者
/// 最坏的一帧到了两帧预算 —— 后者兜住「只坏了一帧但坏得很厉害」那种。
///
/// **拿不到收尾地标时一律保留**。那说明会话没走到正常收尾（被下一次滚动顶掉、
/// 页面被销毁），异常路径正是最该看见的，不能被这层筛选悄悄吃掉。
///
/// `dropped` 故意没参与判据 —— 它在可变刷新率的屏幕上会把「面板降到 60Hz」误记成
/// 丢帧（见 `docs/note-list-warmup-invalidation-2026-08-22.md` 2026-08-27 一节），
/// 拿一个不可靠的数当筛选依据等于随机丢样本。
bool _isScrollSessionWorthReporting(SentryTransaction transaction) {
  for (final span in transaction.spans) {
    if (span.context.description != scrollSessionFinalizeTraceName) {
      continue;
    }
    final jank = span.data['frameJank'];
    if (jank is num && jank > 0) return true;
    final worstFrameMs = span.data['worstFrameMs'];
    final budgetMs = span.data['budgetMs'];
    if (worstFrameMs is num && budgetMs is num && budgetMs > 0) {
      return worstFrameMs >= budgetMs * 2;
    }
    return false;
  }
  return true;
}

SentryTransaction? sanitizeSentryTransaction(
  SentryTransaction transaction,
  Hint hint,
) {
  if (transaction.transaction == scrollSessionTraceName &&
      !_isScrollSessionWorthReporting(transaction)) {
    return null;
  }
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
