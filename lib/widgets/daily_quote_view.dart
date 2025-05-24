import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../widgets/sliding_card.dart';
import 'dart:async'; // Import async for StreamController and StreamSubscription

class DailyQuoteView extends StatefulWidget {
  // 修改接口，增加hitokotoData参数，以便传递完整的一言数据
  final Function(String, String?, String?, Map<String, dynamic>) onAddQuote;
  // 新增：外部刷新回调，用于通知首页刷新每日提示
  final Future<void> Function()? onRefreshRequested;

  const DailyQuoteView({
    super.key, 
    required this.onAddQuote,
    this.onRefreshRequested,
  });

  @override
  State<DailyQuoteView> createState() => _DailyQuoteViewState();
}

class _DailyQuoteViewState extends State<DailyQuoteView> {
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

        debugPrint('获取一言失败: $e');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);    return RefreshIndicator(
      onRefresh: () async {
        // 刷新一言
        await _loadDailyQuote();
        // 如果提供了外部刷新回调，同时刷新每日提示
        if (widget.onRefreshRequested != null) {
          await widget.onRefreshRequested!();
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height:
              MediaQuery.of(context).size.height -
              kToolbarHeight -
              MediaQuery.of(context).padding.top -
              kBottomNavigationBarHeight,
          child: Column(
            children: [
              Expanded(
                child: SlidingCard(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          // 单击复制内容
                          final String formattedQuote =
                              '${dailyQuote['content']}\n${dailyQuote['from_who'] != null && dailyQuote['from_who'].isNotEmpty ? '——${dailyQuote['from_who']}' : ''}${dailyQuote['from'] != null && dailyQuote['from'].isNotEmpty ? '《${dailyQuote['from']}》' : ''}';

                          // 复制到剪贴板
                          Clipboard.setData(
                            ClipboardData(text: formattedQuote),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制到剪贴板')),
                          );
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
                          children: [
                            Text(
                              dailyQuote['content'],
                              style: theme.textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            if (dailyQuote['from_who'] != null &&
                                    dailyQuote['from_who'].isNotEmpty ||
                                dailyQuote['from'] != null &&
                                    dailyQuote['from'].isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  formatHitokotoSource(
                                    dailyQuote['from_who'],
                                    dailyQuote['from'],
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
