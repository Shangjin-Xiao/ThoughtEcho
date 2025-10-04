import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../theme/app_theme.dart';
import '../widgets/quote_content_widget.dart';
import '../services/weather_service.dart';
import '../utils/time_utils.dart';
import '../utils/color_utils.dart'; // Import color_utils
import '../utils/icon_utils.dart'; // 添加 IconUtils 导入

/// 优化：使用StatefulWidget以支持双击反馈动画，数据变化通过父组件管理
class QuoteItemWidget extends StatefulWidget {
  final Quote quote;
  final List<NoteCategory> tags;
  final bool isExpanded;
  final Function(bool) onToggleExpanded;
  final Function() onEdit;
  final Function() onDelete;
  final Function() onAskAI;
  final Function()? onGenerateCard;
  final Function()? onFavorite; // 新增：心形按钮点击回调
  final String? searchQuery;

  /// 自定义标签显示的构建器函数，接收一个标签对象，返回一个Widget
  final Widget Function(NoteCategory)? tagBuilder;
  final GlobalKey? favoriteButtonGuideKey;
  final GlobalKey? foldToggleGuideKey;

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
    this.searchQuery,
    this.favoriteButtonGuideKey,
    this.foldToggleGuideKey,
  });

  @override
  State<QuoteItemWidget> createState() => _QuoteItemWidgetState();

  // 动画优化：缩短时长以提升"干脆"感，同时保持缓动曲线的丝滑
  static const Duration expandCollapseDuration = Duration(milliseconds: 170);
  static const Duration _fadeDuration = Duration(milliseconds: 130);
  static const Curve _expandCurve = Curves.easeOutCubic;

  // 优化：缓存计算结果，避免重复计算
  static final Map<String, bool> _expansionCache = <String, bool>{};
  static int _cacheHitCount = 0; // 统计缓存命中次数

  /// 清理折叠判断缓存，常用于测试或手动刷新场景。
  static void clearExpansionCache() {
    _expansionCache.clear();
    _cacheHitCount = 0;
  }

  /// 获取折叠缓存当前状态，便于调试观察命中率。
  static Map<String, int> getCacheStats() {
    return {
      'cacheSize': _expansionCache.length,
      'cacheHits': _cacheHitCount,
    };
  }

  /// 测试辅助方法，等价于 [clearExpansionCache]。
  static void clearExpansionCacheForTest() => clearExpansionCache();

  /// 优化：基于高度判断是否需要展开按钮 - 带缓存
  /// 折叠策略说明：
  /// 1. 触发阈值：内容高度超过120像素时出现折叠/展开交互
  /// 2. 折叠展示：固定展示约3-4行的高度（120像素）
  /// 3. 目的：基于实际显示高度判断，解决图片导致的显示问题
  /// 4. 包含图片的内容会正常显示，避免因图片隐藏造成的矛盾
  static bool needsExpansionFor(Quote quote) {
    final cacheKey =
        '${quote.id}_${quote.content.length}_${quote.deltaContent?.length ?? 0}';

    if (_expansionCache.containsKey(cacheKey)) {
      _cacheHitCount++;
      return _expansionCache[cacheKey]!;
    }

    final bool needsExpansion = QuoteContent.exceedsCollapsedHeight(quote);

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
}

class _QuoteItemWidgetState extends State<QuoteItemWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _doubleTapController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _highlightProgress;

  @override
  void initState() {
    super.initState();

    _doubleTapController = AnimationController(
      duration: const Duration(milliseconds: 240),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 0.99)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.99, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
    ]).animate(_doubleTapController);

    _highlightProgress = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 40,
      ),
    ]).animate(_doubleTapController);
  }

  @override
  void dispose() {
    _doubleTapController.dispose();
    super.dispose();
  }

  bool _needsExpansion(Quote quote) => QuoteItemWidget.needsExpansionFor(quote);

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

  void _handleDoubleTap(bool isExpanded, Quote quote) {
    if (!_needsExpansion(quote)) {
      return;
    }

    _doubleTapController.stop();
    _doubleTapController.forward(from: 0.0);

    Feedback.forTap(context);

    widget.onToggleExpanded(!isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = widget.quote;
    final isExpanded = widget.isExpanded;
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

    return AnimatedContainer(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ), // 减少水平边距从16到12，垂直从8到6
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutQuad,
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

            // 笔记内容 - 支持双击展开/折叠
            GestureDetector(
        key: widget.foldToggleGuideKey ??
          const ValueKey('quote_item.double_tap_region'),
              behavior: HitTestBehavior.translucent,
              onDoubleTap: _needsExpansion(quote)
                  ? () => _handleDoubleTap(isExpanded, quote)
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Builder(
                  builder: (context) {
                    final innerTheme = Theme.of(context);
                    final needsExpansion = _needsExpansion(quote);
                    final showFullContent = isExpanded || !needsExpansion;

                    return AnimatedSize(
                      duration: QuoteItemWidget.expandCollapseDuration,
                      curve: QuoteItemWidget._expandCurve,
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      child: AnimatedBuilder(
                        animation: _doubleTapController,
                        builder: (context, _) {
                          final highlightOpacity = _highlightProgress.value;
                          final brightness = innerTheme.brightness;
                          final overlayStrength =
                              brightness == Brightness.dark ? 0.12 : 0.05;
                          final overlayColor = Colors.white.withValues(
                            alpha: overlayStrength * highlightOpacity,
                          );

                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            alignment: Alignment.topLeft,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                AnimatedSwitcher(
                                  duration: QuoteItemWidget._fadeDuration,
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  layoutBuilder:
                                      (currentChild, previousChildren) => Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ...previousChildren,
                                      if (currentChild != null) currentChild,
                                    ],
                                  ),
                                  child: KeyedSubtree(
                                    key: ValueKey<bool>(showFullContent),
                                    child: QuoteContent(
                                      quote: quote,
                                      style: innerTheme.textTheme.bodyLarge
                                          ?.copyWith(
                                        color: innerTheme.colorScheme.onSurface,
                                        height: 1.5,
                                      ),
                                      showFullContent: showFullContent,
                                    ),
                                  ),
                                ),
                                if (highlightOpacity > 0)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        key: const ValueKey(
                                            'quote_item.double_tap_overlay'),
                                        decoration: BoxDecoration(
                                          color: overlayColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 30,
                                  child: IgnorePointer(
                                    child: AnimatedSwitcher(
                                      duration: QuoteItemWidget._fadeDuration,
                                      switchInCurve: Curves.easeIn,
                                      switchOutCurve: Curves.easeOut,
                                      child: (!isExpanded && needsExpansion)
                                          ? ClipRect(
                                              child: BackdropFilter(
                                                filter: ui.ImageFilter.blur(
                                                  sigmaX: 1.2,
                                                  sigmaY: 1.2,
                                                ),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                      colors: [
                                                        innerTheme
                                                            .colorScheme.surface
                                                            .withValues(
                                                                alpha: 0.0),
                                                        innerTheme
                                                            .colorScheme.surface
                                                            .withValues(
                                                                alpha: 0.08),
                                                        innerTheme
                                                            .colorScheme.surface
                                                            .withValues(
                                                                alpha: 0.18),
                                                      ],
                                                      stops: const [
                                                        0.0,
                                                        0.4,
                                                        1.0
                                                      ],
                                                    ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: innerTheme
                                                          .colorScheme.surface
                                                          .withValues(
                                                              alpha: 0.35),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                    child: Text(
                                                      '双击查看全文',
                                                      style: innerTheme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: innerTheme
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha: 0.65),
                                                        fontSize: 11,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
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
                            final tag = widget.tags.firstWhere(
                              (t) => t.id == tagId,
                              orElse: () =>
                                  NoteCategory(id: tagId, name: '未知标签'),
                            );

                            return Container(
                              margin: EdgeInsets.only(
                                right: index < quote.tagIds.length - 1 ? 8 : 0,
                              ),
                              child: widget.tagBuilder != null
                                  ? widget.tagBuilder!(tag)
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .applyOpacity(0.12),
                                        borderRadius: BorderRadius.circular(14),
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
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 3),
                                            ],
                                          ],
                                          Text(
                                            tag.name,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
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
                  ] else ...[
                    const Expanded(child: SizedBox.shrink()),
                  ],

                  // 心形按钮（如果启用）
                  if (widget.onFavorite != null) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: widget.favoriteButtonGuideKey,
                        onTap: widget.onFavorite,
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
                                      borderRadius: BorderRadius.circular(10),
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
                        widget.onAskAI();
                      } else if (value == 'edit') {
                        widget.onEdit();
                      } else if (value == 'generate_card') {
                        widget.onGenerateCard?.call();
                      } else if (value == 'delete') {
                        widget.onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: theme.colorScheme.primary),
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
                      if (widget.onGenerateCard != null)
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
                                style:
                                    TextStyle(color: theme.colorScheme.error)),
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
