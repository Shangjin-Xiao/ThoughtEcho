import 'dart:convert';

import '../gen_l10n/app_localizations.dart';
import '../services/api_key_manager.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/network_service.dart';
import '../utils/app_logger.dart';
import '../utils/http_response.dart';

part 'api_service_daily_quote_fallback.dart';
part 'api_service_daily_quote_remote.dart';

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
    final normalizedLanguageCode =
        (languageCode ?? '').toLowerCase().split(RegExp(r'[_-]')).first;
    switch (normalizedLanguageCode) {
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
      return await _getLocalQuoteOrDefault(
        l10n,
        databaseService,
        offlineQuoteSource: offlineQuoteSource,
      );
    }
  }

  void fetchData() {
    const req = Request();
    logDebug("请求发送：${req.toString()}");
  }
}
