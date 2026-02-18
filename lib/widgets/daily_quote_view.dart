import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/sliding_card.dart';
import 'dart:async'; // Import async for StreamController and StreamSubscription
import 'package:thoughtecho/utils/app_logger.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class DailyQuoteView extends StatefulWidget {
  // 修改接口，增加hitokotoData参数，以便传递完整的一言数据
  final Function(String, String?, String?, Map<String, dynamic>) onAddQuote;

  const DailyQuoteView({super.key, required this.onAddQuote});

  @override
  DailyQuoteViewState createState() => DailyQuoteViewState();
}

class DailyQuoteViewState extends State<DailyQuoteView> {
  Map<String, dynamic> dailyQuote = {
    'content': '加载中...',
    'source': '',
    'author': '',
    'type': 'a',
  };

  @override
  void initState() {
    super.initState();
    _loadDailyQuote();
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

      final hitokotoType = settingsService.appSettings.hitokotoType;
      final useLocalOnly = settingsService.appSettings.useLocalQuotesOnly;
      final isConnected = connectivityService.isConnected;

      setState(() {
        if (useLocalOnly) {
          dailyQuote = {
            'content': '从本地记录加载中...',
            'source': '',
            'author': '',
            'type': 'local',
          };
        } else if (!isConnected) {
          dailyQuote = {
            'content': '网络未连接，从本地记录加载中...',
            'source': '',
            'author': '',
            'type': 'offline',
          };
        } else {
          dailyQuote = {
            'content': '加载中...',
            'source': '',
            'author': '',
            'type': 'a',
          };
        }
      });

      final l10n = AppLocalizations.of(context);
      final quote = await ApiService.getDailyQuote(
        l10n,
        hitokotoType,
        useLocalOnly: useLocalOnly,
        databaseService: databaseService,
      );

      if (mounted) {
        setState(() {
          dailyQuote = quote;
        });
      }
    } catch (e) {
      if (mounted) {
        final isConnected = Provider.of<ConnectivityService>(
          context,
          listen: false,
        ).isConnected;

        setState(() {
          if (!isConnected) {
            dailyQuote = {
              'content': '无网络连接且无本地记录，点击重试',
              'source': '',
              'author': '',
              'type': 'error',
            };
          } else {
            dailyQuote = {
              'content': '获取一言失败，点击重试',
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.fetchHitokotoFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: l10n.retry,
              onPressed: _loadDailyQuote,
              textColor: Colors.white,
            ),
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

  // 公开刷新方法，供父组件调用
  Future<void> refreshQuote() async {
    await _loadDailyQuote();
  }

  // 响应式字体大小计算
  double _getResponsiveFontSize(double screenWidth, double screenHeight) {
    if (screenHeight < 550) {
      // 极小屏设备
      return screenWidth > 600 ? 26 : (screenWidth > 400 ? 18 : 16);
    } else if (screenHeight < 600) {
      // 小屏设备
      return screenWidth > 600 ? 28 : (screenWidth > 400 ? 20 : 18);
    } else {
      // 普通屏幕
      return screenWidth > 600 ? 30 : (screenWidth > 400 ? 22 : 20);
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
        vertical: isVerySmallScreen
            ? 8.0
            : (isSmallScreen ? 12.0 : 16.0), // 动态调整垂直边距
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
        // 双击整个卡片区域快速添加到笔记
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
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: _getResponsiveFontSize(
                          screenWidth,
                          screenHeight,
                        ),
                        height: isVerySmallScreen ? 1.3 : 1.4, // 极小屏幕进一步减少行高
                        fontWeight: FontWeight.w500,
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
                          fontStyle: FontStyle.italic,
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
