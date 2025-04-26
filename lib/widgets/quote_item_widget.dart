import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../theme/app_theme.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import '../widgets/quote_content_widget.dart';

class QuoteItemWidget extends StatelessWidget {
  final Quote quote;
  final List<NoteCategory> tags;
  final bool isExpanded;
  final Function(bool) onToggleExpanded;
  final Function() onEdit;
  final Function() onDelete;
  final Function() onAskAI;

  /// 自定义标签显示的构建器函数，接收一个标签对象，返回一个Widget
  final Widget Function(NoteCategory)? tagBuilder;

  const QuoteItemWidget({
    super.key,
    required this.quote,
    required this.tags,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onDelete,
    required this.onAskAI,
    this.tagBuilder,
  });

  // 判断是否需要展开按钮（富文本或长文本）
  bool _needsExpansion(Quote quote) {
    // 对于普通文本，检查长度
    if (quote.deltaContent == null) {
      return quote.content.length > 100;
    }

    // 对于富文本，尝试解析并检查段落数
    try {
      final decoded = jsonDecode(quote.deltaContent!);
      if (decoded is List) {
        // 计算段落标记数量
        return decoded
                .where(
                  (op) =>
                      op is Map &&
                      op['insert'] != null &&
                      op['insert'].toString().contains('\n'),
                )
                .length >
            3;
      }
    } catch (_) {}

    // 默认根据内容长度判断
    return quote.content.length > 100;
  }

  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      result += ' 《$work》';
    }

    return result;
  }

  // 根据天气描述获取图标
  IconData _getWeatherIcon(String weather) {
    if (weather.contains('晴')) return Icons.wb_sunny;
    if (weather.contains('云') || weather.contains('阴')) return Icons.cloud;
    if (weather.contains('雾') || weather.contains('霾')) return Icons.cloud;
    if (weather.contains('雨') && weather.contains('雷')) return Icons.flash_on;
    if (weather.contains('雨')) return Icons.water_drop;
    if (weather.contains('雪')) return Icons.ac_unit;
    if (weather.contains('风')) return Icons.air;
    return Icons.cloud_queue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 格式化日期和时间段
    final DateTime quoteDate = DateTime.parse(quote.date);
    final int hour = quoteDate.hour;
    String timeOfDay;
    // 使用更诗意的表述
    if (hour >= 5 && hour < 9) {
      timeOfDay = '晨曦'; // 5:00 - 8:59
    } else if (hour >= 9 && hour < 12) {
      timeOfDay = '清晨'; // 9:00 - 11:59
    } else if (hour >= 12 && hour < 14) {
      timeOfDay = '正午'; // 12:00 - 13:59
    } else if (hour >= 14 && hour < 17) {
      timeOfDay = '午后'; // 14:00 - 16:59
    } else if (hour >= 17 && hour < 19) {
      timeOfDay = '黄昏'; // 17:00 - 18:59
    } else if (hour >= 19 && hour < 23) {
      timeOfDay = '夜晚'; // 19:00 - 22:59
    } else {
      timeOfDay = '深夜';
    }
    final String formattedDate =
        '${quoteDate.year}-${quoteDate.month.toString().padLeft(2, '0')}-${quoteDate.day.toString().padLeft(2, '0')} $timeOfDay';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        color:
            quote.colorHex != null
                ? Color(
                  int.parse(quote.colorHex!.substring(1), radix: 16) |
                      0xFF000000,
                )
                : theme.colorScheme.surfaceContainerHighest,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              color: Colors.transparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部日期显示
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formattedDate,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      if (quote.location != null || quote.weather != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (quote.location != null) ...[
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: theme.colorScheme.secondary.withOpacity(
                                  0.7,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                quote.location!.split(',').length >= 3
                                    ? (quote.location!.split(',').length >= 4
                                        ? '${quote.location!.split(',')[2]}·${quote.location!.split(',')[3]}' // 显示 "城市·区县"
                                        : quote.location!.split(',')[2]) // 只有城市
                                    : quote.location!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (quote.location != null && quote.weather != null)
                              const SizedBox(width: 8),
                            if (quote.weather != null) ...[
                              Icon(
                                _getWeatherIcon(quote.weather!),
                                size: 14,
                                color: theme.colorScheme.secondary.withOpacity(
                                  0.7,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${quote.weather!}${quote.temperature != null ? ' ${quote.temperature}' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),

                // 笔记内容 - 使用QuoteContent组件替换
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: QuoteContent(
                    quote: quote,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.5,
                    ),
                    maxLines: isExpanded ? null : 3,
                    showFullContent: isExpanded,
                  ),
                ),

                // 来源信息（如果有）
                if ((quote.sourceAuthor != null &&
                        quote.sourceAuthor!.isNotEmpty) ||
                    (quote.sourceWork != null &&
                        quote.sourceWork!.isNotEmpty)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      _formatSource(
                        quote.sourceAuthor ?? '',
                        quote.sourceWork ?? '',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ] else if (quote.source != null &&
                    quote.source!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      quote.source!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],

                // 展开/折叠按钮（如果内容较长）
                if (_needsExpansion(quote)) ...[
                  Center(
                    child: TextButton(
                      onPressed: () => onToggleExpanded(!isExpanded),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isExpanded ? '收起' : '展开全部',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 12,
                            ),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // 底部工具栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 0, 8),
                  child: Row(
                    children: [
                      // 标签信息
                      if (quote.tagIds.isNotEmpty) ...[
                        Icon(
                          Icons.label_outline,
                          size: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children:
                                  quote.tagIds.map((tagId) {
                                    final tag = tags.firstWhere(
                                      (t) => t.id == tagId,
                                      orElse:
                                          () => NoteCategory(
                                            id: tagId,
                                            name: '未知标签',
                                          ),
                                    );
                                    return tagBuilder != null
                                        ? tagBuilder!(tag)
                                        : Container(
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary
                                                .withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            tag.name,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                          ),
                                        );
                                  }).toList(),
                            ),
                          ),
                        ),
                      ],

                      // 操作按钮
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (value) {
                          if (value == 'ask') {
                            onAskAI();
                          } else if (value == 'edit') {
                            onEdit();
                          } else if (value == 'delete') {
                            onDelete();
                          }
                        },
                        itemBuilder:
                            (context) => [
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('编辑笔记'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'ask',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.question_answer,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('向AI提问'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text(
                                      '删除笔记',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
