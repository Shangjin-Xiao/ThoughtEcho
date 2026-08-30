import 'dart:collection';

import 'package:flutter/material.dart';
import '../theme/theme_style.dart';
import 'package:provider/provider.dart';

import '../extensions/note_tag_localization_extension.dart';
import '../models/quote_model.dart';
import '../models/note_tag.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/common/paper_rule_background.dart';
import '../widgets/quote_content_widget.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../utils/quill_editor_extensions.dart';
import '../utils/time_utils.dart';
import '../utils/icon_utils.dart';

import '../gen_l10n/app_localizations.dart';
import 'quote_card_helpers.dart';

/// 优化：使用StatefulWidget以支持双击反馈动画，数据变化通过父组件管理
class QuoteItemWidget extends StatefulWidget {
  @visibleForTesting
  static bool disableVisualEffectsForTesting = false;

  @visibleForTesting
  static bool disableCardShadowsForTesting = false;

  @visibleForTesting
  static void resetVisualEffectTestingOverrides() {
    disableVisualEffectsForTesting = false;
    disableCardShadowsForTesting = false;
  }

  final Quote quote;
  final Map<String, NoteTag> tagMap;
  final bool isExpanded;
  final Function(bool) onToggleExpanded;
  final Function() onEdit;
  final Function() onDelete;
  final Function() onAskAI;
  final Function()? onGenerateCard;
  final Function()? onExportPdf; // PDF导出回调
  final Function()? onFavorite; // 心形按钮点击回调
  final Function()? onLongPressFavorite; // 心形按钮长按回调（清除收藏）
  final String? searchQuery;

  /// 自定义标签显示的构建器函数，接收一个标签对象，返回一个Widget
  final Widget Function(NoteTag)? tagBuilder;
  final GlobalKey? favoriteButtonGuideKey;
  final GlobalKey? foldToggleGuideKey;
  final GlobalKey? moreButtonGuideKey; // 功能引导：更多按钮 Key

  /// 当前筛选的标签ID列表，用于优先显示匹配的标签
  final List<String> selectedTagIds;
  final bool isTrashMode;
  final String? trashDeletedAtText;
  final String? trashRemainingDaysText;
  final VoidCallback? onRestore;
  final VoidCallback? onPermanentlyDelete;
  final bool trashActionsEnabled;
  final bool isSelected;
  final bool selectionMode;

  /// 单独收紧卡片上边距，供列表首条使用。
  ///
  /// 搜索框与首条笔记之间只隔着一层卡片上边距，不需要和卡片之间的间距同宽。
  /// 为 null 时使用默认的 [defaultCardMarginVertical]。收紧只能改这里——给
  /// ListView 传负 padding 会命中 RenderSliverPadding 的 assert(isNonNegative)。
  final double? topMarginOverride;

  /// 卡片默认的上下外边距。
  static const double defaultCardMarginVertical = 6.0;

  /// 列表首条笔记的上边距。
  ///
  /// 6.0（= 默认值）→ 4.0 → 2.67 收了三轮都看不出变化，因为真正占位的不是它：
  /// 记录页的 ListView 没写 padding，被 BoxScrollView 自动补上了一整条状态栏
  /// 高度（见 `note_list_items.dart` 里 ListView 的 padding 注释）。那处补齐后
  /// 这个值才真正等于搜索框与首条笔记之间的间距——搜索框容器的下边距是 0，
  /// 首条卡片上方就只剩这一层。4.0 实测贴得太紧，放回 12.0：正好等于两张卡片
  /// 之间的间距（上下各 [defaultCardMarginVertical]），首条与搜索框的呼吸感
  /// 和列表内部一致，又远小于先前那条白送的状态栏高度。
  /// 要再调只改这个数，不要动 [defaultCardMarginVertical]（那会连带改变
  /// 卡片之间的间距）。
  static const double firstItemTopMargin = 12.0;

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
    this.onExportPdf,
    this.onFavorite, // 心形按钮点击回调
    this.onLongPressFavorite, // 心形按钮长按回调（清除收藏）
    this.tagBuilder,
    this.searchQuery,
    this.favoriteButtonGuideKey,
    this.foldToggleGuideKey,
    this.moreButtonGuideKey,
    this.selectedTagIds = const [],
    this.isTrashMode = false,
    this.trashDeletedAtText,
    this.trashRemainingDaysText,
    this.onRestore,
    this.onPermanentlyDelete,
    this.trashActionsEnabled = true,
    this.isSelected = false,
    this.selectionMode = false,
    this.topMarginOverride,
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
  static final LinkedHashMap<_HeaderTextWidthCacheKey, double>
      _headerTextWidthCache = LinkedHashMap<_HeaderTextWidthCacheKey, double>();
  static const int _maxHeaderTextWidthCacheSize = 512;
  static const int _headerTextWidthPruneBatchSize = 128;
  static int _headerTextWidthCacheHits = 0;
  static int _headerTextWidthCacheMisses = 0;
  // 每张卡片首布局都要测 1~3 段头部文字（日期、位置、天气），而日期逐条不同，
  // 缓存按文本做键 ⇒ 首次必然未命中。它是首滑成本的另一个嫌疑人，一并计量。
  static int _headerTextWidthWorkMicros = 0;
  static int _headerTextWidthWorstWorkMicros = 0;

  /// 清理折叠判断缓存，常用于测试或手动刷新场景。
  static void clearExpansionCache() {
    _expansionCache.clear();
    _cacheHitCount = 0;
  }

  /// 清理列表卡片头部文本测宽缓存，常用于测试或主题/字体变化后的兜底刷新。
  static void clearHeaderTextWidthCache() {
    _headerTextWidthCache.clear();
    _headerTextWidthCacheHits = 0;
    _headerTextWidthCacheMisses = 0;
    _headerTextWidthWorkMicros = 0;
    _headerTextWidthWorstWorkMicros = 0;
  }

  /// 获取折叠缓存当前状态，便于调试观察命中率。
  static Map<String, int> getCacheStats() {
    var expandableCount = 0;
    for (final needsExpansion in _expansionCache.values) {
      if (needsExpansion) {
        expandableCount++;
      }
    }
    return {
      'cacheSize': _expansionCache.length,
      'cacheHits': _cacheHitCount,
      'expandableCount': expandableCount,
      'headerMisses': _headerTextWidthCacheMisses,
      'headerWorkMicros': _headerTextWidthWorkMicros,
      'headerWorstWorkMicros': _headerTextWidthWorstWorkMicros,
    };
  }

  @visibleForTesting
  static Map<String, int> getHeaderTextWidthCacheStats() => {
        'cacheSize': _headerTextWidthCache.length,
        'cacheHits': _headerTextWidthCacheHits,
        'cacheMisses': _headerTextWidthCacheMisses,
        'workMicros': _headerTextWidthWorkMicros,
        'worstWorkMicros': _headerTextWidthWorstWorkMicros,
      };

  /// 测试辅助方法：把卡片持有的静态可变状态一次清干净。
  ///
  /// [lastCollapsedContentWidth] 也在其中 —— 它是跨测试泄漏的现成来源，
  /// 漏掉的话后一个测试会拿着前一个测试的布局宽度去暖缓存。
  static void clearExpansionCacheForTest() {
    clearExpansionCache();
    clearHeaderTextWidthCache();
    lastCollapsedContentWidth = null;
  }

  /// 折叠卡片正文区最近一次的布局宽度。
  ///
  /// 空闲预热（见 [warmCollapsedMeasurements]）必须用**和渲染完全相同的宽度**
  /// 去暖折叠判定与排版缓存：缓存键里带着 maxWidth，差一个像素就全是未命中，
  /// 预热等于没做。按公式反推（卡片外边距 + 边框 + 两层内边距）是能算，但那个
  /// 算式散在四个 widget 里，谁改了间距都不会想起来同步它 —— 所以直接把真实
  /// 布局宽度记在这里。
  ///
  /// 列表还没建出任何一张卡片时为 null，预热此时应当让路等下一轮。
  static double? lastCollapsedContentWidth;

  /// 折叠正文的文字样式。渲染与空闲预热共用这一处，理由同上。
  static TextStyle? collapsedContentStyle(
    ThemeData theme,
    Color primaryTextColor,
  ) {
    // 行高**不在这里写死**：它由 ThemeStyleForm.bodyLineHeight 下发到
    // textTheme.bodyLarge，纸墨风格的横线间距也是从同一个值推导的。
    // 一旦在这里 copyWith 覆盖，文字就会和纸张横线错位。
    return theme.textTheme.bodyLarge?.copyWith(color: primaryTextColor);
  }

  /// 空闲预热一条笔记的折叠测量缓存（折叠判定 + 折叠排版）。
  ///
  /// 这两项是「卡片第一次布局时才做」的活：日志里的 `expandMiss+` 和
  /// `planMiss+` 每次首滑都等于新建卡片的张数。它们只跟内容和布局宽度有关，
  /// 提前在静止期算好，滑动帧里就全是命中。
  ///
  /// 预热本身不建任何 widget，也不碰 element 树；纯粹是往几张按内容指纹做键的
  /// LRU 缓存里填结果，卡片建出来时照旧走自己的那条路，只是查表命中。
  /// 卡片头部那一行要测宽的三段文字，以及它们的样式。
  ///
  /// [build] 和 [warmCollapsedMeasurements] **共用这一处**。测宽缓存是按文本做键
  /// 的，两边各写一份格式化逻辑的话，预热就变成静悄悄的空转 —— 折叠排版那次已经
  /// 吃过一模一样的亏（见 `QuoteContent._resolveCollapsedLayout` 的说明）。
  static QuoteHeaderTexts resolveHeaderTexts({
    required BuildContext context,
    required Quote quote,
    required bool showExactTime,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = QuoteCardColors.fromHex(quote.colorHex, theme.colorScheme);
    final secondaryTextColor = colors.secondaryTextColor;

    final formattedDate = TimeUtils.formatQuoteDateLocalized(
      context,
      DateTime.parse(quote.date),
      dayPeriod: quote.dayPeriod,
      showExactTime: showExactTime,
    );
    // 显示优先级：地点名（拼上行政区）> 行政区 > 坐标。
    // 用户在编辑器里特意选过"芝公园"，卡片上就不该只写"东京都·港区"。
    final displayLocation = LocationService.formatPoiForDisplay(
      quote.poiName,
      quote.location,
    );
    final locationText = displayLocation.isNotEmpty
        ? displayLocation
        : (quote.hasCoordinates
            ? LocationService.formatCoordinates(
                quote.latitude,
                quote.longitude,
              )
            : null);
    final weatherText = quote.weather != null
        ? '${WeatherService.getLocalizedWeatherDescription(l10n, quote.weather!)}'
            '${quote.temperature != null ? ' ${quote.temperature}' : ''}'
        : null;

    final headerStyle = theme.textTheme.bodySmall?.copyWith(
          color: secondaryTextColor,
        ) ??
        TextStyle(color: secondaryTextColor);

    return QuoteHeaderTexts(
      formattedDate: formattedDate,
      locationText: locationText,
      weatherText: weatherText,
      // 日期和元信息取的是同一个 token，见 build 里的说明：写死或各取各的，
      // 同一行就会出现两个字号。
      dateStyle: headerStyle,
      metaStyle: headerStyle,
    );
  }

  /// 单行文字测宽（带缓存）。
  ///
  /// [countAsHeader] 决定这次测量算不算进 `headerWorkUs` / `headerMiss` 这两个
  /// 性能计数器。它们的口径是「日期/位置/天气」那三段。标签估宽复用同一张缓存表
  /// 没问题，但**不能混进同一组计数器**，否则下一轮复测会对着一个变了口径的数字
  /// 下结论。
  static double measureSingleLineTextWidth(
    BuildContext context,
    String text,
    TextStyle style, {
    bool countAsHeader = true,
  }) {
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final cacheKey = _HeaderTextWidthCacheKey(
      text: text,
      styleHash: style.hashCode,
      textDirection: textDirection,
      textScalerHash: textScaler.hashCode,
      localeTag: locale?.toLanguageTag(),
    );
    final cached = _headerTextWidthCache.remove(cacheKey);
    if (cached != null) {
      if (countAsHeader) {
        _headerTextWidthCacheHits++;
      }
      _headerTextWidthCache[cacheKey] = cached;
      return cached;
    }

    if (countAsHeader) {
      _headerTextWidthCacheMisses++;
    }
    final stopwatch = Stopwatch()..start();
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    );

    // 量完就放，而且走 `finally`：`TextPainter` 背后是一个原生 paragraph，不 dispose
    // 要等 GC 才还，而 `layout()` 抛异常时更没人还。预热一轮会把这个方法调用三倍于
    // 卡片数的次数，攒起来不是小数。
    final double width;
    try {
      textPainter.layout();
      width = textPainter.width;
    } finally {
      textPainter.dispose();
    }
    stopwatch.stop();
    if (countAsHeader) {
      _headerTextWidthWorkMicros += stopwatch.elapsedMicroseconds;
      if (stopwatch.elapsedMicroseconds > _headerTextWidthWorstWorkMicros) {
        _headerTextWidthWorstWorkMicros = stopwatch.elapsedMicroseconds;
      }
    }
    if (_headerTextWidthCache.length >= _maxHeaderTextWidthCacheSize) {
      final keysToRemove = _headerTextWidthCache.keys
          .take(_headerTextWidthPruneBatchSize)
          .toList();
      for (final key in keysToRemove) {
        _headerTextWidthCache.remove(key);
      }
    }
    _headerTextWidthCache[cacheKey] = width;
    return width;
  }

  /// 返回这条笔记的右侧缩略图这次会画多大，不画时为 null。调用方要按这个尺寸
  /// 预解码，见 [QuoteContent.warmCollapsedLayout]。
  static double? warmCollapsedMeasurements({
    required BuildContext context,
    required Quote quote,
    required double contentMaxWidth,
    required String mediaStyle,
    required bool prioritizeBoldContent,
    required bool showExactTime,
  }) {
    if (!contentMaxWidth.isFinite || contentMaxWidth <= 0) return null;

    // 头部测宽：日期逐条不同，按文本做键必然是每张新卡片一次未命中。
    // 2026-08-25 的日志里它是 `headerMiss+48 / 13.1ms`、`+62 / 16.8ms`，
    // 是折叠测量都暖好之后仅剩的一块「第一次才做」的工作。
    final header = resolveHeaderTexts(
      context: context,
      quote: quote,
      showExactTime: showExactTime,
    );
    measureSingleLineTextWidth(
      context,
      header.formattedDate,
      header.dateStyle,
    );
    final locationText = header.locationText;
    if (locationText != null) {
      measureSingleLineTextWidth(context, locationText, header.metaStyle);
    }
    final weatherText = header.weatherText;
    if (weatherText != null) {
      measureSingleLineTextWidth(context, weatherText, header.metaStyle);
    }

    final theme = Theme.of(context);
    final colors = QuoteCardColors.fromHex(quote.colorHex, theme.colorScheme);
    final style = collapsedContentStyle(theme, colors.primaryTextColor);

    QuoteContent.exceedsCollapsedHeightForLayout(
      quote: quote,
      style: style,
      maxWidth: contentMaxWidth,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      boldWeight: QuoteContent.collapsedBoldWeight(context),
      richTextBaseStyle: QuillThemeTypography.paragraphStyle(
        context,
        base: style,
      ),
    );

    return QuoteContent.warmCollapsedLayout(
      context: context,
      quote: quote,
      style: style,
      maxWidth: contentMaxWidth,
      mediaStyle: mediaStyle,
      prioritizeBoldContent: prioritizeBoldContent,
    );
  }

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
  /// 双击反馈的动画机件**按需创建**。
  ///
  /// 它此前在 `initState` 里无条件建出来：每张卡片一个 `AnimationController`、
  /// 两条 `TweenSequence`（各 2 段 + `CurveTween`），外加正文外面常驻一层
  /// `AnimatedBuilder` + `Transform.scale`。而绝大多数卡片从挂载到销毁都不会被
  /// 双击一次 —— 首滑一次要建三十多张新卡，这些全是白付的挂载成本。
  ///
  /// 第一次双击时再建，并借那次 `setState` 把 `AnimatedBuilder` 插进树里。
  AnimationController? _doubleTapController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _highlightProgress;

  void _ensureDoubleTapController() {
    if (_doubleTapController != null) return;

    final controller = AnimationController(
      duration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _doubleTapController = controller;

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
    ]).animate(controller);

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
    ]).animate(controller);
  }

  @override
  void dispose() {
    _doubleTapController?.dispose();
    super.dispose();
  }

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

  /// 转发到 [QuoteItemWidget.measureSingleLineTextWidth]，测量与预热共用一处。
  double _measureSingleLineTextWidth(
    BuildContext context,
    String text,
    TextStyle style, {
    bool countAsHeader = true,
  }) =>
      QuoteItemWidget.measureSingleLineTextWidth(
        context,
        text,
        style,
        countAsHeader: countAsHeader,
      );

  void _handleDoubleTap(bool isExpanded, {required bool canExpand}) {
    if (!canExpand) {
      return;
    }

    final controller = _doubleTapController;
    if (controller == null) {
      // 这张卡片第一次被双击：现在才建动画机件，并借这次 setState 把
      // AnimatedBuilder 插进树里（见 [_ensureDoubleTapController]）。
      setState(_ensureDoubleTapController);
      _doubleTapController!.forward(from: 0.0);
    } else {
      controller.stop();
      controller.forward(from: 0.0);
    }

    Feedback.forTap(context);

    widget.onToggleExpanded(!isExpanded);
  }

  bool _needsExpansionForLayout(
    BuildContext context,
    Quote quote,
    TextStyle? contentStyle,
    double maxWidth,
  ) {
    return QuoteContent.exceedsCollapsedHeightForLayout(
      quote: quote,
      style: contentStyle,
      maxWidth: maxWidth,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      // 判定和渲染必须量同一件事：Android + material 下折叠预览的加粗是降档过的，
      // 富文本的基准样式也要用渲染侧那份解析好的 paragraphStyle，而不是另找一个
      // 字号/行高兜底——`bodyLarge` 和 quill 硬编码的 16/1.15 并不总是一致。
      boldWeight: QuoteContent.collapsedBoldWeight(context),
      richTextBaseStyle: QuillThemeTypography.paragraphStyle(
        context,
        base: contentStyle,
      ),
    );
  }

  Widget _buildQuoteContentSection({
    required Quote quote,
    required bool isExpanded,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required bool paperRulesDisabled,
    required AppLocalizations l10n,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final innerTheme = Theme.of(context);
          // 空闲预热要用和这里完全相同的宽度和样式去暖缓存，
          // 见 [QuoteItemWidget.lastCollapsedContentWidth]。
          QuoteItemWidget.lastCollapsedContentWidth = constraints.maxWidth;
          final contentStyle = QuoteItemWidget.collapsedContentStyle(
            innerTheme,
            primaryTextColor,
          );
          final needsExpansion = _needsExpansionForLayout(
            context,
            quote,
            contentStyle,
            constraints.maxWidth,
          );
          final String mediaStyle = context.select<SettingsService, String>(
            (s) => s.noteCardMediaStyle,
          );
          // 「可展开」和「正文被裁了」是两件事：带媒体的笔记一律可展开，正文却
          // 常常一个字都没少。提示遮罩按后者画，短笔记才不会被一条模糊带压住。
          final bool textTruncated = needsExpansion &&
              QuoteContent.collapsedTextTruncatedForLayout(
                context: context,
                quote: quote,
                style: contentStyle,
                maxWidth: constraints.maxWidth,
                mediaStyle: mediaStyle,
                prioritizeBoldContent: context.select<SettingsService, bool>(
                  (s) => s.prioritizeBoldContentInCollapse,
                ),
              );
          // 「短到不用折叠」不等于「展开」：短卡片仍然是列表卡片，应该走
          // QuoteContent 的轻量预览而不是 QuillEditor。只有用户真的双击展开了，
          // 才需要完整的富文本渲染。
          final showFullContent = isExpanded;
          // 只算一次，同时喂给正文栈和动画层：两处一旦给出不同答案，
          // AnimatedSize 与 AnimatedSwitcher 的挂载就会错配。
          final bool canToggle = needsExpansion || isExpanded;

          // 折叠提示优先**并进来源行**，不自己占一整行。
          //
          // 提示是右对齐的一小行灰字，来源行是左对齐的一行灰字，两者从来不会
          // 争同一段横向空间；分成两行等于为了几个字多撑出一整行的高度，而这条
          // 卡片本来就是「内容多到放不下」的那种，最不该再浪费纵向空间。
          //
          // 没有来源的笔记仍然走自己的提示行（`_buildQuoteContentStack` 里那条）：
          // 硬凑一行空的来源出来，反而比提示自己占一行还高。
          final String? sourceLine = _sourceLineFor(quote);
          final bool showHint = textTruncated && !isExpanded;
          final bool hintInSourceRow = showHint && sourceLine != null;

          final contentChild = _buildQuoteContentStack(
            canToggle: canToggle,
            quote: quote,
            showFullContent: showFullContent,
            needsExpansion: needsExpansion,
            textTruncated: textTruncated && !hintInSourceRow,
            isExpanded: isExpanded,
            contentStyle: contentStyle,
            innerTheme: innerTheme,
            l10n: l10n,
          );

          final animatedContent = _buildAnimatedQuoteContent(
            innerTheme: innerTheme,
            child: contentChild,
            canToggle: canToggle,
          );

          return GestureDetector(
            key: widget.foldToggleGuideKey ??
                const ValueKey('quote_item.double_tap_region'),
            behavior: HitTestBehavior.translucent,
            onDoubleTap: needsExpansion
                ? () => _handleDoubleTap(
                      isExpanded,
                      canExpand: needsExpansion,
                    )
                : null,
            // 纸张横线**只画在正文这一块**，不铺满整张卡片。
            //
            // 铺满整卡时横线会穿过日期天气行、图片、标签胶囊和按钮行，而且相位对不上：
            // 线从卡片顶边开始等距排，正文却从头部行下面才开始，于是每一行字都骑在
            // 线的中腰上——看着就是「卡片背了一张格子图」。间距等于行高只解决了
            // 行与行之间不漂移，解决不了整体相位。
            //
            // 画在正文块上，横线第一条正好落在第一行的行底（painter 从
            // topInset + spacing 起画，而正文首行的行盒顶就是 y=0），后面每一条都
            // 落在行与行之间。圆角传 zero：这里已经在卡片的圆角裁切之内了。
            // 正文里的图片和展开蒙层都画在 painter 之上，会自然盖住横线。
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 纸张横线只裹正文，不裹来源行：来源行的行高和正文不是一套，
                // 横线接着往下画会和它错位。
                if (paperRulesDisabled)
                  animatedContent
                else
                  PaperRuleBackground(
                    borderRadius: BorderRadius.zero,
                    child: animatedContent,
                  ),
                if (sourceLine != null || hintInSourceRow)
                  _buildSourceRow(
                    sourceLine: sourceLine,
                    showHint: hintInSourceRow,
                    rowMaxWidth: constraints.maxWidth,
                    innerTheme: innerTheme,
                    secondaryTextColor: secondaryTextColor,
                    l10n: l10n,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 来源行与右端折叠提示之间的间距。
  static const double _sourceHintGap = 8.0;

  /// 来源与出处那一行的文本；没有来源时为 null。
  String? _sourceLineFor(Quote quote) {
    final author = quote.sourceAuthor ?? '';
    final work = quote.sourceWork ?? '';
    if (author.isNotEmpty || work.isNotEmpty) {
      return _formatSource(author, work);
    }
    final source = quote.source;
    if (source != null && source.isNotEmpty) return source;
    return null;
  }

  /// 来源行，右端可以搭一条折叠提示。
  ///
  /// 上边距 12 = 原来「正文区下内边距 8 + 来源行上内边距 4」，来源行搬进内容区
  /// 之后这两段合成一处，卡片的间距和以前逐像素相同。
  Widget _buildSourceRow({
    required String? sourceLine,
    required bool showHint,
    required double rowMaxWidth,
    required ThemeData innerTheme,
    required Color secondaryTextColor,
    required AppLocalizations l10n,
  }) {
    // 提示是 Row 里的非 flex 子项，会一直保留自己的固有宽度：窄卡片（分屏、
    // Windows 小窗）碰上大字号缩放时，它加上 8 的间距就能超过整行，`Expanded`
    // 分到负宽度，RenderFlex 当场溢出。所以给它封一个上界让它自己折行。
    //
    // 上界取半行：正常字号下提示只占六七十像素，离这条线远得很，版式一点不变；
    // 只有极端缩放才会碰到，那时两边各折各的，谁也挤不掉谁。
    final double halfRow = (rowMaxWidth - _sourceHintGap) / 2;
    final double hintMaxWidth =
        !rowMaxWidth.isFinite ? double.infinity : (halfRow > 0 ? halfRow : 0.0);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        // 来源长到要折行时，提示跟着落在最后一行，不吊在半空。
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Expanded 而不是 Flexible：来源短的时候也要把剩下的宽度吃掉，
          // 否则提示会紧贴在来源右边，而不是卡片右缘。
          Expanded(
            child: sourceLine == null
                ? const SizedBox.shrink()
                : Text(
                    sourceLine,
                    style: innerTheme.textTheme.bodyMedium?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
          ),
          if (showHint) ...[
            const SizedBox(width: _sourceHintGap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: hintMaxWidth),
              child: Text(
                l10n.doubleTapToViewFull,
                textAlign: TextAlign.end,
                style: innerTheme.textTheme.labelSmall?.copyWith(
                  color: innerTheme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuoteContentStack({
    required Quote quote,
    required bool showFullContent,
    required bool needsExpansion,
    required bool textTruncated,
    required bool isExpanded,
    required bool canToggle,
    required TextStyle? contentStyle,
    required ThemeData innerTheme,
    required AppLocalizations l10n,
  }) {
    final Widget quoteContent = QuoteContent(
      quote: quote,
      style: contentStyle,
      showFullContent: showFullContent,
      needsExpansionOverride: needsExpansion,
      collapseRichTextSemantics: true,
    );

    // canToggle 由调用方给：不可展开的卡片正文永远不会在折叠态和展开态之间
    // 切换，`AnimatedSwitcher` 那套动画机件（一个 `AnimationController` 加一层
    // `FadeTransition`）对它一次都用不上，却要在每次首建时挂满整棵子树。
    final Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        // 撑满可用宽度：纯文本正文在宽松约束下只有最长行那么宽（手动换行的
        // 短行笔记尤其明显），否则 Stack 会收缩到文字宽度，
        // 下方的提示行会跟着变窄、贴到正文右边而不是卡片右边。
        const SizedBox(width: double.infinity, height: 0),
        if (!canToggle)
          quoteContent
        else
          AnimatedSwitcher(
            duration: QuoteItemWidget._fadeDuration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              clipBehavior: Clip.none,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey<bool>(showFullContent),
              child: quoteContent,
            ),
          ),
      ],
    );

    // 提示行只给**正文真的被截断**的卡片，而且画在正文下面，不压在正文上。
    //
    // 这两点都是有来由的：
    //
    // - 「有媒体就一律可展开」（见 `QuoteContent._hasCollapsibleMedia`）会让短
    //   笔记、纯图笔记也拿到展开入口，可它们的正文一个字都没少。提示按「可展开」
    //   画，遮的就是完好的内容，说的「还有全文」也不存在。
    // - 正文现在按整行截断（见 `CollapsedRichTextMetrics.plan`），盒底不再留半行
    //   残字，也就不需要一条模糊带去糊住它。原来那条 `BackdropFilter` 每张折叠卡
    //   一个，去掉之后连它的合成开销一起省了。
    if (isExpanded || !textTruncated) return content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              l10n.doubleTapToViewFull,
              style: innerTheme.textTheme.labelSmall?.copyWith(
                color: innerTheme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedQuoteContent({
    required ThemeData innerTheme,
    required Widget child,
    required bool canToggle,
  }) {
    final controller = _doubleTapController;
    final Widget content = controller == null
        ? child
        : _buildDoubleTapFeedback(
            innerTheme: innerTheme,
            controller: controller,
            scaleAnimation: _scaleAnimation!,
            highlightProgress: _highlightProgress!,
            child: child,
          );

    if (!canToggle) {
      // 不可展开的卡片正文高度是静态的，没有任何东西需要 AnimatedSize 去补间；
      // 它自带一个 Ticker 和一个额外的 RenderObject，白挂在每张卡片上。
      return content;
    }

    return AnimatedSize(
      duration: QuoteItemWidget.expandCollapseDuration,
      curve: QuoteItemWidget._expandCurve,
      alignment: Alignment.topLeft,
      clipBehavior: Clip.none,
      child: content,
    );
  }

  /// 三个动画对象由 [_ensureDoubleTapController] 一次性建出，调用方传进来，
  /// 这里就不必再对字段做强制解包。
  Widget _buildDoubleTapFeedback({
    required ThemeData innerTheme,
    required AnimationController controller,
    required Animation<double> scaleAnimation,
    required Animation<double> highlightProgress,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final highlightOpacity = highlightProgress.value;
        final brightness = innerTheme.brightness;
        final overlayStrength = brightness == Brightness.dark ? 0.12 : 0.05;

        return Transform.scale(
          scale: scaleAnimation.value,
          alignment: Alignment.topLeft,
          child: highlightOpacity > 0
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    child!,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: DecoratedBox(
                            key: const ValueKey(
                              'quote_item.double_tap_overlay',
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: overlayStrength * highlightOpacity,
                              ),
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
    );
  }

  /// 标签条容不下时才退回滚动视图的余量。
  static const double _tagStripFitMargin = 4.0;

  /// 标签胶囊的文字样式。估宽和渲染**必须共用这一处**：两边样式差一点，
  /// 估出来的宽度就不是真实宽度，放不下也会被判成放得下。
  ///
  /// 基准是 `labelSmall`（11sp 黑体）而不是 `bodySmall`。胶囊是界面标签，
  /// 按 `AppTheme._applyStyleTypography` 定的全局规则，11–14sp 的功能性文字一律
  /// 留在黑体上——原来拿 `bodySmall` 再写死 11sp，等于在衬线风格下把中文宋体
  /// 缩到 11sp 去渲染，正是那条规则要避开的字号区间，标签糊成一团。
  /// 顺带也不用再写死字号：`labelSmall` 本来就是 11。
  TextStyle? _tagChipTextStyle(
    ThemeData theme,
    Color secondaryTextColor, {
    required bool isFilteredTag,
  }) {
    return theme.textTheme.labelSmall?.copyWith(
      color: secondaryTextColor,
      fontWeight: isFilteredTag ? FontWeight.w600 : FontWeight.w500,
    );
  }

  /// 标签条。
  ///
  /// **放得下就不挂 `SingleChildScrollView`。** 一层 `Scrollable` 要带上
  /// `ScrollPosition`、两个手势识别器、`Viewport` 和一组语义节点，实测三个标签的
  /// 卡片里它一个人占了三十多个 element；而绝大多数笔记的标签一行就放得下，
  /// 那层滚动视图从挂载到销毁都不会被滑动一次。
  ///
  /// 放不下才退回滚动视图。判断按估宽做，且**只在明确放得下时才省**：估宽偏大
  /// 只是多挂一层用不上的滚动视图，偏小才会让最后一个标签被静默裁掉。自定义
  /// [QuoteItemWidget.tagBuilder] 的宽度无从估起，一律走滚动视图。
  Widget _buildTagStrip({
    required ThemeData theme,
    required AppLocalizations l10n,
    required Color baseContentColor,
    required Color secondaryTextColor,
  }) {
    // 对标签进行排序：优先显示匹配筛选条件的标签
    final sortedTagIds = _getSortedTagIds(
      widget.quote.tagIds,
      widget.selectedTagIds,
    );

    var estimatedWidth = 0.0;
    final canEstimate = widget.tagBuilder == null;
    final chips = <Widget>[];

    for (var index = 0; index < sortedTagIds.length; index++) {
      final tagId = sortedTagIds[index];
      final tag = widget.tagMap[tagId] ??
          NoteTag(
            id: tagId,
            name: l10n.unknownTag,
          );
      // 判断是否是筛选条件中的标签
      final isFilteredTag = widget.selectedTagIds.contains(tagId);
      final textStyle = _tagChipTextStyle(
        theme,
        secondaryTextColor,
        isFilteredTag: isFilteredTag,
      );
      final iconName = tag.iconName;
      final hasIcon = iconName != null && iconName.isNotEmpty;
      final isEmojiIcon = hasIcon && IconUtils.isEmoji(iconName);

      if (canEstimate) {
        estimatedWidth += 20; // 左右内边距
        estimatedWidth += isFilteredTag ? 2.0 : 1.0; // 左右边框
        if (hasIcon) {
          estimatedWidth += 3; // 图标与文字之间的间距
          estimatedWidth += isEmojiIcon
              ? _measureSingleLineTextWidth(
                  context,
                  IconUtils.getDisplayIcon(iconName),
                  const TextStyle(fontSize: 12),
                  countAsHeader: false,
                )
              : 12;
        }
        estimatedWidth += _measureSingleLineTextWidth(
          context,
          tag.localizedName(l10n),
          textStyle ?? const TextStyle(),
          countAsHeader: false,
        );
        if (index < sortedTagIds.length - 1) {
          estimatedWidth += 8; // 胶囊之间的间距
        }
      }

      chips.add(
        Padding(
          padding: EdgeInsets.only(
            right: index < sortedTagIds.length - 1 ? 8 : 0,
          ),
          child: widget.tagBuilder != null
              ? widget.tagBuilder!(tag)
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: baseContentColor.withValues(
                      alpha: isFilteredTag ? 0.15 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: baseContentColor.withValues(
                        alpha: isFilteredTag ? 0.4 : 0.15,
                      ),
                      width: isFilteredTag ? 1.0 : 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasIcon) ...[
                        ExcludeSemantics(
                          child: isEmojiIcon
                              ? Text(
                                  IconUtils.getDisplayIcon(iconName),
                                  style: const TextStyle(fontSize: 12),
                                )
                              : Icon(
                                  IconUtils.getIconData(iconName),
                                  size: 12,
                                  color: secondaryTextColor,
                                ),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        tag.localizedName(l10n),
                        style: textStyle,
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final row = Row(mainAxisSize: MainAxisSize.min, children: chips);
        final bool fits = canEstimate &&
            constraints.maxWidth.isFinite &&
            estimatedWidth + _tagStripFitMargin <= constraints.maxWidth;
        if (!fits) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: row,
          );
        }
        // 估宽万一偏小也只是裁掉一截，不会撞 RenderFlex 溢出。
        return ClipRect(
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            maxWidth: double.infinity,
            child: row,
          ),
        );
      },
    );
  }

  /// 心形按钮的边长（图标 20 + 上下各 8 的内边距），保持与改造前逐像素一致。
  static const double _favoriteButtonSize = 36.0;

  /// 更多按钮的边长。原先由 `IconButton` 的 48dp 触控目标撑出来，
  /// 换成轻量按钮后必须显式给回来，否则这一行会矮 12dp、整张卡片跟着变矮。
  static const double _moreButtonSize = 48.0;

  /// 只有带指针的平台才挂 [Tooltip]。
  ///
  /// 触摸端 Tooltip 只能靠长按弹出，而这两个按钮的长按要么已经被「清除收藏」
  /// 占着、要么本来就不该有反应；无障碍名称由 [Semantics] 单独给，不依赖它。
  /// 一层 Tooltip 是一个 `AnimationController` 加约十个 element，乘以首滑要建的
  /// 三十多张新卡片就是实打实的挂载成本。
  static bool _showsHoverTooltips(ThemeData theme) {
    switch (theme.platform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Widget _buildFavoriteButton({
    required ThemeData theme,
    required AppLocalizations l10n,
    required Color iconColor,
    required Color cardColor,
  }) {
    final quote = widget.quote;
    final bool isFavorite = quote.favoriteCount > 0;
    final String label =
        isFavorite ? l10n.actionUnfavorite : l10n.actionFavorite;
    final semanticColors = AppSemanticColors.of(context);

    return _CardActionButton(
      key: widget.favoriteButtonGuideKey,
      size: _favoriteButtonSize,
      borderRadius: BorderRadius.circular(20),
      semanticsLabel: label,
      hoverTooltip: _showsHoverTooltips(theme) ? label : null,
      onTap: (_) => widget.onFavorite?.call(),
      onLongPress: isFavorite ? widget.onLongPressFavorite : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: isFavorite ? semanticColors.favorite : iconColor,
          ),
          if (isFavorite)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  color: semanticColors.favorite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (quote.colorHex == null || quote.colorHex!.isEmpty)
                        ? theme.colorScheme.surfaceContainerLowest
                        : cardColor,
                    width: 1.0,
                  ),
                ),
                constraints: const BoxConstraints(
                  minWidth: 14,
                  minHeight: 14,
                ),
                child: Text(
                  quote.favoriteCount > 99 ? '99+' : '${quote.favoriteCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: semanticColors.onFavorite,
                    fontSize: 9.0,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 弹出「更多」菜单。
  ///
  /// 菜单项在**点开时**才构造：此前挂在 `PopupMenuButton` 上的 `itemBuilder`
  /// 也是懒的，但按钮本体（`IconButton` 的整套 `ButtonStyle` 解析 + 48dp 触控
  /// 内衬 + `Tooltip`）是每张卡片必付的，实测一张最小卡片 146 个 element 里
  /// 它一个人占 59 —— 而正文只有 3 个。
  Future<void> _showMoreMenu(
      BuildContext context, AppLocalizations l10n) async {
    final theme = Theme.of(context);
    final RenderObject? buttonObject = context.findRenderObject();
    final RenderBox? overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (buttonObject is! RenderBox || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        buttonObject.localToGlobal(Offset.zero, ancestor: overlay),
        buttonObject.localToGlobal(
          buttonObject.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    // 导出格式在点开时才读：菜单在这一刻才需要它，卡片本身不必为它订阅设置变更。
    final String exportFormat = context.read<SettingsService>().exportFormat;

    final String? selected = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      items: <PopupMenuEntry<String>>[
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
                Icons.lightbulb_outline,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(l10n.askAIMenu),
            ],
          ),
        ),
        if (exportFormat == 'pdf' && widget.onExportPdf != null)
          PopupMenuItem<String>(
            value: 'export_pdf',
            child: Row(
              children: [
                Icon(
                  Icons.picture_as_pdf,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l10n.exportToPdf),
              ],
            ),
          )
        else if (widget.onGenerateCard != null)
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
              Icon(Icons.delete, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text(
                l10n.deleteNoteMenu,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'ask':
        widget.onAskAI();
      case 'edit':
        widget.onEdit();
      case 'generate_card':
        widget.onGenerateCard?.call();
      case 'export_pdf':
        widget.onExportPdf?.call();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final quote = widget.quote;
    final isExpanded = widget.isExpanded;

    final colors = QuoteCardColors.fromHex(quote.colorHex, theme.colorScheme);
    final Color cardColor = colors.cardColor;
    final Color baseContentColor = colors.baseContentColor;
    final Color primaryTextColor = colors.primaryTextColor;
    final Color secondaryTextColor = colors.secondaryTextColor;
    final Color iconColor = colors.iconColor;

    // Determine the text color based on the card color

    // 格式化日期和时间段（支持国际化和精确时间显示）
    final DateTime quoteDate = DateTime.parse(quote.date);
    final showExactTime = context.select<SettingsService, bool>(
      (s) => s.showExactTime,
    );
    final showNoteEditTime = context.select<SettingsService, bool>(
      (s) => s.showNoteEditTime,
    );
    final disableCardShadows = context.select<SettingsService, bool>(
      (s) => s.noteListDisableCardShadows,
    );
    final headerTexts = QuoteItemWidget.resolveHeaderTexts(
      context: context,
      quote: quote,
      showExactTime: showExactTime,
    );
    final String formattedDate = headerTexts.formattedDate;
    final DateTime? lastModified = quote.lastModified != null
        ? DateTime.tryParse(quote.lastModified!)
        : null;
    final bool shouldShowEditedAt = showNoteEditTime &&
        lastModified != null &&
        !lastModified.isAtSameMomentAs(quoteDate);
    final String? formattedEditedAt = shouldShowEditedAt
        ? l10n.editedAtLabel(
            TimeUtils.formatQuoteDateLocalized(
              context,
              lastModified,
              showExactTime: showExactTime,
            ),
          )
        : null;
    final String? locationText = headerTexts.locationText;
    final String? weatherText = headerTexts.weatherText;
    // 日期和元信息取的是同一个 token（见 resolveHeaderTexts）：写死 12 就等于把
    // 这一项从排版体系里摘出去，风格一旦动了 bodySmall（曾经加过 6% 字号补偿，
    // 现在改成整级不动），日期跟着走而它不跟，同一行两个字号，看着就是没对齐。
    final TextStyle headerDateStyle = headerTexts.dateStyle;
    final TextStyle headerMetaStyle = headerTexts.metaStyle;
    final visualEffectsDisabled =
        QuoteItemWidget.disableVisualEffectsForTesting;
    final cardShadowsDisabled = visualEffectsDisabled ||
        QuoteItemWidget.disableCardShadowsForTesting ||
        disableCardShadows;
    final cardMargin = EdgeInsets.only(
      left: 12,
      right: 12,
      top:
          widget.topMarginOverride ?? QuoteItemWidget.defaultCardMarginVertical,
      bottom: QuoteItemWidget.defaultCardMarginVertical,
    );
    final shapeTokens = AppShapeTokens.of(context);
    final cardRadius = BorderRadius.circular(shapeTokens.cardRadius);
    final cardDecoration = BoxDecoration(
      borderRadius: cardRadius,
      border: widget.selectionMode && widget.isSelected
          ? Border.all(color: theme.colorScheme.primary, width: 2)
          : Border.all(color: Colors.transparent, width: 2),
      boxShadow: cardShadowsDisabled
          ? const <BoxShadow>[]
          : widget.isSelected && widget.selectionMode
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 2,
                  )
                ]
              : (isExpanded
                  ? shapeTokens.raisedShadow
                  : shapeTokens.restShadow),
      gradient: quote.colorHex != null && quote.colorHex!.isNotEmpty
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isSelected && widget.selectionMode
                  ? [
                      cardColor.withValues(alpha: 0.8),
                      theme.colorScheme.primary.withValues(alpha: 0.1)
                    ]
                  : [cardColor, cardColor.withValues(alpha: 0.95)],
            )
          : null,
      color: quote.colorHex == null || quote.colorHex!.isEmpty
          ? (widget.isSelected && widget.selectionMode
              ? theme.colorScheme.primary.withValues(alpha: 0.05)
              : cardColor)
          : null,
    );
    final cardChild = Padding(
      padding: const EdgeInsets.all(12), // 减少内边距从16到12
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Trash Metadata Row ---
          if (widget.isTrashMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.auto_delete_outlined,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.trashRemainingDaysText ?? '',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                  const Spacer(),
                  Text(
                    widget.trashDeletedAtText ?? '',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),

          // 头部日期显示
          Padding(
            padding: EdgeInsets.fromLTRB(
              4,
              0,
              4,
              formattedEditedAt != null ? 2 : 8,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool hasLocationText = locationText != null;
                final bool hasWeatherText = weatherText != null;
                final bool hasMetaText = hasLocationText || hasWeatherText;
                final double dateWidth = _measureSingleLineTextWidth(
                  context,
                  formattedDate,
                  headerDateStyle,
                );
                double metaWidth = 0;

                if (hasLocationText) {
                  metaWidth += 14 + 2;
                  metaWidth += _measureSingleLineTextWidth(
                    context,
                    locationText,
                    headerMetaStyle,
                  );
                }
                if (hasLocationText && hasWeatherText) {
                  metaWidth += 8;
                }
                if (hasWeatherText) {
                  metaWidth += 14 + 2;
                  metaWidth += _measureSingleLineTextWidth(
                    context,
                    weatherText,
                    headerMetaStyle,
                  );
                }

                final double compactWidth =
                    dateWidth + (hasMetaText ? 12 + metaWidth : 0);

                Widget buildDate() => Text(
                      formattedDate,
                      maxLines: 1,
                      softWrap: false,
                      style: headerDateStyle,
                    );

                Widget buildMeta() => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasLocationText) ...[
                          ExcludeSemantics(
                            child: Icon(
                              Icons.location_on,
                              size: 14,
                              color: iconColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            locationText,
                            maxLines: 1,
                            softWrap: false,
                            style: headerMetaStyle,
                          ),
                        ],
                        if (hasLocationText && hasWeatherText)
                          const SizedBox(width: 8),
                        if (hasWeatherText) ...[
                          ExcludeSemantics(
                            child: Icon(
                              _getWeatherIcon(quote.weather!),
                              size: 14,
                              color: iconColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            weatherText,
                            maxLines: 1,
                            softWrap: false,
                            style: headerMetaStyle,
                          ),
                        ],
                      ],
                    );

                if (compactWidth <= constraints.maxWidth) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(child: buildDate()),
                      if (hasMetaText) ...[
                        const SizedBox(width: 12),
                        buildMeta(),
                      ],
                    ],
                  );
                }

                return Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildDate(),
                        if (hasMetaText) ...[
                          const SizedBox(width: 12),
                          buildMeta(),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (formattedEditedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Text(
                formattedEditedAt,
                // labelSmall（11sp 黑体）而不是 bodySmall 再压到 10：10sp 的中文
                // 宋体只剩一团灰。它是时间戳，不承担任何风格识别。
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondaryTextColor.withValues(alpha: 0.82),
                ),
              ),
            ),

          _buildQuoteContentSection(
            quote: quote,
            isExpanded: isExpanded,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            paperRulesDisabled: visualEffectsDisabled,
            l10n: l10n,
          ),

          // 来源行画在 `_buildQuoteContentSection` 里面，不在这里：折叠提示要和它
          // 并成一行（见那边的说明），而「正文是否真的被截断」只有内容区的
          // `LayoutBuilder` 里才量得出来。

          // 底部工具栏 - 标签、心形和更多按钮在同一行
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                if (quote.tagIds.isNotEmpty) ...[
                  ExcludeSemantics(
                    child: Icon(
                      Icons.label_outline,
                      size: 16,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: _buildTagStrip(
                        theme: theme,
                        l10n: l10n,
                        baseContentColor: baseContentColor,
                        secondaryTextColor: secondaryTextColor,
                      ),
                    ),
                  ),
                ] else ...[
                  const Expanded(child: SizedBox.shrink()),
                ],

                if (widget.isTrashMode) ...[
                  TextButton(
                    onPressed: widget.trashActionsEnabled
                        ? widget.onPermanentlyDelete
                        : null,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text(l10n.permanentlyDelete),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed:
                        widget.trashActionsEnabled ? widget.onRestore : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text(l10n.restore),
                  ),
                ],

                // 心形按钮与更多按钮共用一层 Material：墨水层是按 Material 挂的，
                // 一张卡片两个按钮不需要两层。
                if (!widget.isTrashMode)
                  Material(
                    color: Colors.transparent,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onFavorite != null) ...[
                          _buildFavoriteButton(
                            theme: theme,
                            l10n: l10n,
                            iconColor: iconColor,
                            cardColor: cardColor,
                          ),
                          const SizedBox(width: 4),
                        ],
                        _CardActionButton(
                          key: widget.moreButtonGuideKey, // 功能引导 key
                          size: _moreButtonSize,
                          shape: BoxShape.circle,
                          semanticsLabel: l10n.moreOptions,
                          hoverTooltip: _showsHoverTooltips(theme)
                              ? l10n.moreOptions
                              : null,
                          // 菜单按**按钮**的位置弹，不是按整张卡片，见 [_CardActionButton.onTap]。
                          onTap: (buttonContext) =>
                              _showMoreMenu(buttonContext, l10n),
                          child: Icon(Icons.more_vert, color: iconColor),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    // 纸张横线纹理**不在这一层**：它只画在正文块上（见 _buildQuoteContentSection），
    // 铺满整张卡会穿过头部元信息、图片和按钮行。这层保持纯壳，
    // 折叠态卡片的 RepaintBoundary 缓存收益也就不受影响。
    final shouldAnimateCardShell = widget.selectionMode || isExpanded;
    final Widget card;
    if (shouldAnimateCardShell) {
      card = AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: cardMargin,
        decoration: cardDecoration,
        child: cardChild,
      );
    } else {
      // 性能优化（第一步）：折叠态静态卡片用 RepaintBoundary 隔离绘制。
      // 卡片阴影（BoxShadow 高斯模糊）与渐变属于静态像素，套重绘边界后
      // 其栅格结果可被缓存，滚动时仅做位移合成，避免每帧重新栅格化阴影。
      // 视觉像素不变；展开/选择态走 AnimatedContainer 分支，decoration 每帧变化，
      // 缓存收益小，故不在该分支额外包裹。
      card = RepaintBoundary(
        child: Container(
          margin: cardMargin,
          decoration: cardDecoration,
          child: cardChild,
        ),
      );
    }

    return card;
  }
}

/// 卡片底部动作按钮的轻量实现。
///
/// 列表卡片的挂载预算几乎全被这一行吃掉过：实测一张最小卡片（无标签、无媒体、
/// 短正文）146 个 element，其中 `PopupMenuButton` 一个人占 59、心形按钮外面那层
/// `Tooltip` 占 10，而**正文只有 3 个**。首滑一次要建三十多张这样的新卡片，
/// 成本全落在滚动帧里。
///
/// `IconButton` 那一整套（`ButtonStyle` 逐属性解析、`_InputPadding` 触控内衬、
/// 焦点与快捷键节点、`Tooltip`）对这两个位置一样都用不上：它们不吃按钮样式令牌、
/// 不参与键盘遍历、触摸端也没有悬浮。这里只保留真正需要的三件事 ——
/// 固定尺寸、水波纹、无障碍名称。
///
/// 尺寸由调用方显式给（心形 36、更多 48），和改造前逐像素一致；改这两个数
/// 会连带改变整行的高度，也就是每张卡片的高度。
class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    super.key,
    required this.size,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.hoverTooltip,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  final double size;
  final String semanticsLabel;

  /// 回调拿到的是**按钮自己的** context。
  ///
  /// 「更多」菜单要按按钮的位置弹出，而 `showMenu` 的定位靠
  /// `context.findRenderObject()`。用卡片 build 方法里的那个 context 的话，
  /// 找到的是整张卡片的 RenderBox，菜单会按整张卡片定位 —— 改造前的
  /// `PopupMenuButton` 用的是它自己的 element，这里必须还原同一个语义。
  final void Function(BuildContext buttonContext)? onTap;
  final VoidCallback? onLongPress;

  /// 仅在有指针悬浮的平台传值，见 [_QuoteItemWidgetState._showsHoverTooltips]。
  final String? hoverTooltip;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tapHandler = onTap;
    Widget button = InkResponse(
      onTap: tapHandler == null ? null : () => tapHandler(context),
      onLongPress: onLongPress,
      containedInkWell: shape == BoxShape.rectangle,
      highlightShape: shape,
      borderRadius: borderRadius,
      radius: size / 2,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );

    button = Semantics(
      button: true,
      label: semanticsLabel,
      child: button,
    );

    final tooltip = hoverTooltip;
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}

@immutable

/// 卡片头部那一行要测宽的三段文字与样式，见 [QuoteItemWidget.resolveHeaderTexts]。
@immutable
class QuoteHeaderTexts {
  const QuoteHeaderTexts({
    required this.formattedDate,
    required this.locationText,
    required this.weatherText,
    required this.dateStyle,
    required this.metaStyle,
  });

  final String formattedDate;
  final String? locationText;
  final String? weatherText;
  final TextStyle dateStyle;
  final TextStyle metaStyle;
}

class _HeaderTextWidthCacheKey {
  const _HeaderTextWidthCacheKey({
    required this.text,
    required this.styleHash,
    required this.textDirection,
    required this.textScalerHash,
    required this.localeTag,
  });

  final String text;
  final int styleHash;
  final TextDirection textDirection;
  final int textScalerHash;
  final String? localeTag;

  @override
  bool operator ==(Object other) {
    return other is _HeaderTextWidthCacheKey &&
        other.text == text &&
        other.styleHash == styleHash &&
        other.textDirection == textDirection &&
        other.textScalerHash == textScalerHash &&
        other.localeTag == localeTag;
  }

  @override
  int get hashCode => Object.hash(
        text,
        styleHash,
        textDirection,
        textScalerHash,
        localeTag,
      );
}
