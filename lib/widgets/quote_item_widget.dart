import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../theme/app_theme.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import '../widgets/quote_content_widget.dart';
import '../services/weather_service.dart';
import '../utils/time_utils.dart';
import '../utils/color_utils.dart'; // Import color_utils
import '../utils/icon_utils.dart'; // 添加 IconUtils 导入
import '../constants/app_constants.dart';

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
  final Function()? onFavorite; // 新增：心形按钮点击回调

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
    this.onFavorite, // 新增：心形按钮点击回调
    this.tagBuilder,
  });

  // 优化：缓存计算结果，避免重复计算
  static final Map<String, bool> _expansionCache = <String, bool>{};
  static int _cacheHitCount = 0; // 统计缓存命中次数

  /// 优化：判断是否需要展开按钮（富文本或长文本）- 带缓存
  /// 折叠策略说明：
  /// 1. 触发阈值：逻辑行数 > 4 或 字符数 > 150 才会出现折叠/展开交互。
  /// 2. 折叠展示：固定展示 4 行（maxLines=4）。
  /// 3. 目的：避免折叠后比短内容更短造成突兀，同时不对稍长文本过早折叠。
  /// 4. 逻辑行的统计方式：按换行符拆分，富文本拆分每个Delta insert段。
  /// 5. 若富文本中包含换行较少但有长行自动换行，视觉行可能多于4，后续如需严格视觉裁剪再单独实现。
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
          // 超过4行或内容长度超过150字符时显示折叠按钮（与富文本内部阈值保持一致）
          needsExpansion = lineCount > 4 || totalLength > 150;
        }
      } catch (_) {
        // 富文本解析失败，回退到纯文本判断
        final int lineCount = 1 + '\n'.allMatches(quote.content).length;
        needsExpansion = lineCount > 4 || quote.content.length > 150;
      }
    } else {
      // 旧笔记（纯文本）
      final int lineCount = 1 + '\n'.allMatches(quote.content).length;
      needsExpansion = lineCount > 4 || quote.content.length > 150;
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
    // If the quote has a color, use it, otherwise use theme color
    final Color cardColor = quote.colorHex != null && quote.colorHex!.isNotEmpty
        ? Color(
            int.parse(quote.colorHex!.substring(1), radix: 16) | 0xFF000000,
          ) // Ensure alpha for hex string
        : theme.colorScheme.surfaceContainerLowest;

    // Determine the text color based on the card color

    // 格式化日期和时间段
    final DateTime quoteDate = DateTime.parse(quote.date);
    final String formattedDate = TimeUtils.formatQuoteDate(
      quoteDate,
      dayPeriod: quote.dayPeriod,
    );

    return AnimatedScale(
        duration: AppConstants.defaultAnimationDuration,
        curve: Curves.easeInOutCubic,
        scale: isExpanded ? 1.0 : 0.997, // 细微缩放，提升过渡质感
        child: AnimatedContainer(
          margin: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ), // 减少水平边距从16到12，垂直从8到6
          duration: AppConstants.defaultAnimationDuration,
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            boxShadow: isExpanded
                ? [
                    // 轻微增强阴影，提升展开时的质感
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : AppTheme.defaultShadow,
            gradient: quote.colorHex != null && quote.colorHex!.isNotEmpty
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cardColor, cardColor.withValues(alpha: 0.95)],
                  )
                : null,
            color: quote.colorHex == null || quote.colorHex!.isEmpty
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
                  padding:
                      const EdgeInsets.fromLTRB(4, 0, 4, 8), // 减少左右边距，调整上下边距
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

                // 笔记内容 - 支持双击展开/折叠
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _needsExpansion(quote)
                      ? () => onToggleExpanded(!isExpanded)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Stack(
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOutCubicEmphasized,
                          alignment: Alignment.topCenter,
                          child: QuoteContent(
                            quote: quote,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  height: 1.5,
                                ),
                            maxLines: isExpanded ? null : 4,
                            showFullContent: isExpanded,
                          ),
                        ),
                        if (!isExpanded && _needsExpansion(quote))
                          // 折叠遮罩设计：
                          // 1) 模糊降低到 1.2，避免“糊一片”压迫感，仅轻微区隔。
                          // 2) 上浅下深渐变（透明 -> 0.04 -> 0.08）营造“还有内容”暗示，不生硬。
                          // 3) 使用 IgnorePointer 不阻挡双击展开手势。
                          // 4) 中央提示文字放入半透明胶囊背景，增强可读性同时不影响下方内容整体感。
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 22, // 渐变遮罩高度
                            child: IgnorePointer(
                              // 不阻挡双击
                              child: ClipRect(
                                child: BackdropFilter(
                                  // 降低模糊强度（3 -> 1.2），更轻柔
                                  filter: ui.ImageFilter.blur(
                                      sigmaX: 1.2, sigmaY: 1.2),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      // 上浅下深渐变：顶部透明，底部明显以提示还有内容
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          theme.colorScheme.surface
                                              .withValues(alpha: 0.0),
                                          theme.colorScheme.surface
                                              .withValues(alpha: 0.08),
                                          theme.colorScheme.surface
                                              .withValues(alpha: 0.18),
                                        ],
                                        stops: const [0.0, 0.4, 1.0],
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface
                                            .withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '双击查看全文',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.65),
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // 来源信息（如果有）
                if ((quote.sourceAuthor != null &&
                        quote.sourceAuthor!.isNotEmpty) ||
                    (quote.sourceWork != null &&
                        quote.sourceWork!.isNotEmpty)) ...[
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(4, 4, 4, 8), // 减少左右边距从16到4
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
                    padding:
                        const EdgeInsets.fromLTRB(4, 4, 4, 8), // 减少左右边距从16到4
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

                // 底部工具栏 - 标签、心形和更多按钮在同一行
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Row(
                    children: [
                      if (quote.tagIds.isNotEmpty) ...[
                        Icon(
                          Icons.label_outline,
                          size: 16,
                          color: theme.colorScheme.onSurface.applyOpacity(0.6),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: quote.tagIds.length,
                              itemBuilder: (context, index) {
                                final tagId = quote.tagIds[index];
                                final tag = tags.firstWhere(
                                  (t) => t.id == tagId,
                                  orElse: () =>
                                      NoteCategory(id: tagId, name: '未知标签'),
                                );

                                return Container(
                                  margin: EdgeInsets.only(
                                    right:
                                        index < quote.tagIds.length - 1 ? 8 : 0,
                                  ),
                                  child: tagBuilder != null
                                      ? tagBuilder!(tag)
                                      : Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary
                                                .applyOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: 0.3),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (tag.iconName?.isNotEmpty ==
                                                  true) ...[
                                                if (IconUtils.isEmoji(
                                                    tag.iconName!)) ...[
                                                  Text(
                                                    IconUtils.getDisplayIcon(
                                                        tag.iconName!),
                                                    style: const TextStyle(
                                                        fontSize: 12),
                                                  ),
                                                  const SizedBox(width: 3),
                                                ] else ...[
                                                  Icon(
                                                    IconUtils.getIconData(
                                                        tag.iconName!),
                                                    size: 12,
                                                    color: theme
                                                        .colorScheme.primary,
                                                  ),
                                                  const SizedBox(width: 3),
                                                ],
                                              ],
                                              Text(
                                                tag.name,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                );
                              },
                            ),
                          ),
                        ),
                      ] else ...[
                        const Expanded(child: SizedBox.shrink()),
                      ],

                      // 心形按钮（如果启用）
                      if (onFavorite != null) ...[
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onFavorite,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Stack(
                                children: [
                                  Icon(
                                    quote.favoriteCount > 0
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 20,
                                    color: quote.favoriteCount > 0
                                        ? Colors.red.shade400
                                        : theme.colorScheme.onSurface
                                            .applyOpacity(0.6),
                                  ),
                                  if (quote.favoriteCount > 0)
                                    Positioned(
                                      right: -2,
                                      top: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade600,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: (quote.colorHex == null ||
                                                    quote.colorHex!.isEmpty)
                                                ? theme.colorScheme
                                                    .surfaceContainerLowest
                                                : cardColor,
                                            width: 1.5,
                                          ),
                                        ),
                                        constraints: const BoxConstraints(
                                            minWidth: 16, minHeight: 16),
                                        child: Text(
                                          quote.favoriteCount > 99
                                              ? '99+'
                                              : '${quote.favoriteCount}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              height: 1.0),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],

                      // 更多操作按钮
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: theme.colorScheme.onSurface.applyOpacity(0.7),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                const Text('编辑笔记'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'ask',
                            child: Row(
                              children: [
                                Icon(Icons.question_answer,
                                    color: theme.colorScheme.primary),
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
                                  Icon(Icons.auto_awesome,
                                      color: theme.colorScheme.primary),
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
                                Text('删除笔记',
                                    style: TextStyle(
                                        color: theme.colorScheme.error)),
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
        ));
  }
}
