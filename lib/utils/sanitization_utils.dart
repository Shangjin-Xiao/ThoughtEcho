const Set<String> defaultSensitiveWords = <String>{
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

const Set<String> defaultMetricSuffixes = <String>{
  'length',
  'count',
  'size',
  'bytes',
  'duration',
  'ms',
  'overhead',
};

final RegExp sanitizationWordSplitPattern = RegExp(
  r'[_\.\-\s]+|(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])',
);

const Set<String> defaultAllowedUrlSchemes = <String>{
  'http',
  'https',
  'file',
};

/// 检查键名是否属于敏感字段。
///
/// 先按分词正则拆分为小写单词。
/// 若最后一个词属于 [metricSuffixes]，则直接判定为安全指标豁免（返回 false）；
/// 遍历分词，若包含在 [sensitiveWords] 中则返回 true；
/// 若当前词为 'api' 且下一个词为 'key'，则返回 true；
/// 其余情况返回 false。
bool isSensitiveKey(
  String key, {
  Set<String> sensitiveWords = defaultSensitiveWords,
  Set<String> metricSuffixes = defaultMetricSuffixes,
}) {
  final words = key
      .split(sanitizationWordSplitPattern)
      .where((w) => w.isNotEmpty)
      .map((w) => w.toLowerCase())
      .toList();
  if (words.isNotEmpty && metricSuffixes.contains(words.last)) {
    return false;
  }
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (sensitiveWords.contains(w)) return true;
    if (w == 'api' && i + 1 < words.length && words[i + 1] == 'key') {
      return true;
    }
  }
  return false;
}

/// 判断字符串是否可能是 URL。
///
/// 若 [key] 为 'url' 或字符串包含 '://' 返回 true；
/// 若解析为 URI 且具有 scheme，判断 scheme 是否在 [allowedSchemes] 中。
bool isLikelyUrl(
  String value, [
  String? key,
  Set<String> allowedSchemes = defaultAllowedUrlSchemes,
]) {
  if (key == 'url') return true;
  if (value.contains('://')) return true;
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    return allowedSchemes.contains(uri.scheme.toLowerCase());
  }
  return false;
}

/// 对 URL 进行脱敏清洗。
///
/// 若 url 为 null 返回 null；
/// 解析 uri，若解析失败返回原串；
/// 若无 scheme 返回 uri.path；
/// 若 scheme 为 'file' 返回 '[path]'；
/// 保留 scheme, host, port, path，清洗掉 query 参数和 fragment。
String? sanitizeUrl(String? url) {
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

/// 递归脱敏单个数据值。
///
/// 递归处理字符串（URL 清洗）、Map（剔除敏感键并递归清洗嵌套值）、List（递归清洗每个元素）。
Object? sanitizeDataValue(
  Object? value, {
  String? key,
  bool Function(String key) isSensitive = isSensitiveKey,
}) {
  if (value is String) {
    if (isLikelyUrl(value, key)) {
      return sanitizeUrl(value) ?? value;
    }
    return value;
  }
  if (value is Map) {
    return sanitizeDataMap<dynamic>(value, isSensitive: isSensitive);
  }
  if (value is List) {
    final result = <dynamic>[];
    for (final item in value) {
      result.add(sanitizeDataValue(item, isSensitive: isSensitive));
    }
    return result;
  }
  return value;
}

/// 顶层 Map 清洗函数。
///
/// 剔除 'http.query', 'http.fragment' 以及 [isSensitive] 为 true 的敏感键，并递归清洗嵌套值。
Map<K, dynamic> sanitizeDataMap<K>(
  Map<K, dynamic> data, {
  bool Function(String key) isSensitive = isSensitiveKey,
}) {
  final result = <K, dynamic>{};
  for (final entry in data.entries) {
    final key = entry.key;
    if (key is String) {
      if (key == 'http.query' || key == 'http.fragment' || isSensitive(key)) {
        continue;
      }
      result[key] = sanitizeDataValue(
        entry.value,
        key: key,
        isSensitive: isSensitive,
      );
    } else {
      result[key] = sanitizeDataValue(
        entry.value,
        isSensitive: isSensitive,
      );
    }
  }
  return result;
}
