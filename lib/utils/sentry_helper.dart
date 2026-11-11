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
  // 记录页滚动的掉帧一直卡在「build 只有 1ms，整帧却拖到 40ms 以上」这种形状 ——
  // vsyncOverhead 说明时间花在帧与帧之间，逐帧计数器再怎么加也指不到具体函数。
  // 这一份 profile 就是为它开的。
  //
  // 采样率是**架在已采样事务之上的第二层**（见 SentryTracesSampler.sampleProfiling），
  // 配合上面的 tracesSampleRate = 1.0，1.0 等于「每一条事务都开 profiler」。平台由
  // SDK 自己判（SentryNativeProfilerFactory.attachTo 只在 iOS/macOS 启动 profiler），
  // 所以这里不重复写一层平台分支；Android 和 Windows 上设了不会有开销。
  //
  // **说清代价**：SDK 没有按事务名开关 profiler 的钩子，所以 iOS/macOS 上路由事务、
  // 分页、以及每一次「其实不卡」的滚动都会被采样，采样线程的 CPU 和电量是实打实要
  // 付的。下面 [sanitizeSentryTransaction] 那层筛选省的是**上传**，不是采样开销。
  // 明知如此仍然取 1.0：Sentry 默认关闭、由用户主动打开来查这一个问题，而调低采样率
  // 会按概率漏掉真卡的那几段 —— 那正是唯一要看的样本。
  // ignore: experimental_member_use
  options.profilesSampleRate = 1.0;

  // 开启 TTFD (完全渲染时间监控)
  // 在异步数据加载完成的页面手动调用 SentryFlutter.currentDisplay()?.reportFullyDisplayed();
  options.enableTimeToFullDisplayTracing = true;

  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  // ignore: experimental_member_use
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

const _allowedUrlSchemes = <String>{'http', 'https', 'file'};

bool _isLikelySpanUrl(String value, [String? key]) {
  if (key == 'url') return true;
  if (value.contains('://')) return true;
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    return _allowedUrlSchemes.contains(uri.scheme.toLowerCase());
  }
  return false;
}

String sanitizeSentrySpanDescription(String description) {
  final parts = description.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && _isLikelySpanUrl(parts[1])) {
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
  if (uri.scheme.toLowerCase() == 'file') {
    return '[path]';
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

final _exceptionUrlPattern = RegExp(
  r'''[a-z][a-z0-9+.-]*://[^\s<>"']+''',
  caseSensitive: false,
);

final _quotedFileUriPattern = RegExp(
  r'''(?<=["'])file:(?:/{1,3}|//[a-zA-Z0-9._-]+/)[^"'\r\n]+(?=["'])''',
  caseSensitive: false,
);

final _unquotedFileUriPattern = RegExp(
  r'''(?<![a-zA-Z0-9_])file:(?:/{1,3}|//[a-zA-Z0-9._-]+/)[^\s<>"'`]*''',
  caseSensitive: false,
);

final _quotedLocalPathPattern = RegExp(
  r'''(?<=["'])(?:[a-zA-Z]:[/\\\\]|/[a-zA-Z0-9._-]+/)[^"'\r\n]+(?=["'])''',
  caseSensitive: false,
);

final _unquotedLocalPathPattern = RegExp(
  r'''(?<![a-zA-Z0-9_/:\]])(?:[a-zA-Z]:[/\\\\]|/[a-zA-Z0-9._-]+/)[^\s<>"'`]*''',
  caseSensitive: false,
);

String _sanitizeFileUrisInText(String text) {
  var result = text.replaceAllMapped(_quotedFileUriPattern, (_) => '[path]');
  result = result.replaceAllMapped(_unquotedFileUriPattern, (match) {
    var p = match.group(0)!;
    var suffix = '';
    while (p.length > 2 &&
        (p.endsWith('.') ||
            p.endsWith(',') ||
            p.endsWith(';') ||
            p.endsWith(':') ||
            p.endsWith(')') ||
            p.endsWith(']'))) {
      suffix = p[p.length - 1] + suffix;
      p = p.substring(0, p.length - 1);
    }
    return '[path]$suffix';
  });
  return result;
}

String _sanitizePathsInText(String text) {
  var result = text.replaceAllMapped(_quotedLocalPathPattern, (_) => '[path]');
  result = result.replaceAllMapped(_unquotedLocalPathPattern, (match) {
    var p = match.group(0)!;
    var suffix = '';
    while (p.length > 2 &&
        (p.endsWith('.') ||
            p.endsWith(',') ||
            p.endsWith(';') ||
            p.endsWith(':') ||
            p.endsWith(')') ||
            p.endsWith(']'))) {
      suffix = p[p.length - 1] + suffix;
      p = p.substring(0, p.length - 1);
    }
    return '[path]$suffix';
  });
  return result;
}

String _sanitizeUrlsInText(String text) {
  return text.replaceAllMapped(_exceptionUrlPattern, (match) {
    final url = match.group(0)!;
    return Uri.tryParse(url) == null
        ? '[invalid URL]'
        : (sanitizeSentryUrl(url) ?? url);
  });
}

/// 1. Quoted Authorization header or scheme:
/// e.g. "Bearer 对不起，风太大了，我听不清。——皇昴流《东京巴比伦》"
/// e.g. "Authorization: Basic dXNlcjpwYXNz"
final _quotedAuthHeaderPattern = RegExp(
  r'''(?<=["'])\s*(?:(authorization\s*:\s*)?(Bearer|Basic))\s+[^"'\r\n]+(?=["'])''',
  caseSensitive: false,
);

/// 2. Unquoted Authorization header:
/// e.g. Authorization: Bearer abc123
/// e.g. Authorization: Basic dXNlcjpwYXNz
final _unquotedAuthHeaderPattern = RegExp(
  r'''\b(authorization\s*:\s*)(Bearer|Basic)\s+[^\s"'\r\n,;]+''',
  caseSensitive: false,
);

/// 3. Multiline header value followed by caret marker (e.g. FormatException output):
/// Bearer 对不起，风太大了，我听不清。——皇昴流《东京巴比伦》
///        ^
final _multilineAuthSchemePattern = RegExp(
  r'''^(\s*(?:authorization\s*:\s*)?(?:Bearer|Basic)\s+).+(?=\r?\n\s*\^)''',
  multiLine: true,
  caseSensitive: false,
);

/// 4. Inline Bearer token:
final _inlineBearerPattern = RegExp(
  r'''\b(Bearer)\s+([a-zA-Z0-9_\-\.\+/=~]{4,})(?=\s|["',;}\]]|$)''',
  caseSensitive: false,
);

/// 5. Inline Basic credentials:
final _inlineBasicPattern = RegExp(
  r'''\b(Basic)\s+([A-Za-z0-9+/]{4,}={0,2})(?=\s|["',;}\]]|$)''',
  caseSensitive: false,
);

String _sanitizeAuthHeadersInText(String text) {
  var result = text.replaceAllMapped(_quotedAuthHeaderPattern, (match) {
    final prefix = match.group(1) ?? '';
    final scheme = match.group(2) ?? '';
    return '$prefix$scheme [redacted]';
  });
  result = result.replaceAllMapped(_unquotedAuthHeaderPattern, (match) {
    final prefix = match.group(1) ?? '';
    final scheme = match.group(2) ?? '';
    return '$prefix$scheme [redacted]';
  });
  result = result.replaceAllMapped(_multilineAuthSchemePattern, (match) {
    final prefix = match.group(1) ?? '';
    if (prefix.trimRight().endsWith('[redacted]')) return match.group(0)!;
    return '$prefix[redacted]';
  });
  result = result.replaceAllMapped(_inlineBearerPattern, (match) {
    return '${match.group(1)} [redacted]';
  });
  result = result.replaceAllMapped(_inlineBasicPattern, (match) {
    return '${match.group(1)} [redacted]';
  });
  return result;
}

/// Quoted JSON string values for credential keys (including escaped characters):
/// e.g. {"api_key": "secret", "authToken": "secret\"with\\escapes"}
final _jsonApiKeyStringPattern = RegExp(
  r'''"(api[_-]?key|apikey|x[_-]api[_-]key|access[_-]?token|secret[_-]?key|auth[_-]?token|private[_-]?key)"(\s*:\s*)"(?:[^"\\]|\\.)*"''',
  caseSensitive: false,
);

/// Single-quoted JSON-like string values for credential keys:
/// e.g. {'api_key': 'secret', 'authToken': 'secret\'with\\escapes'}
final _singleQuotedApiKeyStringPattern = RegExp(
  r"""'(api[_-]?key|apikey|x[_-]api[_-]key|access[_-]?token|secret[_-]?key|auth[_-]?token|private[_-]?key)'(\s*:\s*)'(?:[^'\\]|\\.)*'""",
  caseSensitive: false,
);

/// API key key-value pairs (in headers, JSON, query, config, or error texts):
/// e.g. api_key: "secret", "apiKey": "secret", x-api-key: secret, api_key=secret
final _apiKeyKeyValuePattern = RegExp(
  r'''\b(api[_-]?key|apikey|x[_-]api[_-]key|access[_-]?token|secret[_-]?key|auth[_-]?token|private[_-]?key)(\s*[:=]\s*)(['"]?)([^\s"',;}\]]+)\3''',
  caseSensitive: false,
);

/// Standalone known API key formats:
/// - OpenAI/Anthropic/Groq etc: sk-..., sk_live_..., sk_test_...
/// - Google Gemini: AIza...
final _standaloneApiKeyPattern = RegExp(
  r'''\b(?:sk|pk|rk)_(?:live|test)_[a-zA-Z0-9]{14,}\b|\bsk-[a-zA-Z0-9_\-]{16,}\b|\bAIza[0-9A-Za-z\-_]{30,45}\b''',
);

String _sanitizeApiKeysInText(String text) {
  var result = text.replaceAllMapped(_jsonApiKeyStringPattern, (match) {
    return '"${match.group(1)}"${match.group(2)}"[redacted]"';
  });
  result = result.replaceAllMapped(_singleQuotedApiKeyStringPattern, (match) {
    return "'${match.group(1)}'${match.group(2)}'[redacted]'";
  });
  result = result.replaceAllMapped(_apiKeyKeyValuePattern, (match) {
    final key = match.group(1)!;
    final sep = match.group(2)!;
    final quote = match.group(3) ?? '';
    final val = match.group(4) ?? '';
    if (val == '[redacted]') return match.group(0)!;
    return '$key$sep$quote[redacted]$quote';
  });
  result =
      result.replaceAllMapped(_standaloneApiKeyPattern, (_) => '[redacted]');
  return result;
}

/// JSON string values for sensitive AI / user fields:
/// "prompt": "...", "content": "...", "messages": "..."
final _jsonSensitiveStringFieldPattern = RegExp(
  r'''"(prompt|system_prompt|content|deltaContent|messages)"\s*:\s*"(?:[^"\\]|\\.)*"''',
  caseSensitive: false,
);

/// JSON structured (array/object) values for sensitive AI / user fields:
/// "messages": [...], "prompt": [...]
final _jsonSensitiveStructureFieldPattern = RegExp(
  r'''"(prompt|system_prompt|content|deltaContent|messages)"\s*:\s*(\[[^\]\r\n]*\]|\{[^\}\r\n]*\})''',
  caseSensitive: false,
);

String _sanitizeAiFieldsInText(String text) {
  var result = text.replaceAllMapped(_jsonSensitiveStringFieldPattern, (match) {
    final key = match.group(1)!;
    return '"$key": "[redacted]"';
  });
  result =
      result.replaceAllMapped(_jsonSensitiveStructureFieldPattern, (match) {
    final key = match.group(1)!;
    return '"$key": "[redacted]"';
  });
  return result;
}

/// 对非 SQL 文本进行脱敏（清洗本地 file: URI、URL 参数、本地系统绝对路径、HTTP Authorization 凭据、API Key 以及 AI 敏感字段）。
String sanitizeSentryNonSqlText(String text) {
  if (text.isEmpty) return text;
  var result = _sanitizeFileUrisInText(text);
  result = _sanitizeUrlsInText(result);
  result = _sanitizePathsInText(result);
  result = _sanitizeAuthHeadersInText(result);
  result = _sanitizeApiKeysInText(result);
  result = _sanitizeAiFieldsInText(result);
  return result;
}

const _sensitiveBreadcrumbDataKeys = <String>[
  'query',
  'search',
  'file_path',
  'filepath',
  'path',
  'text',
  'content',
  'prompt',
  'system_prompt',
  'messages',
  'delta',
  'deltacontent',
  'token',
  'secret',
  'auth',
  'authorization',
  'password',
  'apikey',
  'api_key',
  'credential',
  'fragment',
];

bool _isSensitiveDataKey(String key) {
  final lowerKey = key.toLowerCase();
  final words =
      key.split(_spanWordSplitPattern).map((w) => w.toLowerCase()).toList();
  if (words.isNotEmpty && _spanMetricSuffixes.contains(words.last)) {
    return false;
  }
  for (final pattern in _sensitiveBreadcrumbDataKeys) {
    if (lowerKey.contains(pattern)) {
      return true;
    }
  }
  return false;
}

bool _isSensitiveBreadcrumbKey(String key) => _isSensitiveDataKey(key);

dynamic _sanitizeGenericData(dynamic value) {
  if (value is String) {
    return sanitizeSentryNonSqlText(value);
  }
  if (value is Map) {
    final sanitizedMap = <String, dynamic>{};
    for (final entry in value.entries) {
      final entryKey = entry.key.toString();
      if (_isSensitiveDataKey(entryKey)) {
        continue;
      }
      sanitizedMap[entryKey] = _sanitizeGenericData(entry.value);
    }
    return sanitizedMap;
  }
  if (value is List) {
    return value.map((item) => _sanitizeGenericData(item)).toList();
  }
  return value;
}

dynamic _sanitizeBreadcrumbDataValue(dynamic value) =>
    _sanitizeGenericData(value);

void _sanitizeSentryExceptions(SentryEvent event) {
  for (final exception in event.exceptions ?? <SentryException>[]) {
    final value = exception.value;
    if (value != null && value.isNotEmpty) {
      exception.value = sanitizeSentryNonSqlText(value);
    }
  }
}

void _sanitizeSentryMessage(SentryEvent event) {
  final message = event.message;
  if (message == null) return;

  if (message.formatted.isNotEmpty) {
    message.formatted = sanitizeSentryNonSqlText(message.formatted);
  }
  final template = message.template;
  if (template != null && template.isNotEmpty) {
    message.template = sanitizeSentryNonSqlText(template);
  }
  final params = message.params;
  if (params != null && params.isNotEmpty) {
    message.params = params.map((param) {
      if (param is String) {
        return sanitizeSentryNonSqlText(param);
      }
      if (param is Map || param is List) {
        return _sanitizeGenericData(param);
      }
      return param;
    }).toList();
  }
}

void _sanitizeSentryHint(Hint hint) {
  const commonHintKeys = <String>[
    'message',
    'source',
    'log',
    'error',
    'description',
    'reason',
    'detail',
    'details',
    'operation',
    'filePath',
    'file_path',
    'path',
    'query',
    'text',
    'content',
    'prompt',
    'system_prompt',
    'messages',
    'delta',
    'token',
    'secret',
    'auth',
    'authorization',
    'apiKey',
    'api_key',
    'password',
    'credential',
    'credentials',
  ];

  for (final key in commonHintKeys) {
    try {
      final value = hint.get(key);
      if (value == null) continue;
      if (_isSensitiveDataKey(key)) {
        hint.remove(key);
      } else if (value is String) {
        hint.set(key, sanitizeSentryNonSqlText(value));
      } else if (value is Map || value is List) {
        hint.set(key, _sanitizeGenericData(value));
      }
    } catch (_) {
      // Safe fallback on non-standard hint entries
    }
  }
}

void _sanitizeSentryMetadata(SentryEvent event) {
  // ignore: deprecated_member_use
  final extra = event.extra;
  if (extra != null && extra.isNotEmpty) {
    try {
      final sanitizedExtra =
          _sanitizeGenericData(extra) as Map<String, dynamic>;
      // ignore: deprecated_member_use
      event.extra = sanitizedExtra;
    } catch (e, stackTrace) {
      logError(
        'Failed to sanitize Sentry extra metadata: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'Sentry',
      );
      // Drop the affected entry without mutating potentially unmodifiable maps
      // ignore: deprecated_member_use
      event.extra = null;
    }
  }

  final contexts = event.contexts;
  final keys = contexts.keys.toList();
  for (final key in keys) {
    if (_isSensitiveDataKey(key)) {
      contexts.remove(key);
      continue;
    }
    final value = contexts[key];
    if (value is Map) {
      try {
        contexts[key] = _sanitizeGenericData(value);
      } catch (e, stackTrace) {
        contexts.remove(key);
        logError(
          'Failed to sanitize Sentry context entry $key: $e',
          error: e,
          stackTrace: stackTrace,
          source: 'Sentry',
        );
      }
    } else if (value is String) {
      contexts[key] = sanitizeSentryNonSqlText(value);
    } else if (value is List) {
      try {
        contexts[key] = _sanitizeGenericData(value);
      } catch (e, stackTrace) {
        contexts.remove(key);
        logError(
          'Failed to sanitize Sentry context entry $key: $e',
          error: e,
          stackTrace: stackTrace,
          source: 'Sentry',
        );
      }
    } else if (value is SentryResponse) {
      contexts[key] = SentryResponse(
        statusCode: value.statusCode,
        bodySize: value.bodySize,
      );
    }
  }

  final traceData = contexts.trace?.data;
  if (traceData != null) {
    try {
      final sanitizedTrace = _sanitizeSpanData(traceData);
      try {
        traceData.clear();
        traceData.addAll(sanitizedTrace);
      } catch (_) {
        contexts.trace?.data = sanitizedTrace;
      }
    } catch (e, stackTrace) {
      logError(
        'Failed to sanitize Sentry trace data: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'Sentry',
      );
      contexts.trace?.data = null;
    }
  }

  final tags = event.tags;
  if (tags != null && tags.isNotEmpty) {
    final sanitizedTags = <String, String>{};
    for (final entry in tags.entries) {
      if (_isSensitiveDataKey(entry.key)) continue;
      sanitizedTags[entry.key] = sanitizeSentryNonSqlText(entry.value);
    }
    try {
      tags.clear();
      tags.addAll(sanitizedTags);
    } catch (_) {
      event.tags = sanitizedTags;
    }
  }
}

SentryEvent? sanitizeSentryEvent(SentryEvent event, Hint hint) {
  try {
    _sanitizeSentryRequest(event);
    _sanitizeSentryExceptions(event);
    _sanitizeSentryMessage(event);
    _sanitizeSentryHint(hint);
    _sanitizeSentryMetadata(event);
    return event;
  } catch (e, stackTrace) {
    logError(
      'Failed to sanitize Sentry event: $e',
      error: e,
      stackTrace: stackTrace,
      source: 'Sentry',
    );
    return null;
  }
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
  if (breadcrumb == null) return null;

  final message = breadcrumb.message;
  if (message != null) {
    final dbSanitized = sanitizeSentryDatabaseDescription(message);
    if (dbSanitized != message) {
      breadcrumb.message = dbSanitized;
    } else {
      breadcrumb.message = sanitizeSentryNonSqlText(message);
    }
  }

  final data = breadcrumb.data;
  if (data != null) {
    final sanitizedData = <String, dynamic>{};
    for (final entry in data.entries) {
      if (_isSensitiveBreadcrumbKey(entry.key)) {
        continue;
      }
      sanitizedData[entry.key] = _sanitizeBreadcrumbDataValue(entry.value);
    }
    breadcrumb.data = sanitizedData;
  }

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

final _spanSensitiveWords = <String>{
  'content',
  'text',
  'query',
  'title',
  'password',
  'token',
  'secret',
  'authorization',
  'auth',
  'authentication',
  'credential',
  'credentials',
  'apikey',
};

final _spanMetricSuffixes = <String>{
  'length',
  'count',
  'size',
  'bytes',
  'duration',
  'ms',
  'overhead',
};

final _spanWordSplitPattern = RegExp(
  r'[_\.\-\s]+|(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])',
);

bool _isSensitiveSpanKey(String key) {
  final words =
      key.split(_spanWordSplitPattern).map((w) => w.toLowerCase()).toList();
  if (words.isNotEmpty && _spanMetricSuffixes.contains(words.last)) {
    return false;
  }
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (_spanSensitiveWords.contains(w)) return true;
    if (w == 'api' && i + 1 < words.length && words[i + 1] == 'key') {
      return true;
    }
  }
  return false;
}

dynamic _sanitizeSpanValue(dynamic value, {String? key}) {
  if (value is String) {
    if (_isLikelySpanUrl(value, key)) {
      return sanitizeSentryUrl(value) ?? value;
    }
    return value;
  }
  if (value is Map) {
    final result = <dynamic, dynamic>{};
    for (final entry in value.entries) {
      final entryKey = entry.key;
      if (entryKey is String) {
        if (entryKey == 'http.query' ||
            entryKey == 'http.fragment' ||
            _isSensitiveSpanKey(entryKey)) {
          continue;
        }
        result[entryKey] = _sanitizeSpanValue(entry.value, key: entryKey);
      } else {
        result[entryKey] = _sanitizeSpanValue(entry.value);
      }
    }
    return result;
  }
  if (value is List) {
    final result = <dynamic>[];
    for (final item in value) {
      result.add(_sanitizeSpanValue(item));
    }
    return result;
  }
  return value;
}

Map<K, dynamic> _sanitizeSpanMap<K>(Map<K, dynamic> data) {
  final result = <K, dynamic>{};
  for (final entry in data.entries) {
    final key = entry.key;
    if (key is String) {
      if (key == 'http.query' ||
          key == 'http.fragment' ||
          _isSensitiveSpanKey(key)) {
        continue;
      }
      result[key] = _sanitizeSpanValue(entry.value, key: key);
    } else {
      result[key] = _sanitizeSpanValue(entry.value);
    }
  }
  return result;
}

Map<String, dynamic> _sanitizeSpanData(Map<String, dynamic> data) =>
    _sanitizeSpanMap<String>(data);

@visibleForTesting
Map<K, dynamic> sanitizeSpanData<K>(Map<K, dynamic> data) =>
    _sanitizeSpanMap<K>(data);

SentryTransaction? sanitizeSentryTransaction(
  SentryTransaction transaction,
  Hint hint,
) {
  if (transaction.transaction == scrollSessionTraceName &&
      !_isScrollSessionWorthReporting(transaction)) {
    return null;
  }
  _sanitizeSentryRequest(transaction);
  final traceData = transaction.contexts.trace?.data;
  if (traceData != null) {
    final sanitizedTraceData = _sanitizeSpanData(traceData);
    try {
      traceData.clear();
      traceData.addAll(sanitizedTraceData);
    } catch (_) {
      transaction.contexts.trace?.data = sanitizedTraceData;
    }
  }
  for (final span in transaction.spans) {
    final sanitized = _sanitizeSpanData(span.data);
    try {
      span.data.clear();
      span.data.addAll(sanitized);
    } catch (_) {}
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

  @visibleForTesting
  static Future<SentryId> Function(
    dynamic throwable, {
    dynamic stackTrace,
    Hint? hint,
    ScopeCallback? withScope,
  })? onCaptureExceptionForTesting;

  /// 捕获并上报异常到 Sentry。
  ///
  /// 若配置了 [onCaptureExceptionForTesting]，则优先回调测试钩子。
  /// 遵循隐私第一原则，调用方应确保存储层故障不上报敏感记忆数据，但完整记录报错堆栈。
  static Future<SentryId> captureException(
    dynamic throwable, {
    dynamic stackTrace,
    Hint? hint,
    ScopeCallback? withScope,
  }) async {
    final testHandler = onCaptureExceptionForTesting;
    if (testHandler != null) {
      return testHandler(
        throwable,
        stackTrace: stackTrace,
        hint: hint,
        withScope: withScope,
      );
    }
    if (!Sentry.isEnabled) return SentryId.empty();
    try {
      return await Sentry.captureException(
        throwable,
        stackTrace: stackTrace,
        hint: hint,
        withScope: withScope,
      );
    } catch (e) {
      logWarning('Sentry captureException 失败: $e', source: 'Sentry');
      return SentryId.empty();
    }
  }

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
      await SentryFlutter.init((options) {
        configureSentryOptions(options);
      });

      // 5. 绑定完全脱敏的匿名 Device ID，用于 Sentry 统计影响的用户百分比
      try {
        final deviceId = await DeviceIdentityManager.I.getFingerprint();
        Sentry.configureScope(
          (scope) => scope.setUser(SentryUser(id: deviceId)),
        );
      } catch (e) {
        logWarning('Failed to set User ID: $e', source: 'Sentry');
      }

      _initialized = true;
      logInfo('Sentry SDK initialized successfully.', source: 'Sentry');
    } catch (e, stackTrace) {
      logError(
        'Failed to initialize Sentry: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'Sentry',
      );
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
