import 'dart:convert';

import '../gen_l10n/app_localizations.dart';
import '../services/api_key_manager.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/network_service.dart';
import '../utils/app_logger.dart';
import '../utils/http_response.dart';

typedef DailyQuoteHttpGet = Future<HttpResponse> Function(
  String url, {
  Map<String, String>? headers,
  int? timeoutSeconds,
});

typedef DailyQuoteApiKeyResolver = Future<String> Function(String providerId);

class Request {
  const Request();
}

class ApiService {
  static const String baseUrl = 'https://v1.hitokoto.cn/';
  static const String hitokotoProvider = 'hitokoto';
  static const String zenQuotesProvider = 'zenquotes';
  static const String apiNinjasProvider = 'api_ninjas';
  static const String meigenProvider = 'meigen';
  static const String koreanAdviceProvider = 'kadvice';
  static const List<String> supportedDailyQuoteProviders = [
    hitokotoProvider,
    zenQuotesProvider,
    apiNinjasProvider,
    meigenProvider,
    koreanAdviceProvider,
  ];
  static const List<String> apiNinjasCategoryKeys = [
    'wisdom',
    'philosophy',
    'life',
    'truth',
    'inspirational',
    'relationships',
    'love',
    'faith',
    'humor',
    'success',
    'courage',
    'happiness',
    'art',
    'writing',
    'fear',
    'nature',
    'time',
    'freedom',
    'death',
    'leadership',
  ];

  // 一言类型键常量 - 用于不需要本地化的场景（如静态配置）
  static const Map<String, String> hitokotoTypeKeys = {
    'a': 'Animation',
    'b': 'Comic',
    'c': 'Game',
    'd': 'Literature',
    'e': 'Original',
    'f': 'Internet',
    'g': 'Other',
    'h': 'Film',
    'i': 'Poetry',
    'j': 'NetEase',
    'k': 'Philosophy',
  };

  // 一言类型常量 - 返回本地化的标签
  static Map<String, String> getHitokotoTypes(AppLocalizations l10n) {
    return {
      'a': l10n.hitokotoTypeA,
      'b': l10n.hitokotoTypeB,
      'c': l10n.hitokotoTypeC,
      'd': l10n.hitokotoTypeD,
      'e': l10n.hitokotoTypeE,
      'f': l10n.hitokotoTypeF,
      'g': l10n.hitokotoTypeG,
      'h': l10n.hitokotoTypeH,
      'i': l10n.hitokotoTypeI,
      'j': l10n.hitokotoTypeJ,
      'k': l10n.hitokotoTypeK,
    };
  }

  static Map<String, String> getDailyQuoteProviders(AppLocalizations l10n) {
    return {
      hitokotoProvider: l10n.dailyQuoteApiHitokoto,
      zenQuotesProvider: l10n.dailyQuoteApiZenQuotes,
      apiNinjasProvider: l10n.dailyQuoteApiApiNinjas,
      meigenProvider: l10n.dailyQuoteApiMeigen,
      koreanAdviceProvider: l10n.dailyQuoteApiKoreanAdvice,
    };
  }

  static String recommendedDailyQuoteProviderForLanguage(
    String? languageCode,
  ) {
    switch ((languageCode ?? '').toLowerCase()) {
      case 'zh':
        return hitokotoProvider;
      case 'ja':
        return meigenProvider;
      case 'ko':
        return koreanAdviceProvider;
      default:
        return zenQuotesProvider;
    }
  }

  static Map<String, String> getApiNinjasCategories(AppLocalizations l10n) {
    return {
      'wisdom': l10n.dailyQuoteApiNinjasCategoryWisdom,
      'philosophy': l10n.dailyQuoteApiNinjasCategoryPhilosophy,
      'life': l10n.dailyQuoteApiNinjasCategoryLife,
      'truth': l10n.dailyQuoteApiNinjasCategoryTruth,
      'inspirational': l10n.dailyQuoteApiNinjasCategoryInspirational,
      'relationships': l10n.dailyQuoteApiNinjasCategoryRelationships,
      'love': l10n.dailyQuoteApiNinjasCategoryLove,
      'faith': l10n.dailyQuoteApiNinjasCategoryFaith,
      'humor': l10n.dailyQuoteApiNinjasCategoryHumor,
      'success': l10n.dailyQuoteApiNinjasCategorySuccess,
      'courage': l10n.dailyQuoteApiNinjasCategoryCourage,
      'happiness': l10n.dailyQuoteApiNinjasCategoryHappiness,
      'art': l10n.dailyQuoteApiNinjasCategoryArt,
      'writing': l10n.dailyQuoteApiNinjasCategoryWriting,
      'fear': l10n.dailyQuoteApiNinjasCategoryFear,
      'nature': l10n.dailyQuoteApiNinjasCategoryNature,
      'time': l10n.dailyQuoteApiNinjasCategoryTime,
      'freedom': l10n.dailyQuoteApiNinjasCategoryFreedom,
      'death': l10n.dailyQuoteApiNinjasCategoryDeath,
      'leadership': l10n.dailyQuoteApiNinjasCategoryLeadership,
    };
  }

  static bool supportsHitokotoTypeSelection(String provider) {
    return provider == hitokotoProvider;
  }

  static bool supportsProviderCategorySelection(String provider) {
    return provider == apiNinjasProvider;
  }

  static bool requiresApiKey(String provider) {
    return provider == apiNinjasProvider;
  }

  // 添加一个常量定义请求超时时间
  static const int _timeoutSeconds = 10;

  // 获取一言API数据，支持本地笔记回退
  static Future<Map<String, dynamic>> getDailyQuote(
    AppLocalizations l10n,
    String type, {
    bool useLocalOnly = false,
    String offlineQuoteSource = 'tagOnly',
    DatabaseService? databaseService,
    String provider = hitokotoProvider,
    List<String> apiNinjasCategories = const [],
    DailyQuoteApiKeyResolver? apiKeyResolver,
    DailyQuoteHttpGet? httpGet,
  }) async {
    try {
      // 如果设置了仅使用本地笔记，直接返回本地一言
      if (useLocalOnly) {
        return await _getLocalOnlyQuote(
          l10n,
          databaseService,
          offlineQuoteSource,
        );
      }

      // 检查网络连接状态
      final connectivityService = ConnectivityService();
      final isConnected = await connectivityService.checkConnectionNow();

      if (!isConnected) {
        logDebug('网络未连接，使用本地笔记');
        return await _getOfflineQuote(
          l10n,
          databaseService,
          offlineQuoteSource,
          isOffline: true,
        );
      }

      final normalizedProvider = supportedDailyQuoteProviders.contains(provider)
          ? provider
          : hitokotoProvider;
      final fetch = httpGet ?? NetworkService.instance.get;
      final remoteQuote = await _fetchRemoteQuote(
        type,
        provider: normalizedProvider,
        apiNinjasCategories: apiNinjasCategories,
        apiKeyResolver: apiKeyResolver ?? _resolveProviderApiKey,
        httpGet: fetch,
      );
      if (remoteQuote != null) {
        return remoteQuote;
      }

      return await _getLocalQuoteOrDefault(
        l10n,
        databaseService,
        offlineQuoteSource: offlineQuoteSource,
      );
    } catch (e) {
      logDebug('获取一言异常: $e');
      if (useLocalOnly) {
        return await _getLocalOnlyQuote(
          l10n,
          databaseService,
          offlineQuoteSource,
        );
      }
      return await _getLocalQuoteOrDefault(
        l10n,
        databaseService,
        offlineQuoteSource: offlineQuoteSource,
      );
    }
  }

  static Future<Map<String, dynamic>?> _fetchRemoteQuote(
    String type, {
    required String provider,
    required List<String> apiNinjasCategories,
    required DailyQuoteApiKeyResolver apiKeyResolver,
    required DailyQuoteHttpGet httpGet,
  }) async {
    switch (provider) {
      case hitokotoProvider:
        return _fetchFromHitokoto(type, httpGet: httpGet);
      case zenQuotesProvider:
        return _fetchFromZenQuotes(type, httpGet: httpGet);
      case apiNinjasProvider:
        return _fetchFromApiNinjas(
          type,
          apiNinjasCategories: apiNinjasCategories,
          apiKeyResolver: apiKeyResolver,
          httpGet: httpGet,
        );
      case meigenProvider:
        return _fetchFromMeigen(type, httpGet: httpGet);
      case koreanAdviceProvider:
        return _fetchFromKoreanAdvice(type, httpGet: httpGet);
      default:
        return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchFromHitokoto(
    String type, {
    required DailyQuoteHttpGet httpGet,
  }) async {
    String apiUrl = baseUrl;
    if (type.contains(',')) {
      final types = type.split(',');
      final typeParams =
          types.map((selectedType) => 'c=$selectedType').join('&');
      apiUrl = '$apiUrl?$typeParams';
    } else {
      apiUrl = '$apiUrl?c=$type';
    }

    logDebug('一言API请求URL: $apiUrl');
    final response = await httpGet(apiUrl, timeoutSeconds: _timeoutSeconds);
    if (response.statusCode != 200) {
      logDebug('一言API请求失败: ${response.statusCode}, 响应体: ${response.body}');
      return null;
    }

    final data = json.decode(response.body);
    if (data is! Map<String, dynamic> || !data.containsKey('hitokoto')) {
      logDebug('一言API返回数据格式错误: $data');
      return null;
    }

    return _normalizeQuote(
      content: data['hitokoto']?.toString() ?? '',
      author: data['from_who']?.toString() ?? '',
      source: data['from']?.toString() ?? '',
      type: data['type']?.toString() ?? _fallbackType(type),
      provider: hitokotoProvider,
    );
  }

  static Future<Map<String, dynamic>?> _fetchFromZenQuotes(
    String type, {
    required DailyQuoteHttpGet httpGet,
  }) async {
    const apiUrl = 'https://zenquotes.io/api/random';
    final response = await httpGet(apiUrl, timeoutSeconds: _timeoutSeconds);
    if (response.statusCode != 200) {
      logDebug('ZenQuotes 请求失败: ${response.statusCode}, 响应体: ${response.body}');
      return null;
    }

    final data = json.decode(response.body);
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
      provider: zenQuotesProvider,
    );
  }

  static Future<Map<String, dynamic>?> _fetchFromApiNinjas(
    String type, {
    required List<String> apiNinjasCategories,
    required DailyQuoteApiKeyResolver apiKeyResolver,
    required DailyQuoteHttpGet httpGet,
  }) async {
    final apiKey = await apiKeyResolver(apiNinjasProvider);
    if (apiKey.trim().isEmpty) {
      logDebug('API Ninjas 未配置 API Key，跳过远程请求');
      return null;
    }

    var apiUrl = 'https://api.api-ninjas.com/v2/randomquotes';
    if (apiNinjasCategories.isNotEmpty) {
      apiUrl = '$apiUrl?categories=${apiNinjasCategories.join(',')}';
    }

    final response = await httpGet(
      apiUrl,
      headers: {'X-Api-Key': apiKey},
      timeoutSeconds: _timeoutSeconds,
    );
    if (response.statusCode != 200) {
      logDebug(
          'API Ninjas 请求失败: ${response.statusCode}, 响应体: ${response.body}');
      return null;
    }

    final data = json.decode(response.body);
    final quote = data is List && data.isNotEmpty ? data.first : data;
    if (quote is! Map<String, dynamic>) {
      logDebug('API Ninjas 返回数据格式错误: $data');
      return null;
    }

    final categories = (quote['categories'] as List<dynamic>?) ?? const [];
    return _normalizeQuote(
      content: quote['quote']?.toString() ?? '',
      author: quote['author']?.toString() ?? '',
      source: quote['work']?.toString() ?? '',
      type: _mapApiNinjasType(categories, type),
      provider: apiNinjasProvider,
    );
  }

  static Future<Map<String, dynamic>?> _fetchFromMeigen(
    String type, {
    required DailyQuoteHttpGet httpGet,
  }) async {
    const apiUrl = 'https://meigen.doodlenote.net/api/json.php?c=1';
    final response = await httpGet(apiUrl, timeoutSeconds: _timeoutSeconds);
    if (response.statusCode != 200) {
      logDebug('名言教えるよ 请求失败: ${response.statusCode}, 响应体: ${response.body}');
      return null;
    }

    final data = json.decode(response.body);
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
      provider: meigenProvider,
    );
  }

  static Future<Map<String, dynamic>?> _fetchFromKoreanAdvice(
    String type, {
    required DailyQuoteHttpGet httpGet,
  }) async {
    const apiUrl = 'https://korean-advice-open-api.vercel.app/api/advice';
    final response = await httpGet(apiUrl, timeoutSeconds: _timeoutSeconds);
    if (response.statusCode != 200) {
      logDebug(
          'Korean Advice 请求失败: ${response.statusCode}, 响应体: ${response.body}');
      return null;
    }

    final data = json.decode(response.body);
    if (data is! Map<String, dynamic>) {
      logDebug('Korean Advice 返回数据格式错误: $data');
      return null;
    }

    return _normalizeQuote(
      content: data['message']?.toString() ?? '',
      author: data['author']?.toString() ?? '',
      source: data['authorProfile']?.toString() ?? '',
      type: _fallbackType(type),
      provider: koreanAdviceProvider,
    );
  }

  static String _fallbackType(String type) {
    final normalizedType = type
        .split(',')
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'a');
    return normalizedType.isEmpty ? 'a' : normalizedType;
  }

  static String _mapApiNinjasType(
      List<dynamic> categories, String fallbackType) {
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
          return 'l';
      }
    }

    return _fallbackType(fallbackType);
  }

  static Future<String> _resolveProviderApiKey(String providerId) async {
    return APIKeyManager().getProviderApiKey(providerId);
  }

  static Map<String, dynamic>? _normalizeQuote({
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

  static Future<Map<String, dynamic>> _getLocalOnlyQuote(
    AppLocalizations l10n,
    DatabaseService? databaseService,
    String offlineQuoteSource,
  ) async {
    return _getLocalQuoteOrDefault(
      l10n,
      databaseService,
      offlineQuoteSource: offlineQuoteSource,
      allowDefaultQuote: offlineQuoteSource != 'tagOnly',
      emptyStateContent: l10n.noLocalSavedQuotes,
      emptyStateType: 'local-empty',
    );
  }

  // 根据 offlineQuoteSource 选择离线数据源
  static Future<Map<String, dynamic>> _getOfflineQuote(
    AppLocalizations l10n,
    DatabaseService? databaseService,
    String offlineQuoteSource, {
    bool isOffline = false,
  }) async {
    return await _getLocalQuoteOrDefault(
      l10n,
      databaseService,
      offlineQuoteSource: offlineQuoteSource,
      isOffline: isOffline,
    );
  }

  // 获取本地一言或默认一言
  static Future<Map<String, dynamic>> _getLocalQuoteOrDefault(
    AppLocalizations l10n,
    DatabaseService? databaseService, {
    String offlineQuoteSource = 'tagOnly',
    bool isOffline = false,
    bool allowDefaultQuote = true,
    String? emptyStateContent,
    String emptyStateType = 'local-empty',
  }) async {
    try {
      if (databaseService != null) {
        final localQuote = await databaseService.getLocalDailyQuote(
          offlineQuoteSource: offlineQuoteSource,
        );
        if (localQuote != null) {
          logDebug('使用本地笔记作为一言');
          return localQuote;
        }
      }
    } catch (e) {
      logDebug('获取本地笔记失败: $e');
    }

    // 如果是离线状态且没有本地笔记，返回网络错误提示
    if (isOffline) {
      return {
        'content': l10n.noNetworkConnection,
        'source': '',
        'author': '',
        'type': 'offline',
        'from_who': '',
        'from': '',
        'provider': 'offline',
      };
    }

    if (!allowDefaultQuote) {
      return {
        'content': emptyStateContent ?? l10n.noLocalSavedQuotes,
        'source': '',
        'author': '',
        'type': emptyStateType,
        'from_who': '',
        'from': '',
        'provider': 'local',
      };
    }

    // 如果不是离线状态但本地笔记获取失败，使用默认一言
    logDebug('使用默认一言');
    return _getDefaultQuote(l10n);
  }

  // 提供默认引言，在网络请求失败时使用
  static Map<String, dynamic> _getDefaultQuote(AppLocalizations l10n) {
    // 预设的引言列表
    final quotes = [
      {
        'content': l10n.defaultQuote1,
        'source': l10n.unknown,
        'author': l10n.unknown,
        'type': 'a',
        'from_who': l10n.unknown,
        'from': l10n.unknown,
        'provider': 'default',
      },
      {
        'content': l10n.defaultQuote2,
        'source': l10n.unknown,
        'author': l10n.unknown,
        'type': 'a',
        'from_who': l10n.unknown,
        'from': l10n.unknown,
        'provider': 'default',
      },
      {
        'content': l10n.defaultQuote3,
        'source': l10n.unknown,
        'author': l10n.unknown,
        'type': 'a',
        'from_who': l10n.unknown,
        'from': l10n.unknown,
        'provider': 'default',
      },
    ];

    // 随机选择一条引言
    final random = DateTime.now().millisecondsSinceEpoch % quotes.length;
    return quotes[random];
  }

  void fetchData() {
    const req = Request();
    logDebug("请求发送：${req.toString()}");
  }
}
