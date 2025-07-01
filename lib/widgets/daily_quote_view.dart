import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../widgets/sliding_card.dart';
import 'dart:async'; // Import async for StreamController and StreamSubscription
import 'package:thoughtecho/utils/app_logger.dart';

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
      final hitokotoType = settingsService.appSettings.hitokotoType;

      setState(() {
        dailyQuote = {
          'content': '加载中...',
          'source': '',
          'author': '',
          'type': 'a',
        };
      });

      final quote = await ApiService.getDailyQuote(hitokotoType);
      if (mounted) {
        setState(() {
          dailyQuote = quote;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          dailyQuote = {
            'content': '获取一言失败，点击重试',
            'source': '',
            'author': '',
            'type': 'error',
          };
        });

        // 添加重试机制，3秒后自动重试一次
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _loadDailyQuote();
          }
        });

        logDebug('获取一言失败: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('获取一言失败: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: '重试',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      // 去掉固定高度，让容器适应父组件的尺寸
      width: double.infinity,
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth > 600 ? 16.0 : 12.0,
        vertical: 16.0,
      ),
      child: SlidingCard(
        child: Padding(
          padding: EdgeInsets.all(screenWidth > 600 ? 12.0 : 4.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  // 单击复制内容
                  final String formattedQuote =
                      '${dailyQuote['content']}\n${dailyQuote['from_who'] != null && dailyQuote['from_who'].isNotEmpty ? '——${dailyQuote['from_who']}' : ''}${dailyQuote['from'] != null && dailyQuote['from'].isNotEmpty ? '《${dailyQuote['from']}》' : ''}';

                  // 复制到剪贴板
                  Clipboard.setData(ClipboardData(text: formattedQuote));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                },
                onDoubleTap: () {
                  // 双击添加到笔记，同时传递完整的一言数据以便根据类型添加标签
                  widget.onAddQuote(
                    dailyQuote['content'],
                    dailyQuote['from_who'],
                    dailyQuote['from'],
                    dailyQuote,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        dailyQuote['content'],
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: screenWidth > 600 ? 30 : 24, // 再次增大字体
                          height: 1.5, // 增加行高，提升可读性
                          fontWeight: FontWeight.w500, // 稍微加粗
                        ),
                        textAlign: TextAlign.center,
                        // 去掉行数限制，让文字完全展示
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    if (dailyQuote['from_who'] != null &&
                            dailyQuote['from_who'].isNotEmpty ||
                        dailyQuote['from'] != null &&
                            dailyQuote['from'].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(
                          formatHitokotoSource(
                            dailyQuote['from_who'],
                            dailyQuote['from'],
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            fontSize: screenWidth > 600 ? 14 : 12,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
