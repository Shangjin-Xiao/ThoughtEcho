import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/ai_service.dart';
import '../services/settings_service.dart';
import '../widgets/sliding_card.dart';
import '../utils/color_utils.dart'; // Import color_utils

class DailyQuoteView extends StatefulWidget {
  // 修改接口，增加hitokotoData参数，以便传递完整的一言数据
  final Function(String, String?, String?, Map<String, dynamic>) onAddQuote;

  const DailyQuoteView({super.key, required this.onAddQuote});

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
  String? dailyPrompt;

  @override
  void initState() {
    super.initState();
    _loadDailyQuote();
    _fetchDailyPrompt();
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

  Future<void> _fetchDailyPrompt() async {
    try {
      final aiService = context.read<AIService>();
      final prompt = await aiService.generateDailyPrompt();
      if (mounted) {
        setState(() {
          dailyPrompt = prompt;
        });
      }
    } catch (e) {
      debugPrint('获取每日提示失败: $e');
      // 添加重试机制
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _fetchDailyPrompt();
        }
      });
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
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadDailyQuote(), _fetchDailyPrompt()]);
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
                              '${dailyQuote['content']}\n${dailyQuote['from_who'] != null &&
                                      dailyQuote['from_who'].isNotEmpty
                                  ? '——${dailyQuote['from_who']}'
                                  : ''}${dailyQuote['from'] != null &&
                                      dailyQuote['from'].isNotEmpty
                                  ? '《${dailyQuote['from']}》'
                                  : ''}';

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
              if (dailyPrompt != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.applyOpacity(0.26), // MODIFIED
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '今日思考',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dailyPrompt!,
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
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
