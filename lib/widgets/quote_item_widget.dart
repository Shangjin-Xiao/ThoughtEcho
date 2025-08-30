import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../theme/app_theme.dart';
import 'dart:convert';
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

            // 展开/折叠按钮（移到内容区域上方，避免与标签冲突）
            if (_needsExpansion(quote))
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    InkWell(
                      onTap: () => onToggleExpanded(!isExpanded),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isExpanded ? '收起' : '展开',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 3),
                            AnimatedRotation(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOutCubicEmphasized,
                              turns: isExpanded ? 0.5 : 0.0,
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 16,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 笔记内容 - 优化动画性能和视觉效果
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: _needsExpansion(quote)
                  ? () => onToggleExpanded(!isExpanded)
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 350), // 优化动画时长
                  curve: Curves.easeInOutCubicEmphasized,
                  alignment: Alignment.topCenter,
                  child: Stack(
                    children: [
                      QuoteContent(
                        quote: quote,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              height: 1.5,
                            ),
                        maxLines: isExpanded ? null : 3,
                        showFullContent: isExpanded,
                      ),
                      // 优化的底部渐隐遮罩 - 降低透明度，避免遮挡重要内容
                      if (!isExpanded && _needsExpansion(quote))
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 24, // 减少遮罩高度
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    (quote.colorHex == null || quote.colorHex!.isEmpty)
                                        ? theme.colorScheme.surfaceContainerLowest
                                            .withValues(alpha: 0.7) // 降低不透明度
                                        : cardColor.withValues(alpha: 0.8), // 降低不透明度
                                  ],
                                  stops: const [0.0, 0.8], // 渐变更自然
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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

            // 底部工具栏 - 优化标签展示为横向滚动
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Row(
                children: [
                  // 标签区域 - 改为横向滚动
                  if (quote.tagIds.isNotEmpty) ...[
                    Icon(
                      Icons.label_outline,
                      size: 16,
                      color: theme.colorScheme.onSurface.applyOpacity(0.6),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 32, // 固定高度确保滚动区域稳定
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: quote.tagIds.length,
                          itemBuilder: (context, index) {
                            final tagId = quote.tagIds[index];
                            final tag = tags.firstWhere(
                              (t) => t.id == tagId,
                              orElse: () => NoteCategory(id: tagId, name: '未知标签'),
                            );
                            
                            return Container(
                              margin: EdgeInsets.only(
                                right: index < quote.tagIds.length - 1 ? 6 : 0,
                              ),
                              child: tagBuilder != null
                                  ? tagBuilder!(tag)
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.applyOpacity(0.12),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (tag.iconName?.isNotEmpty == true) ...[
                                            if (IconUtils.isEmoji(tag.iconName!)) ...[
                                              Text(
                                                IconUtils.getDisplayIcon(tag.iconName!),
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                              const SizedBox(width: 3),
                                            ] else ...[
                                              Icon(
                                                IconUtils.getIconData(tag.iconName!),
                                                size: 12,
                                                color: theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 3),
                                            ],
                                          ],
                                          Text(
                                            tag.name,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.primary,
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
                  ],

                  // 添加Spacer确保操作按钮始终在右侧
                  const Spacer(),

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
                                    : theme.colorScheme.onSurface.applyOpacity(0.6),
                              ),
                              // 显示点击次数（如果大于0）
                              if (quote.favoriteCount > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade600,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: (quote.colorHex == null || quote.colorHex!.isEmpty)
                                            ? theme.colorScheme.surfaceContainerLowest
                                            : cardColor,
                                        width: 1.5,
                                      ),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      quote.favoriteCount > 99 ? '99+' : '${quote.favoriteCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        height: 1.0,
                                      ),
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

                  // 操作按钮
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: theme.colorScheme.onSurface.applyOpacity(0.7),
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
                    itemBuilder: (context) => [
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
      ),
    );
  }
}
