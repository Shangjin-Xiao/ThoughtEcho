import 'dart:convert';
import '../services/network_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../utils/app_logger.dart';
import '../gen_l10n/app_localizations.dart';

class Request {
  const Request();
}

class ApiService {
  static const String baseUrl = 'https://v1.hitokoto.cn/';

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

  // 添加一个常量定义请求超时时间
  static const int _timeoutSeconds = 10;

  // 获取一言API数据，支持本地笔记回退
  static Future<Map<String, dynamic>> getDailyQuote(
    AppLocalizations l10n,
    String type, {
    bool useLocalOnly = false,
    DatabaseService? databaseService,
  }) async {
    try {
      // 如果设置了仅使用本地笔记，直接返回本地一言
      if (useLocalOnly) {
        return await _getLocalQuoteOrDefault(l10n, databaseService);
      }

      // 检查网络连接状态
      final connectivityService = ConnectivityService();
      final isConnected = await connectivityService.checkConnectionNow();

      if (!isConnected) {
        logDebug('网络未连接，使用本地笔记');
        return await _getLocalQuoteOrDefault(l10n, databaseService,
            isOffline: true);
      }

      // 处理多类型选择的情况
      String apiUrl = 'https://v1.hitokoto.cn/';

      // 如果类型包含逗号，说明是多类型选择
      if (type.contains(',')) {
        // 将逗号分隔的类型转换为c=a&c=b&c=d格式
        final types = type.split(',');
        final typeParams = types.map((t) => 'c=$t').join('&');
        apiUrl = '$apiUrl?$typeParams';
      } else {
        // 单类型选择
        apiUrl = '$apiUrl?c=$type';
      }

      logDebug('一言API请求URL: $apiUrl');
      // 使用带超时的HTTP请求
      final response = await NetworkService.instance
          .get(apiUrl, timeoutSeconds: _timeoutSeconds)
          .catchError((error) {
        logDebug('一言API请求错误: $error');
        throw error;
      });

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          // 验证返回的数据结构
          if (data is Map<String, dynamic> && data.containsKey('hitokoto')) {
            return {
              'content': data['hitokoto'],
              'source': data['from'],
              'author': data['from_who'],
              'type': data['type'],
              'from_who': data['from_who'],
              'from': data['from'],
            };
          } else {
            logDebug('一言API返回数据格式错误: $data');
            return await _getLocalQuoteOrDefault(l10n, databaseService);
          }
        } catch (e) {
          logDebug('一言API JSON解析失败: $e, 响应体: ${response.body}');
          return await _getLocalQuoteOrDefault(l10n, databaseService);
        }
      } else {
        logDebug('一言API请求失败: ${response.statusCode}, 响应体: ${response.body}');
        return await _getLocalQuoteOrDefault(l10n, databaseService);
      }
    } catch (e) {
      logDebug('获取一言异常: $e');
      return await _getLocalQuoteOrDefault(l10n, databaseService);
    }
  }

  // 获取本地一言或默认一言
  static Future<Map<String, dynamic>> _getLocalQuoteOrDefault(
    AppLocalizations l10n,
    DatabaseService? databaseService, {
    bool isOffline = false,
  }) async {
    try {
      if (databaseService != null) {
        final localQuote = await databaseService.getLocalDailyQuote();
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
      },
      {
        'content': l10n.defaultQuote2,
        'source': l10n.unknown,
        'author': l10n.unknown,
        'type': 'a',
        'from_who': l10n.unknown,
        'from': l10n.unknown,
      },
      {
        'content': l10n.defaultQuote3,
        'source': l10n.unknown,
        'author': l10n.unknown,
        'type': 'a',
        'from_who': l10n.unknown,
        'from': l10n.unknown,
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
