import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../theme/app_theme.dart';
import '../widgets/quote_content_widget.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../utils/time_utils.dart';
import '../utils/icon_utils.dart'; // 添加 IconUtils 导入
import '../gen_l10n/app_localizations.dart';

/// 优化：使用StatefulWidget以支持双击反馈动画，数据变化通过父组件管理
class QuoteItemWidget extends StatefulWidget {
  final Quote quote;
  final Map<String, NoteCategory> tagMap;
  final bool isExpanded;
  final Function(bool) onToggleExpanded;
  final Function() onEdit;
  final Function() onDelete;
  final Function() onAskAI;
  final Function()? onGenerateCard;
  final Function()? onFavorite; // 心形按钮点击回调
  final Function()? onLongPressFavorite; // 心形按钮长按回调（清除收藏）
  final String? searchQuery;

  /// 自定义标签显示的构建器函数，接收一个标签对象，返回一个Widget
  final Widget Function(NoteCategory)? tagBuilder;
  final GlobalKey? favoriteButtonGuideKey;
  final GlobalKey? foldToggleGuideKey;
  final GlobalKey? moreButtonGuideKey; // 功能引导：更多按钮 Key

  /// 当前筛选的标签ID列表，用于优先显示匹配的标签
  final List<String> selectedTagIds;

  const QuoteItemWidget({
    super.key,
    required this.quote,
    required this.tagMap,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onDelete,
    required this.onAskAI,
    this.onGenerateCard,
    this.onFavorite, // 心形按钮点击回调
    this.onLongPressFavorite, // 心形按钮长按回调（清除收藏）
    this.tagBuilder,
    this.searchQuery,
    this.favoriteButtonGuideKey,
    this.foldToggleGuideKey,
    this.moreButtonGuideKey,
    this.selectedTagIds = const [],
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
    return {'cacheSize': _expansionCache.length, 'cacheHits': _cacheHitCount};
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
    // 性能优化：使用内容哈希作为缓存 key，提升命中率
    final contentHash = quote.deltaContent?.hashCode ?? quote.content.hashCode;
    final cacheKey = '${quote.id}_$contentHash';

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
        tween: Tween<double>(
          begin: 1.0,
          end: 0.99,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0.99,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
    ]).animate(_doubleTapController);

    _highlightProgress = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOutQuad)),
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

  /// 对标签ID列表进行排序，优先显示匹配筛选条件的标签
  List<String> _getSortedTagIds(
    List<String> tagIds,
    List<String> selectedTagIds,
  ) {
    if (selectedTagIds.isEmpty) {
      // 没有筛选条件时，按原顺序返回
      return tagIds;
    }

    // 将标签分为两组：匹配筛选条件的和其他的
    final matchedTags = <String>[];
    final otherTags = <String>[];

    for (final tagId in tagIds) {
      if (selectedTagIds.contains(tagId)) {
        matchedTags.add(tagId);
      } else {
        otherTags.add(tagId);
      }
    }

    // 先显示匹配的标签，再显示其他标签
    return [...matchedTags, ...otherTags];
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
    final l10n = AppLocalizations.of(context);
    final quote = widget.quote;
    final isExpanded = widget.isExpanded;

    // Determine the background color of the card
    // If the quote has a color, use it, otherwise use theme color
    final Color cardColor = quote.colorHex != null && quote.colorHex!.isNotEmpty
        ? Color(
            int.parse(quote.colorHex!.substring(1), radix: 16) | 0xFF000000,
          ) // Ensure alpha for hex string
        : theme.colorScheme.surfaceContainerLowest;

    // 修复深色模式下自定义颜色卡片的对比度问题
    // 计算卡片背景的亮度，决定内容颜色
    final bool isLightCard =
        ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light;
    final Color baseContentColor = isLightCard ? Colors.black : Colors.white;

    final Color primaryTextColor = baseContentColor.withValues(alpha: 0.9);
    final Color secondaryTextColor = baseContentColor.withValues(alpha: 0.7);
    final Color iconColor = baseContentColor.withValues(alpha: 0.65);

    // Determine the text color based on the card color

    // 格式化日期和时间段（支持国际化和精确时间显示）
    final DateTime quoteDate = DateTime.parse(quote.date);
    final showExactTime = context.select<SettingsService, bool>(
      (s) => s.showExactTime,
    );
    final String formattedDate = TimeUtils.formatQuoteDateLocalized(
      context,
      quoteDate,
      dayPeriod: quote.dayPeriod,
      showExactTime: showExactTime,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: isExpanded
            ? [
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
                      color: secondaryTextColor,
                    ),
                  ),
                  if (quote.hasLocation || quote.weather != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (quote.hasLocation) ...[
                          Icon(Icons.location_on, size: 14, color: iconColor),
                          const SizedBox(width: 2),
                          Text(
                            // 优先显示文字位置，没有文字位置时显示坐标
                            (quote.location != null &&
                                    LocationService.formatLocationForDisplay(
                                      quote.location,
                                    ).isNotEmpty)
                                ? LocationService.formatLocationForDisplay(
                                    quote.location,
                                  )
                                : LocationService.formatCoordinates(
                                    quote.latitude,
                                    quote.longitude,
                                  ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (quote.hasLocation && quote.weather != null)
                          const SizedBox(width: 8),
                        if (quote.weather != null) ...[
                          Icon(
                            _getWeatherIcon(quote.weather!),
                            size: 14,
                            color: iconColor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${WeatherService.getLocalizedWeatherDescription(AppLocalizations.of(context), quote.weather!)}${quote.temperature != null ? ' ${quote.temperature}' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondaryTextColor,
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
              key:
                  widget.foldToggleGuideKey ??
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

                    // 构建不依赖双击动画的内容子树（QuoteContent + 底部遮罩）
                    // 作为 AnimatedBuilder 的 child 传入，避免动画 tick 时重建重型子树
                    final contentChild = Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedSwitcher(
                          duration: QuoteItemWidget._fadeDuration,
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
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
                              style: innerTheme.textTheme.bodyLarge?.copyWith(
                                color: primaryTextColor,
                                height: 1.5,
                              ),
                              showFullContent: showFullContent,
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
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                innerTheme.colorScheme.surface
                                                    .withValues(alpha: 0.0),
                                                innerTheme.colorScheme.surface
                                                    .withValues(alpha: 0.08),
                                                innerTheme.colorScheme.surface
                                                    .withValues(alpha: 0.18),
                                              ],
                                              stops: const [0.0, 0.4, 1.0],
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: innerTheme
                                                  .colorScheme
                                                  .surface
                                                  .withValues(alpha: 0.35),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              l10n.doubleTapToViewFull,
                                              style: innerTheme
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: innerTheme
                                                        .colorScheme
                                                        .onSurface
                                                        .withValues(
                                                          alpha: 0.65,
                                                        ),
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
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
                    );

                    return AnimatedSize(
                      duration: QuoteItemWidget.expandCollapseDuration,
                      curve: QuoteItemWidget._expandCurve,
                      alignment: Alignment.topLeft,
                      clipBehavior: Clip.none,
                      child: AnimatedBuilder(
                        animation: _doubleTapController,
                        // 将不依赖动画值的子树通过 child 传入，避免动画帧间重建
                        child: contentChild,
                        builder: (context, child) {
                          final highlightOpacity = _highlightProgress.value;
                          final brightness = innerTheme.brightness;
                          final overlayStrength = brightness == Brightness.dark
                              ? 0.12
                              : 0.05;

                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            alignment: Alignment.topLeft,
                            child: highlightOpacity > 0
                                ? Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      child!,
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: DecoratedBox(
                                            key: const ValueKey(
                                              'quote_item.double_tap_overlay',
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha:
                                                    overlayStrength *
                                                    highlightOpacity,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : child!,
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
                    color: secondaryTextColor,
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
                    color: secondaryTextColor,
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
                    Icon(Icons.label_outline, size: 16, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: Builder(
                          builder: (context) {
                            // 对标签进行排序：优先显示匹配筛选条件的标签
                            final sortedTagIds = _getSortedTagIds(
                              quote.tagIds,
                              widget.selectedTagIds,
                            );

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  for (
                                    int index = 0;
                                    index < sortedTagIds.length;
                                    index++
                                  )
                                    () {
                                      final tagId = sortedTagIds[index];
                                      final tag =
                                          widget.tagMap[tagId] ??
                                          NoteCategory(
                                            id: tagId,
                                            name: l10n.unknownTag,
                                          );

                                      // 判断是否是筛选条件中的标签
                                      final isFilteredTag = widget
                                          .selectedTagIds
                                          .contains(tagId);

                                      return Container(
                                        margin: EdgeInsets.only(
                                          right: index < sortedTagIds.length - 1
                                              ? 8
                                              : 0,
                                        ),
                                        child: widget.tagBuilder != null
                                            ? widget.tagBuilder!(tag)
                                            : Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isFilteredTag
                                                      ? baseContentColor
                                                            .withValues(
                                                              alpha: 0.15,
                                                            )
                                                      : baseContentColor
                                                            .withValues(
                                                              alpha: 0.08,
                                                            ),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: Border.all(
                                                    color: isFilteredTag
                                                        ? baseContentColor
                                                              .withValues(
                                                                alpha: 0.4,
                                                              )
                                                        : baseContentColor
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                    width: isFilteredTag
                                                        ? 1.0
                                                        : 0.5,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (tag
                                                            .iconName
                                                            ?.isNotEmpty ==
                                                        true) ...[
                                                      if (IconUtils.isEmoji(
                                                        tag.iconName!,
                                                      )) ...[
                                                        Text(
                                                          IconUtils.getDisplayIcon(
                                                            tag.iconName!,
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                      ] else ...[
                                                        Icon(
                                                          IconUtils.getIconData(
                                                            tag.iconName!,
                                                          ),
                                                          size: 12,
                                                          color:
                                                              secondaryTextColor,
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                      ],
                                                    ],
                                                    Text(
                                                      tag.name,
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color:
                                                                secondaryTextColor,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                isFilteredTag
                                                                ? FontWeight
                                                                      .w600
                                                                : FontWeight
                                                                      .w500,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                      );
                                    }(),
                                ],
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
                    Tooltip(
                      message: l10n.actionFavorite,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: widget.favoriteButtonGuideKey,
                          onTap: widget.onFavorite,
                          onLongPress: quote.favoriteCount > 0
                              ? widget.onLongPressFavorite
                              : null,
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
                                      : iconColor,
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
                                          color:
                                              (quote.colorHex == null ||
                                                  quote.colorHex!.isEmpty)
                                              ? theme
                                                    .colorScheme
                                                    .surfaceContainerLowest
                                              : cardColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      child: Text(
                                        quote.favoriteCount > 99
                                            ? '99+'
                                            : '${quote.favoriteCount}',
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
                    ),
                    const SizedBox(width: 4),
                  ],

                  // 更多操作按钮
                  PopupMenuButton<String>(
                    tooltip: l10n.moreOptions,
                    key: widget.moreButtonGuideKey, // 功能引导 key
                    icon: Icon(Icons.more_vert, color: iconColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                            Text(l10n.editNoteMenu),
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
                            Text(l10n.askAIMenu),
                          ],
                        ),
                      ),
                      if (widget.onGenerateCard != null)
                        PopupMenuItem<String>(
                          value: 'generate_card',
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(l10n.generateCardShareMenu),
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
                              l10n.deleteNoteMenu,
                              style: TextStyle(color: theme.colorScheme.error),
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
