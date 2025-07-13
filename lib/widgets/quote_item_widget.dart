import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../theme/app_theme.dart';
import 'dart:convert';
import '../widgets/quote_content_widget.dart';
import '../services/weather_service.dart';
import '../utils/time_utils.dart';
import '../utils/color_utils.dart'; // Import color_utils

/// 优化：使用StatelessWidget保持高性能，数据变化通过父组件管理
class QuoteItemWidget extends StatelessWidget {
  final Quote quote;
  final List<NoteCategory> tags;
  final bool isExpanded;
  final Function(bool) onToggleExpanded;
  final Function() onEdit;
  final Function() onDelete;
  final Function() onAskAI;
  final Function()? onGenerateCard;

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
    this.onGenerateCard,
    this.tagBuilder,
  });

  // 优化：缓存计算结果，避免重复计算
  static final Map<String, bool> _expansionCache = <String, bool>{};
  static int _cacheHitCount = 0; // 统计缓存命中次数

  /// 优化：判断是否需要展开按钮（富文本或长文本）- 带缓存
  bool _needsExpansion(Quote quote) {
    final cacheKey =
        '${quote.id}_${quote.content.length}_${quote.deltaContent?.length ?? 0}';

    if (_expansionCache.containsKey(cacheKey)) {
      _cacheHitCount++;
      return _expansionCache[cacheKey]!;
    }

    bool needsExpansion = false;

    // 新笔记（富文本）
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      try {
        final decoded = jsonDecode(quote.deltaContent!);
        if (decoded is List) {
          int lineCount = 0;
          int totalLength = 0;
          for (var op in decoded) {
            if (op is Map && op['insert'] != null) {
              final String insert = op['insert'].toString();
              // 每个\n算一行，且最后一段如果不是\n结尾也算一行
              final lines = insert.split('\n');
              lineCount += lines.length - 1;
              if (!insert.endsWith('\n') && insert.isNotEmpty) lineCount++;
              totalLength += insert.length;
            }
          }
          // 超过3行或内容长度超过150字符时显示折叠按钮
          needsExpansion = lineCount > 3 || totalLength > 150;
        }
      } catch (_) {
        // 富文本解析失败，回退到纯文本判断
        final int lineCount = 1 + '\n'.allMatches(quote.content).length;
        needsExpansion = lineCount > 3 || quote.content.length > 150;
      }
    } else {
      // 旧笔记（纯文本）
      final int lineCount = 1 + '\n'.allMatches(quote.content).length;
      needsExpansion = lineCount > 3 || quote.content.length > 150;
    }

    // 缓存结果
    _expansionCache[cacheKey] = needsExpansion;

    // 优化：限制缓存大小，防止内存泄漏，并清理最旧的缓存
    if (_expansionCache.length > 200) {
      final keysToRemove = _expansionCache.keys.take(50).toList();
      for (final key in keysToRemove) {
        _expansionCache.remove(key);
      }
    }

    return needsExpansion;
  }

  /// 清理缓存的静态方法（可在适当时机调用）
  static void clearExpansionCache() {
    _expansionCache.clear();
    _cacheHitCount = 0;
  }

  /// 获取缓存统计信息
  static Map<String, int> getCacheStats() {
    return {'cacheSize': _expansionCache.length, 'cacheHits': _cacheHitCount};
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
    // If the quote has a color, use it, otherwise use fixed color based on theme
    final Color cardColor =
        quote.colorHex != null && quote.colorHex!.isNotEmpty
            ? Color(
              int.parse(quote.colorHex!.substring(1), radix: 16) | 0xFF000000,
            ) // Ensure alpha for hex string
            : (theme.brightness == Brightness.light
                ? Colors.white
                : const Color(0xFF2D2D2D));

    // Determine the text color based on the card color

    // 格式化日期和时间段
    final DateTime quoteDate = DateTime.parse(quote.date);
    final String formattedDate = TimeUtils.formatQuoteDate(
      quoteDate,
      dayPeriod: quote.dayPeriod,
    );

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ), // 减少水平边距从16到12，垂直从8到6
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: AppTheme.defaultShadow,
        gradient:
            quote.colorHex != null && quote.colorHex!.isNotEmpty
                ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cardColor, cardColor.withValues(alpha: 0.95)],
                )
                : null,
        color:
            quote.colorHex == null || quote.colorHex!.isEmpty
                ? cardColor
                : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12), // 减少内边距从16到12
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部日期显示
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), // 减少左右边距，调整上下边距
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
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8), // 减少左右边距从16到4
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
                (quote.sourceWork != null && quote.sourceWork!.isNotEmpty)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8), // 减少左右边距从16到4
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
            ] else if (quote.source != null && quote.source!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8), // 减少左右边距从16到4
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

            // 底部工具栏
            Padding(
              padding: const EdgeInsets.fromLTRB(
                4,
                0,
                4,
                4,
              ), // 减少左边距从16到4，右边距从0到4，底部从8到4
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
                      child: Wrap(
                        spacing: 6.0, // 标签之间的水平间距
                        runSpacing: 4.0, // 行与行之间的垂直间距
                        children:
                            quote.tagIds.map((tagId) {
                              final tag = tags.firstWhere(
                                (t) => t.id == tagId,
                                orElse:
                                    () => NoteCategory(id: tagId, name: '未知标签'),
                              );
                              return tagBuilder != null
                                  ? tagBuilder!(tag)
                                  : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .applyOpacity(0.1), // MODIFIED
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      tag.name,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                  );
                            }).toList(),
                      ),
                    ),
                  ],

                  // 展开/折叠按钮（如果内容较长）
                  if (_needsExpansion(quote)) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => onToggleExpanded(!isExpanded),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isExpanded ? '收起' : '展开',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ],
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
                      } else if (value == 'generate_card') {
                        onGenerateCard?.call();
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
                          if (onGenerateCard != null)
                            PopupMenuItem<String>(
                              value: 'generate_card',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('生成卡片分享'),
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
    );
  }
}
