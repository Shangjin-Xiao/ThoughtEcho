import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../services/smart_push_service.dart';
import '../widgets/sliding_card.dart';
import 'dart:async'; // Import async for StreamController and StreamSubscription
import 'package:thoughtecho/utils/app_logger.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';
import 'app_snackbar.dart';

class DailyQuoteView extends StatefulWidget {
  // 修改接口，增加hitokotoData参数，以便传递完整的一言数据
  final Function(String, String?, String?, Map<String, dynamic>) onAddQuote;

  const DailyQuoteView({super.key, required this.onAddQuote});

  @override
  DailyQuoteViewState createState() => DailyQuoteViewState();
}

class DailyQuoteViewState extends State<DailyQuoteView> {
  bool _isInitialQuote = true;
  Map<String, dynamic> dailyQuote = {
    'content': '',
    'source': '',
    'author': '',
    'type': 'a',
  };
  SmartPushService? _smartPushService;
  // 标记当前是否正在展示通知推送的每日一言，为 true 时不允许 API 结果覆盖
  bool _isShowingNotificationQuote = false;

  @override
  void initState() {
    super.initState();
    // 推迟到首帧绘制完成后再发起 HTTP 请求，避免阻塞 ui.load 事务
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDailyQuote();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInitialQuote) {
      _isInitialQuote = false;
      dailyQuote['content'] = AppLocalizations.of(context).dailyQuoteLoading;
    }
    final nextSmartPushService = Provider.of<SmartPushService>(
      context,
      listen: false,
    );
    if (!identical(_smartPushService, nextSmartPushService)) {
      _smartPushService?.removeListener(_onSmartPushServiceChanged);
      _smartPushService = nextSmartPushService;
      _smartPushService?.addListener(_onSmartPushServiceChanged);
    }
  }

  @override
  void dispose() {
    _smartPushService?.removeListener(_onSmartPushServiceChanged);
    super.dispose();
  }

  void _onSmartPushServiceChanged() {
    final service = _smartPushService;
    if (service == null) return;
    unawaited(_applyPendingQuoteIfNeeded(service));
  }

  Map<String, dynamic> _convertSharedQuoteToDailyQuote(
    Map<String, dynamic> quoteData,
  ) {
    return {
      'content': quoteData['hitokoto'] ?? quoteData['content'] ?? '',
      'source': quoteData['from'] ?? quoteData['source'] ?? '',
      'author': quoteData['from_who'] ?? quoteData['author'] ?? '',
      'type': quoteData['type'] ?? 'a',
      'from_who': quoteData['from_who'] ?? quoteData['author'] ?? '',
      'from': quoteData['from'] ?? quoteData['source'] ?? '',
      'provider': quoteData['provider'] ?? '',
    };
  }

  Future<bool> _applyPendingQuoteIfNeeded(SmartPushService service) async {
    final pendingQuote = await service.consumePendingDailyQuoteForHomeDisplay();
    if (!mounted || pendingQuote == null) {
      return false;
    }

    setState(() {
      dailyQuote = _convertSharedQuoteToDailyQuote(pendingQuote);
      _isShowingNotificationQuote = true;
    });
    return true;
  }

  Future<void> _loadDailyQuote() async {
    try {
      final settingsService = Provider.of<SettingsService>(
        context,
        listen: false,
      );
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final connectivityService = Provider.of<ConnectivityService>(
        context,
        listen: false,
      );
      final smartPushService = Provider.of<SmartPushService>(
        context,
        listen: false,
      );

      final hitokotoType = settingsService.appSettings.hitokotoType;
      final dailyQuoteProvider = settingsService.dailyQuoteProvider;
      final apiNinjasCategories = settingsService.apiNinjasCategories;
      final useLocalOnly = settingsService.appSettings.useLocalQuotesOnly;
      final offlineQuoteSource = settingsService.offlineQuoteSource;
      final isConnected = connectivityService.isConnected;
      final l10n = AppLocalizations.of(context);

      setState(() {
        if (useLocalOnly) {
          dailyQuote = {
            'content': l10n.dailyQuoteLoadingLocal,
            'source': '',
            'author': '',
            'type': 'local',
          };
        } else if (!isConnected) {
          dailyQuote = {
            'content': l10n.dailyQuoteLoadingOffline,
            'source': '',
            'author': '',
            'type': 'offline',
          };
        } else {
          dailyQuote = {
            'content': l10n.dailyQuoteLoading,
            'source': '',
            'author': '',
            'type': 'a',
          };
        }
      });

      // 仅在“点击每日一言通知进入应用”时，首页消费并展示该条推送内容
      if (await _applyPendingQuoteIfNeeded(smartPushService)) {
        return;
      }

      if (!mounted) return;
      final quote = await ApiService.getDailyQuote(
        l10n,
        hitokotoType,
        useLocalOnly: useLocalOnly,
        offlineQuoteSource: offlineQuoteSource,
        databaseService: databaseService,
        provider: dailyQuoteProvider,
        apiNinjasCategories: apiNinjasCategories,
      );

      if (mounted) {
        // 若通知推送的每日一言已被展示（由 _onSmartPushServiceChanged 异步设置），
        // 则跳过 API 结果，避免覆盖通知内容
        if (!_isShowingNotificationQuote) {
          setState(() {
            dailyQuote = quote;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final isConnected = Provider.of<ConnectivityService>(
          context,
          listen: false,
        ).isConnected;

        final l10n = AppLocalizations.of(context);
        setState(() {
          if (!isConnected) {
            dailyQuote = {
              'content': l10n.dailyQuoteNoNetworkRetry,
              'source': '',
              'author': '',
              'type': 'error',
            };
          } else {
            dailyQuote = {
              'content': l10n.dailyQuoteFetchFailedRetry,
              'source': '',
              'author': '',
              'type': 'error',
            };
          }
        });

        // 添加重试机制，3秒后自动重试一次
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _loadDailyQuote();
          }
        });

        logDebug('获取一言失败: $e');
        AppSnackBar.error(
          context,
          l10n.fetchHitokotoFailed(e.toString()),
          action: SnackBarAction(
            label: l10n.retry,
            onPressed: _loadDailyQuote,
            textColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
        );
      }
    }
  }

  // 格式化一言的来源显示
  String formatHitokotoSource(String? author, String? source) {
    if ((author == null || author.isEmpty) &&
        (source == null || source.isEmpty)) {
      return '';
    }

    String result = '';
    if (author != null && author.isNotEmpty) {
      result += '——$author';
    }

    if (source != null && source.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$source》';
    }

    return result;
  }

  // 公开刷新方法，供父组件调用（手动刷新时清除通知标志）
  Future<void> refreshQuote() async {
    _isShowingNotificationQuote = false;
    await _loadDailyQuote();
  }

  /// 一言正文相对基准字号（`titleLarge`，M3 为 22）的缩放倍率。
  ///
  /// 过去这里直接返回 16–30 的字面量。字面量本身就违反项目排版约束，更实际的
  /// 代价是**基准一变它就不跟**：风格换了字体、系统调了字形几何，这张卡还钉在
  /// 那几个数上。现在只保留「屏幕多大就放多少」这层判断，绝对值交给 textTheme。
  double _responsiveQuoteScale(double screenWidth, double screenHeight) {
    if (screenHeight < 550) {
      // 极小屏设备
      return screenWidth > 600 ? 1.2 : (screenWidth > 400 ? 0.82 : 0.73);
    } else if (screenHeight < 600) {
      // 小屏设备
      return screenWidth > 600 ? 1.28 : (screenWidth > 400 ? 0.91 : 0.82);
    } else {
      // 普通屏幕
      return screenWidth > 600 ? 1.36 : (screenWidth > 400 ? 1.0 : 0.91);
    }
  }

  // 响应式行数限制
  int? _getResponsiveMaxLines(double screenWidth, double screenHeight) {
    if (screenWidth > 600) {
      return null; // 大屏设备不限制行数
    }

    if (screenHeight < 550) {
      return 3; // 极小屏设备最多3行
    } else if (screenHeight < 600) {
      return 4; // 小屏设备最多4行
    } else {
      return 5; // 中等屏幕最多5行
    }
  }

  // 响应式来源字体大小
  double _getResponsiveSourceFontSize(double screenWidth, double screenHeight) {
    if (screenHeight < 550) {
      return screenWidth > 600 ? 12 : 10;
    } else if (screenHeight < 600) {
      return screenWidth > 600 ? 13 : 11;
    } else {
      return screenWidth > 600 ? 14 : 12;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 更精细的屏幕尺寸判断
    final isSmallScreen = screenHeight < 600;
    final isVerySmallScreen = screenHeight < 550;

    return Container(
      // 去掉固定高度，让容器适应父组件的尺寸
      width: double.infinity,
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth > 600 ? 10.0 : 2.0, // 调整外边距使总间距与今日思考一致
        vertical:
            isVerySmallScreen ? 8.0 : (isSmallScreen ? 12.0 : 16.0), // 动态调整垂直边距
      ),
      child: SlidingCard(
        // 单击整个卡片区域复制内容
        onTap: () {
          final String formattedQuote =
              '${dailyQuote['content']}\n${dailyQuote['from_who'] != null && dailyQuote['from_who'].isNotEmpty ? '——${dailyQuote['from_who']}' : ''}${dailyQuote['from'] != null && dailyQuote['from'].isNotEmpty ? '《${dailyQuote['from']}》' : ''}';

          // 复制到剪贴板
          Clipboard.setData(ClipboardData(text: formattedQuote));
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.contentCopiedToClipboard),
              duration: AppConstants.snackBarDurationNormal,
            ),
          );
        },
        // 双击整个卡片区域快速保存到笔记
        onDoubleTap: () {
          widget.onAddQuote(
            dailyQuote['content'],
            dailyQuote['from_who'],
            dailyQuote['from'],
            dailyQuote,
          );
        },
        child: Padding(
          padding: EdgeInsets.zero, // 移除内边距，依靠SlidingCard的动态padding提供间距
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      dailyQuote['content'],
                      // 基准取 `titleLarge` 而不是 `headlineSmall`：一言在手机上
                      // 落在 20–22 这个「阅读字号」区间，而 `_applyStyleTypography`
                      // 只给 title* / body* 抬字重下限，headline* 只换字体族。
                      // 用 headline 当基准，衬线风格下这张卡就是整屏最大的一段
                      // w400 中文衬线——横画掉进半像素，看起来最虚的正好是最该
                      // 显眼的那句话。material 下两级都是 w400、字号又被覆盖，
                      // 像素不变。
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: (theme.textTheme.titleLarge?.fontSize ?? 22) *
                            _responsiveQuoteScale(screenWidth, screenHeight),
                        height: isVerySmallScreen ? 1.3 : 1.4, // 极小屏幕进一步减少行高
                      ),
                      textAlign: TextAlign.center,
                      maxLines: _getResponsiveMaxLines(
                        screenWidth,
                        screenHeight,
                      ),
                      overflow: screenWidth > 600
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis, // 小屏设备使用省略号
                    ),
                  ),
                  if (dailyQuote['from_who'] != null &&
                          dailyQuote['from_who'].isNotEmpty ||
                      dailyQuote['from'] != null &&
                          dailyQuote['from'].isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        top: isVerySmallScreen ? 8.0 : 12.0,
                      ), // 动态调整间距
                      child: Text(
                        formatHitokotoSource(
                          dailyQuote['from_who'],
                          dailyQuote['from'],
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: _getResponsiveSourceFontSize(
                            screenWidth,
                            screenHeight,
                          ),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
