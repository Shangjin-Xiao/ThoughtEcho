import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../theme/app_theme.dart';
import 'dart:convert';
import '../widgets/quote_content_widget.dart';
import '../services/weather_service.dart';
import '../utils/time_utils.dart';
import '../utils/color_utils.dart'; // Import color_utils

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
    // 新笔记（富文本）
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      try {
        final decoded = jsonDecode(quote.deltaContent!);
        if (decoded is List) {
          int paragraphCount = 0;
          int totalLength = 0;
          for (var op in decoded) {
            if (op is Map && op['insert'] != null) {
              final String insert = op['insert'].toString();
              totalLength += insert.length;
              paragraphCount += '\n'.allMatches(insert).length;
            }
          }
          return paragraphCount > 3 || totalLength > 100;
        }
      } catch (_) {}
    }
    // 旧笔记（纯文本）
    final int paragraphCount = '\n'.allMatches(quote.content).length;
    return paragraphCount > 3 || quote.content.length > 100;
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

  // 根据天气key获取图标
  IconData _getWeatherIcon(String weatherKey) {
    return WeatherService.getWeatherIconDataByKey(weatherKey);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final colorScheme = Theme.of(context).colorScheme; // REMOVED unused variable

    // Determine the background color of the card
    // If the quote has a color, use it, otherwise use the theme's surface container high color
    final Color cardColor =
        quote.colorHex != null && quote.colorHex!.isNotEmpty
            ? Color(
              int.parse(quote.colorHex!.substring(1), radix: 16) | 0xFF000000,
            ) // Ensure alpha for hex string
            : theme.colorScheme.surfaceContainerHigh;

    // Determine the text color based on the card color

    // 格式化日期和时间段
    final DateTime quoteDate = DateTime.parse(quote.date);
    String dayPeriodLabel = '';
    if (quote.dayPeriod != null && quote.dayPeriod!.isNotEmpty) {
      dayPeriodLabel = TimeUtils.getDayPeriodLabel(quote.dayPeriod!);
    }
    final String formattedDate =
        '${quoteDate.year}-${quoteDate.month.toString().padLeft(2, '0')}-${quoteDate.day.toString().padLeft(2, '0')} $dayPeriodLabel';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        color: cardColor,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.applyOpacity(
                    0.08,
                  ), // 使用 applyOpacity 替代 withOpacity
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
                          color: theme.colorScheme.onSurface.applyOpacity(
                            0.7,
                          ), // MODIFIED
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
                                color: theme.colorScheme.secondary.applyOpacity(
                                  // MODIFIED
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
                                color: theme.colorScheme.secondary.applyOpacity(
                                  // MODIFIED
                                  0.7,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${WeatherService.getWeatherDescription(quote.weather!)}${quote.temperature != null ? ' ${quote.temperature}' : ''}',
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
                        color: theme.colorScheme.onSurface.applyOpacity(
                          0.75,
                        ), // MODIFIED
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
                        color: theme.colorScheme.onSurface.applyOpacity(
                          0.75,
                        ), // MODIFIED
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
                          color: theme.colorScheme.onSurface.applyOpacity(
                            0.6,
                          ), // MODIFIED
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
                                                .applyOpacity(0.1), // MODIFIED
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

                      // 添加Spacer确保更多按钮始终在右侧
                      const Spacer(),

                      // 操作按钮
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: theme.colorScheme.onSurface.applyOpacity(
                            0.7,
                          ), // MODIFIED
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
