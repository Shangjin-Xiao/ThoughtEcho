part of 'api_service.dart';

Future<Map<String, dynamic>> _getLocalOnlyQuote(
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

Future<Map<String, dynamic>> _getOfflineQuote(
  AppLocalizations l10n,
  DatabaseService? databaseService,
  String offlineQuoteSource, {
  bool isOffline = false,
}) async {
  return _getLocalQuoteOrDefault(
    l10n,
    databaseService,
    offlineQuoteSource: offlineQuoteSource,
    isOffline: isOffline,
  );
}

Future<Map<String, dynamic>> _getLocalQuoteOrDefault(
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

  logDebug('使用默认一言');
  return _getDefaultQuote(l10n);
}

Map<String, dynamic> _getDefaultQuote(AppLocalizations l10n) {
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

  final random = DateTime.now().millisecondsSinceEpoch % quotes.length;
  return quotes[random];
}
