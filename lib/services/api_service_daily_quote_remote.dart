part of 'api_service.dart';

Future<Map<String, dynamic>?> _fetchRemoteQuote(
  String type, {
  required String provider,
  required List<String> apiNinjasCategories,
  required DailyQuoteApiKeyResolver apiKeyResolver,
  required DailyQuoteHttpGet httpGet,
}) async {
  switch (provider) {
    case ApiService.hitokotoProvider:
      return _fetchFromHitokoto(type, httpGet: httpGet);
    case ApiService.zenQuotesProvider:
      return _fetchFromZenQuotes(type, httpGet: httpGet);
    case ApiService.apiNinjasProvider:
      return _fetchFromApiNinjas(
        type,
        apiNinjasCategories: apiNinjasCategories,
        apiKeyResolver: apiKeyResolver,
        httpGet: httpGet,
      );
    case ApiService.meigenProvider:
      return _fetchFromMeigen(type, httpGet: httpGet);
    case ApiService.koreanAdviceProvider:
      return _fetchFromKoreanAdvice(type, httpGet: httpGet);
    default:
      return null;
  }
}

Future<Map<String, dynamic>?> _fetchFromHitokoto(
  String type, {
  required DailyQuoteHttpGet httpGet,
}) async {
  String apiUrl = ApiService.baseUrl;
  if (type.contains(',')) {
    final types = type.split(',');
    final typeParams = types.map((selectedType) => 'c=$selectedType').join('&');
    apiUrl = '$apiUrl?$typeParams';
  } else {
    apiUrl = '$apiUrl?c=$type';
  }

  logDebug('一言API请求URL: $apiUrl');
  final response = await httpGet(
    apiUrl,
    timeoutSeconds: ApiService._timeoutSeconds,
  );
  if (response.statusCode != 200) {
    logDebug('一言API请求失败: ${response.statusCode}, 响应体: ${response.body}');
    return null;
  }

  dynamic data;
  try {
    data = json.decode(response.body);
  } catch (e) {
    logDebug('一言API返回数据 JSON 解析失败: $e, 响应体: ${response.body}');
    return null;
  }
  if (data is! Map<String, dynamic> || !data.containsKey('hitokoto')) {
    logDebug('一言API返回数据格式错误: $data');
    return null;
  }

  return _normalizeQuote(
    content: data['hitokoto']?.toString() ?? '',
    author: data['from_who']?.toString() ?? '',
    source: data['from']?.toString() ?? '',
    type: data['type']?.toString() ?? _fallbackType(type),
    provider: ApiService.hitokotoProvider,
  );
}

Future<Map<String, dynamic>?> _fetchFromZenQuotes(
  String type, {
  required DailyQuoteHttpGet httpGet,
}) async {
  const apiUrl = 'https://zenquotes.io/api/random';
  final response = await httpGet(
    apiUrl,
    timeoutSeconds: ApiService._timeoutSeconds,
  );
  if (response.statusCode != 200) {
    logDebug('ZenQuotes 请求失败: ${response.statusCode}, 响应体: ${response.body}');
    return null;
  }

  dynamic data;
  try {
    data = json.decode(response.body);
  } catch (e) {
    logDebug('ZenQuotes 返回数据 JSON 解析失败: $e, 响应体: ${response.body}');
    return null;
  }
  final quote = data is List && data.isNotEmpty ? data.first : data;
  if (quote is! Map<String, dynamic>) {
    logDebug('ZenQuotes 返回数据格式错误: $data');
    return null;
  }

  return _normalizeQuote(
    content: quote['q']?.toString() ?? '',
    author: quote['a']?.toString() ?? '',
    source: '',
    type: _fallbackType(type),
    provider: ApiService.zenQuotesProvider,
  );
}

Future<Map<String, dynamic>?> _fetchFromApiNinjas(
  String type, {
  required List<String> apiNinjasCategories,
  required DailyQuoteApiKeyResolver apiKeyResolver,
  required DailyQuoteHttpGet httpGet,
}) async {
  final apiKey = await apiKeyResolver(ApiService.apiNinjasProvider);
  if (apiKey.trim().isEmpty) {
    logDebug('API Ninjas 未配置 API Key，跳过远程请求');
    return null;
  }

  var apiUrl = 'https://api.api-ninjas.com/v2/randomquotes';
  final supportedCategories = apiNinjasCategories
      .where((category) => ApiService.apiNinjasCategoryKeys.contains(category))
      .toList(growable: false);
  if (supportedCategories.isNotEmpty) {
    apiUrl = '$apiUrl?categories=${supportedCategories.join(',')}';
  }

  final response = await httpGet(
    apiUrl,
    headers: {'X-Api-Key': apiKey},
    timeoutSeconds: ApiService._timeoutSeconds,
  );
  if (response.statusCode != 200) {
    logDebug('API Ninjas 请求失败: ${response.statusCode}, 响应体: ${response.body}');
    return null;
  }

  dynamic data;
  try {
    data = json.decode(response.body);
  } catch (e) {
    logDebug('API Ninjas 返回数据 JSON 解析失败: $e, 响应体: ${response.body}');
    return null;
  }
  final quote = data is List && data.isNotEmpty ? data.first : data;
  if (quote is! Map<String, dynamic>) {
    logDebug('API Ninjas 返回数据格式错误: $data');
    return null;
  }

  final categoriesValue = quote['categories'];
  final categories = categoriesValue is List
      ? categoriesValue.cast<dynamic>()
      : const <dynamic>[];
  return _normalizeQuote(
    content: quote['quote']?.toString() ?? '',
    author: quote['author']?.toString() ?? '',
    source: quote['work']?.toString() ?? '',
    type: _mapApiNinjasType(categories, type),
    provider: ApiService.apiNinjasProvider,
  );
}

Future<Map<String, dynamic>?> _fetchFromMeigen(
  String type, {
  required DailyQuoteHttpGet httpGet,
}) async {
  const apiUrl = 'https://meigen.doodlenote.net/api/json.php?c=1';
  final response = await httpGet(
    apiUrl,
    timeoutSeconds: ApiService._timeoutSeconds,
  );
  if (response.statusCode != 200) {
    logDebug('名言教えるよ 请求失败: ${response.statusCode}, 响应体: ${response.body}');
    return null;
  }

  dynamic data;
  try {
    data = json.decode(response.body);
  } catch (e) {
    logDebug('名言教えるよ 返回数据 JSON 解析失败: $e, 响应体: ${response.body}');
    return null;
  }
  final quote = data is List && data.isNotEmpty ? data.first : data;
  if (quote is! Map<String, dynamic>) {
    logDebug('名言教えるよ 返回数据格式错误: $data');
    return null;
  }

  return _normalizeQuote(
    content: quote['meigen']?.toString() ?? '',
    author: quote['auther']?.toString() ?? '',
    source: '',
    type: _fallbackType(type),
    provider: ApiService.meigenProvider,
  );
}

Future<Map<String, dynamic>?> _fetchFromKoreanAdvice(
  String type, {
  required DailyQuoteHttpGet httpGet,
}) async {
  const apiUrl = 'https://korean-advice-open-api.vercel.app/api/advice';
  final response = await httpGet(
    apiUrl,
    timeoutSeconds: ApiService._timeoutSeconds,
  );
  if (response.statusCode != 200) {
    logDebug(
      'Korean Advice 请求失败: ${response.statusCode}, 响应体: ${response.body}',
    );
    return null;
  }

  dynamic data;
  try {
    data = json.decode(response.body);
  } catch (e) {
    logDebug('Korean Advice 返回数据 JSON 解析失败: $e, 响应体: ${response.body}');
    return null;
  }
  if (data is! Map<String, dynamic>) {
    logDebug('Korean Advice 返回数据格式错误: $data');
    return null;
  }

  return _normalizeQuote(
    content: data['message']?.toString() ?? '',
    author: data['author']?.toString() ?? '',
    source: data['authorProfile']?.toString() ?? '',
    type: _fallbackType(type),
    provider: ApiService.koreanAdviceProvider,
  );
}

String _fallbackType(String type) {
  final normalizedType = type
      .split(',')
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => 'a');
  return normalizedType.isEmpty ? 'a' : normalizedType;
}

String _mapApiNinjasType(List<dynamic> categories, String fallbackType) {
  for (final category in categories) {
    switch (category.toString()) {
      case 'philosophy':
      case 'wisdom':
      case 'truth':
      case 'faith':
        return 'k';
      case 'art':
      case 'writing':
        return 'd';
      case 'humor':
        return 'g';
    }
  }

  return _fallbackType(fallbackType);
}

Future<String> _resolveProviderApiKey(String providerId) async {
  return APIKeyManager().getProviderApiKey(providerId);
}

Map<String, dynamic>? _normalizeQuote({
  required String content,
  required String author,
  required String source,
  required String type,
  required String provider,
}) {
  if (content.trim().isEmpty) {
    return null;
  }

  final normalizedAuthor = author.trim();
  final normalizedSource = source.trim();
  final normalizedType = type.trim().isEmpty ? 'a' : type.trim();

  return {
    'content': content.trim(),
    'source': normalizedSource,
    'author': normalizedAuthor,
    'type': normalizedType,
    'from_who': normalizedAuthor,
    'from': normalizedSource,
    'provider': provider,
  };
}
