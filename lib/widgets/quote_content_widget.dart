import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../models/app_settings.dart';
import '../models/quote_model.dart';
import '../theme/theme_style.dart';
import '../utils/delta_media_extractor.dart';
import '../utils/delta_rich_text_parser.dart';
import '../utils/quill_editor_extensions.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import 'motion_photo_preview_page.dart';
import 'note_list/collapsed_media_banner.dart';
import 'note_list/collapsed_media_thumbnail.dart';
import 'note_list/collapsed_rich_text.dart';

/// 统一显示Quote内容的组件，支持富文本和普通文本
class QuoteContent extends StatelessWidget {
  final Quote quote;
  final TextStyle? style;
  final int? maxLines;
  final bool showFullContent;
  final bool collapseRichTextSemantics;
  final bool? needsExpansionOverride;

  const QuoteContent({
    super.key,
    required this.quote,
    this.style,
    this.maxLines,
    this.showFullContent = false,
    this.collapseRichTextSemantics = false,
    this.needsExpansionOverride,
  });

  /// [paragraphStyle] 由 [QuillThemeTypography.paragraphStyle] 算出：quill 的段落
  /// 基准样式**不继承** `textTheme`，字号和行高被硬写成 16 / 1.15，必须按令牌纠正，
  /// 好让富文本笔记、纯文本笔记和纸张横线间距全部由同一组令牌决定。
  ///
  /// **必须给全 color/fontSize**：`TextLine` 用的是 `RichText`，它不继承
  /// `DefaultTextStyle`，paragraph 整体替换后缺 color 会在暗色模式下渲染成黑字。
  /// 所以那个方法是「拿到等效 base 再 copyWith」，不是凭空构造。
  ///
  /// [weightCompensation] 来自 `AppTypographyTokens`，为 0 时下面那套加粗降档
  /// **必须整段跳过**：降档是给黑体做的，而系统中文衬线体常常只有 Regular / Bold
  /// 两档，把 w700 降到 w500 会匹配回 Regular——用户标的粗体直接消失。
  static quill.DefaultStyles _buildCustomStyles(
    TextStyle paragraphStyle,
    double weightCompensation,
  ) {
    // Android 之外、以及不做黑体减重的风格，只需要段落这一项。
    if (kIsWeb || !Platform.isAndroid || weightCompensation <= 0) {
      return QuillThemeTypography.paragraphOnly(paragraphStyle);
    }
    final paragraph = quill.DefaultTextBlockStyle(
      paragraphStyle,
      const quill.HorizontalSpacing(0, 0),
      quill.VerticalSpacing.zero,
      quill.VerticalSpacing.zero,
      null,
    );
    // Flutter 3.41+ Android (Impeller + 精准 wght 轴) 下 FontWeight.bold (w700)
    // 渲染明显偏粗。在 Android 上注入 customStyles 将 bold 降为 w600，
    // 标题按比例降档，使视觉接近升级前效果。
    return quill.DefaultStyles(
      paragraph: paragraph,
      bold: const TextStyle(fontWeight: FontWeight.w500),
      h1: quill.DefaultTextBlockStyle(
        TextStyle(
          fontSize: QuillThemeTypography.headerFontSize1,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          height: 1.083,
          decoration: TextDecoration.none,
        ),
        const quill.HorizontalSpacing(0, 0),
        const quill.VerticalSpacing(16, 0),
        quill.VerticalSpacing.zero,
        null,
      ),
      h2: quill.DefaultTextBlockStyle(
        TextStyle(
          fontSize: QuillThemeTypography.headerFontSize2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
          height: 1.067,
          decoration: TextDecoration.none,
        ),
        const quill.HorizontalSpacing(0, 0),
        const quill.VerticalSpacing(8, 0),
        quill.VerticalSpacing.zero,
        null,
      ),
      h3: quill.DefaultTextBlockStyle(
        TextStyle(
          fontSize: QuillThemeTypography.headerFontSize3,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
          height: 1.083,
          decoration: TextDecoration.none,
        ),
        const quill.HorizontalSpacing(0, 0),
        const quill.VerticalSpacing(8, 0),
        quill.VerticalSpacing.zero,
        null,
      ),
    );
  }

  // 性能优化：静态缓存 config，避免每次 build 创建。
  // embedBuilders 是这里唯一贵的东西，它不随主题变化，所以留在静态基底上。
  static final quill.QuillEditorConfig _staticEditorConfig =
      quill.QuillEditorConfig(
    enableInteractiveSelection: false,
    enableSelectionToolbar: false,
    showCursor: false,
    embedBuilders: QuillEditorExtensions.getEmbedBuilders(
      optimizedImages: true,
    ),
    padding: EdgeInsets.zero,
    expands: false,
    scrollable: false,
  );

  // 段落样式随主题（字号、行高）和笔记颜色变化，没法再全静态。
  // 用一条 memo 而不是 Map：同屏卡片的正文样式几乎总是同一个，命中率极高，
  // 又不会像按颜色做键的 Map 那样无界增长。
  // 字重补偿也要进 memo 的比较，否则切换主题风格后会拿到上一套风格的加粗规则。
  static TextStyle? _memoParagraphStyle;
  static double? _memoWeightCompensation;
  static quill.QuillEditorConfig? _memoEditorConfig;

  static quill.QuillEditorConfig _editorConfigFor(
    TextStyle paragraphStyle,
    double weightCompensation,
  ) {
    final cached = _memoEditorConfig;
    if (cached != null &&
        _memoParagraphStyle == paragraphStyle &&
        _memoWeightCompensation == weightCompensation) {
      return cached;
    }
    final config = _staticEditorConfig.copyWith(
      customStyles: _buildCustomStyles(paragraphStyle, weightCompensation),
    );
    _memoParagraphStyle = paragraphStyle;
    _memoWeightCompensation = weightCompensation;
    _memoEditorConfig = config;
    return config;
  }

  static const double collapsedContentMaxHeight = 160.0;

  /// 无宽度兜底判定用的行高（逻辑像素）。
  ///
  /// 真正的折叠判定已经是实测的（见 [exceedsCollapsedHeightForLayout]），这个全局
  /// 值只服务于拿不到布局宽度的兜底路径，由 [_syncEstimatedLineHeight] 跟随主题
  /// 回填。初值是 Material 下的 16×1.5。
  ///
  /// 它进了 `_HeightEstimateCacheKey`，所以换主题后旧估算不会被复用。
  static double estimatedLineHeight = 24.0;
  static const double _lineSpacing = 4.0;
  static const int _averageCharsPerLine = 28;

  /// 纯文本折叠预览的行数上限。
  ///
  /// 折叠盒 160px 配一个正常字号也就十几行，这个值只防畸形样式（`fontSize: 0.1`）
  /// 把预算算成天文数字。**超过它不是夹到它**——见 [collapsedPlainTextMaxLines]。
  static const int _maxCollapsedPlainTextLines = 64;

  /// 拿不到字号时的兜底，取 Material `bodyLarge` 的默认值。
  static const double _fallbackFontSize = 16.0;

  /// 折叠盒（[collapsedContentMaxHeight] 高）最多能显示多少行纯文本。
  ///
  /// **只用来给 `Text` / `TextPainter` 设 `maxLines`，所以必须偏大。** 宁可多排一
  /// 两行——`ClipRect` 会裁掉，看不见；少排的内容却是静悄悄消失的，没有任何提示。
  ///
  /// 偏大由行高取**下界**来保证：`fontSize * (height ?? 1.0)`。`height` 为 null 时
  /// 真实行高由字体的 ascent/descent 决定，普遍是字号的 1.2~1.4 倍，恒不小于这里
  /// 算的值；于是 `ceil(limit / 下界) + 1` 行的真实高度恒 > limit。
  ///
  /// 返回 null 表示**不要设 `maxLines`**。算不出可信预算时只能退回「整篇都排」：
  /// 那只是慢，而夹一个盖不住盒子的行数会真的截断正文。两种情况会退回 null：
  ///
  /// - 行高非有限或 ≤ 0（畸形样式）；
  /// - 预算超过 [_maxCollapsedPlainTextLines]。字号和行高同时极小时，
  ///   **夹到上限的那 64 行仍然填不满 160px 的盒子**，照样会截断——所以上限是
  ///   「超过就放弃截断」，不是「超过就取上限」。
  ///
  /// 存在的理由是性能：`RenderParagraph` **不看高度约束**，不设 `maxLines` 的话
  /// 一条几千字的笔记会把整篇断行整形完，再被 `ClipRect` 裁到只剩五六行——折叠卡片
  /// 为看不见的像素付了全文排版的钱。富文本那条路阶段 D 已经按剩余像素算好了行数
  /// 预算（见 [CollapsedRichTextMetrics.plan]），纯文本这条一直漏着。
  static int? collapsedPlainTextMaxLines({
    required TextStyle? style,
    required TextScaler textScaler,
    double limit = collapsedContentMaxHeight,
  }) {
    final fontSize = style?.fontSize ?? _fallbackFontSize;
    final lineHeight = textScaler.scale(fontSize) * (style?.height ?? 1.0);
    if (!lineHeight.isFinite || lineHeight <= 0) {
      return null;
    }
    final budget = (limit / lineHeight).ceil() + 1;
    if (budget > _maxCollapsedPlainTextLines) {
      return null;
    }
    return budget < 1 ? 1 : budget;
  }

  /// 折叠盒里**放得下几整行**纯文本。
  ///
  /// 和 [collapsedPlainTextMaxLines] 的方向正好相反：那个是给 `TextPainter` 的
  /// 排版上界，必须偏大；这个是给版式的截断点，必须偏小——多一行就会有半行被
  /// 盒子切掉，盒底留下一截被拦腰砍断的字，只能再盖一条模糊带去糊住它。
  ///
  /// 行高取不到（[TextStyle.height] 为 null，真实行高由字体的 ascent/descent 决定，
  /// 这里算不准）时返回 null，表示**别按整行截**，退回原来的「多排 + 裁掉」。
  static int? collapsedPlainTextWholeLines({
    required TextStyle? style,
    required TextScaler textScaler,
    double limit = collapsedContentMaxHeight,
  }) {
    final fontSize = style?.fontSize;
    final height = style?.height;
    if (fontSize == null || height == null) return null;
    final lineHeight = textScaler.scale(fontSize) * height;
    if (!lineHeight.isFinite || lineHeight <= 0) return null;
    final lines = (limit / lineHeight).floor();
    return lines < 1 ? 1 : lines;
  }

  /// 折叠卡片挂缩略图所需的最小容器宽度：缩略图连间距占 84px，再给正文留
  /// 至少 96px，低于这个宽度就不画缩略图，避免 Row 溢出（见 build 中的说明）。
  static const double _minWidthForCollapsedThumbnail = 180.0;
  static const Key collapsedWrapperKey = ValueKey(
    'quote_content.collapsed_wrapper',
  );

  /// 测量缓存的「代号」：[resetCaches] 每清一次自增一次。
  ///
  /// 空闲预热靠它知道自己暖出来的东西还在不在。App 进后台时 `main.dart` 会把下面
  /// 这一整排缓存清空（省内存），而预热的游标停在列表末尾不动 —— 不比对代号的话，
  /// 回到前台后预热永远不会重跑：缓存是空的、游标是满的，每张卡片滑进来都要重新
  /// 算一遍折叠判定和折叠排版。日志里的表现是 `warmup={items=121,cursor=121/121}`
  /// 看着很美，`expand=` 却恰好等于「一共建出来过几张卡」。
  static int _cacheGeneration = 0;

  static int get cacheGeneration => _cacheGeneration;

  static void resetCaches() {
    _cacheGeneration++;
    _QuoteDocumentCache.clear();
    _QuoteHeightEstimateCache.clear();
    _QuotePlainTextLayoutExpansionCache.clear();
    _QuoteContentControllerCache.clear();
    DeltaMediaCache.clear();
    DeltaRichTextCache.clear();
    CollapsedRichTextPlanCache.clear();
  }

  /// 修复问题1：清理特定笔记的缓存（用于笔记删除/更新）
  static void removeCacheForQuote(String quoteId) {
    _QuoteContentControllerCache.removeByQuoteId(quoteId);
    // Document 缓存基于内容哈希，不需要按 ID 清理
  }

  /// 批量清理特定笔记的缓存（优化批量删除操作的性能）
  static void removeCachesForQuotes(Set<String> quoteIds) {
    _QuoteContentControllerCache.removeByQuoteIds(quoteIds);
  }

  @visibleForTesting
  static void clearCacheForTesting() => resetCaches();

  /// 折叠判定的未命中次数。空闲预热拿它给自己记账，见 `note_list_warmup.dart`。
  static int get debugExpansionMissCount =>
      _QuotePlainTextLayoutExpansionCache._missCount;

  /// Returns lightweight cache counters for performance diagnostics.
  static Map<String, dynamic> debugCacheStats() => {
        'document': _QuoteDocumentCache.stats,
        'heightEstimate': _QuoteHeightEstimateCache.stats,
        'controller': _QuoteContentControllerCache.stats,
        // 折叠态的成本现在全在这两项里（document / controller 只剩展开态在用），
        // 性能日志要一行拿全就得带上它们。
        'richText': DeltaRichTextCache.stats,
        'media': DeltaMediaCache.stats,
        // 折叠富文本真正的排版成本在这里。IR 解析（richText）便宜得多，
        // 只盯着它会以为折叠态已经没有成本了。
        'plan': CollapsedRichTextPlanCache.stats,
        // 折叠判定：每张卡片首布局都要走一遍，此前完全没有计量，
        // 见 [_QuotePlainTextLayoutExpansionCache] 的说明。
        'expansion': _QuotePlainTextLayoutExpansionCache.stats,
      };

  /// Returns a compact one-line summary suitable for copy/paste performance logs.
  static String debugCompactCacheStats({Map<String, dynamic>? baseline}) {
    final stats = debugCacheStats();
    final document = Map<String, dynamic>.from(
      stats['document'] as Map<String, dynamic>,
    );
    final height = Map<String, dynamic>.from(
      stats['heightEstimate'] as Map<String, dynamic>,
    );
    final controller = Map<String, dynamic>.from(
      stats['controller'] as Map<String, dynamic>,
    );
    final richText = Map<String, dynamic>.from(
      stats['richText'] as Map<String, dynamic>,
    );
    final media = Map<String, dynamic>.from(
      stats['media'] as Map<String, dynamic>,
    );
    final plan = Map<String, dynamic>.from(
      stats['plan'] as Map<String, dynamic>,
    );
    final expansion = Map<String, dynamic>.from(
      stats['expansion'] as Map<String, dynamic>,
    );

    final buffer = StringBuffer()
      ..write('doc=${document['cacheSize']}')
      ..write('/${document['maxSize']}')
      ..write(',height=${height['cacheSize']}')
      ..write('/${height['maxSize']}')
      ..write(',ctrl=${controller['cacheSize']}')
      ..write('/${controller['maxSize']}')
      ..write(',ctrlCreate=${controller['createCount']}')
      ..write(',ctrlDispose=${controller['disposeCount']}')
      ..write(',ir=${richText['cacheSize']}')
      ..write('/${richText['maxSize']}')
      ..write(',irWorstUs=${richText['worstWorkMicros']}')
      ..write(',media=${media['cacheSize']}')
      ..write('/${media['maxSize']}')
      ..write(',mediaMiss=${media['missCount']}')
      ..write(',plan=${plan['cacheSize']}')
      ..write('/${plan['maxSize']}')
      ..write(',planWorstUs=${plan['worstWorkMicros']}')
      ..write(',expand=${expansion['cacheSize']}')
      ..write('/${expansion['maxSize']}')
      ..write(',expandWorstUs=${expansion['worstWorkMicros']}');

    if (baseline != null) {
      final baselineDocument = Map<String, dynamic>.from(
        baseline['document'] as Map<String, dynamic>? ?? const {},
      );
      final baselineHeight = Map<String, dynamic>.from(
        baseline['heightEstimate'] as Map<String, dynamic>? ?? const {},
      );
      final baselineController = Map<String, dynamic>.from(
        baseline['controller'] as Map<String, dynamic>? ?? const {},
      );
      final baselinePlan = Map<String, dynamic>.from(
        baseline['plan'] as Map<String, dynamic>? ?? const {},
      );
      final baselineExpansion = Map<String, dynamic>.from(
        baseline['expansion'] as Map<String, dynamic>? ?? const {},
      );

      buffer
        ..write(',ΔdocMiss+')
        ..write(_debugIntDelta(document, baselineDocument, 'missCount'))
        ..write(',docWorkUs+')
        ..write(_debugIntDelta(document, baselineDocument, 'workMicros'))
        ..write(',docWorstUs=')
        ..write(_debugNewWorst(document, baselineDocument))
        ..write(',heightMiss+')
        ..write(_debugIntDelta(height, baselineHeight, 'missCount'))
        ..write(',heightWorkUs+')
        ..write(_debugIntDelta(height, baselineHeight, 'workMicros'))
        ..write(',heightWorstUs=')
        ..write(_debugNewWorst(height, baselineHeight))
        ..write(',ctrlMiss+')
        ..write(_debugIntDelta(controller, baselineController, 'missCount'))
        ..write(',ctrlCreate+')
        ..write(_debugIntDelta(controller, baselineController, 'createCount'))
        ..write(',ctrlWorkUs+')
        ..write(_debugIntDelta(controller, baselineController, 'workMicros'))
        ..write(',ctrlWorstUs=')
        ..write(_debugNewWorst(controller, baselineController))
        ..write(',ctrlDispose+')
        ..write(_debugIntDelta(controller, baselineController, 'disposeCount'))
        ..write(',planMiss+')
        ..write(_debugIntDelta(plan, baselinePlan, 'missCount'))
        ..write(',planWorkUs+')
        ..write(_debugIntDelta(plan, baselinePlan, 'workMicros'))
        ..write(',planWorstUs=')
        ..write(_debugNewWorst(plan, baselinePlan))
        ..write(',expandMiss+')
        ..write(_debugIntDelta(expansion, baselineExpansion, 'missCount'))
        ..write(',expandWorkUs+')
        ..write(_debugIntDelta(expansion, baselineExpansion, 'workMicros'))
        ..write(',expandWorstUs=')
        ..write(_debugNewWorst(expansion, baselineExpansion));
    }

    return buffer.toString();
  }

  static int _debugIntDelta(
    Map<String, dynamic> current,
    Map<String, dynamic> baseline,
    String key,
  ) {
    final currentValue = current[key];
    final baselineValue = baseline[key];
    return (currentValue is int ? currentValue : 0) -
        (baselineValue is int ? baselineValue : 0);
  }

  static int _debugNewWorst(
    Map<String, dynamic> current,
    Map<String, dynamic> baseline,
  ) {
    final currentValue = current['worstWorkMicros'];
    final baselineValue = baseline['worstWorkMicros'];
    final currentMicros = currentValue is int ? currentValue : 0;
    final baselineMicros = baselineValue is int ? baselineValue : 0;
    return currentMicros > baselineMicros ? currentMicros : 0;
  }

  /// 没有布局宽度时的折叠判定兜底。
  ///
  /// 只在拿不到 `constraints.maxWidth` 的调用点用；真正的判定走
  /// [exceedsCollapsedHeightForLayout]，那条路是实测的。
  static bool exceedsCollapsedHeight(Quote quote) {
    if (_hasCollapsibleMedia(quote)) return true;
    return _QuoteHeightEstimateCache.getOrCreate(
          quote: quote,
          builder: () => _estimateRenderedHeight(quote),
        ) >
        collapsedContentMaxHeight;
  }

  /// 折叠卡片右侧缩略图占掉的宽度（含间距），不画缩略图时为 0。
  ///
  /// 展开提示遮罩要按这个值内缩，否则渐变和胶囊会横跨整个内容区、把缩略图压在
  /// 底下。判断逻辑和 [build] 里决定画不画缩略图的那段**共用这一处**——两边各写
  /// 一份的话，宽度阈值一改就会错位。
  static double collapsedThumbnailInset({
    required Quote quote,
    required String mediaStyle,
    required double maxWidth,
  }) {
    if (mediaStyle != NoteCardMediaStyle.thumbnail) return 0;
    if (quote.deltaContent == null || quote.editSource != 'fullscreen') {
      return 0;
    }
    if (!DeltaMediaCache.of(quote.deltaContent).hasMedia) return 0;
    // 容器窄到放不下「缩略图 + 一段能读的正文」时整个不画缩略图，见 build。
    if (maxWidth.isFinite && maxWidth < _minWidthForCollapsedThumbnail) {
      return 0;
    }
    return CollapsedMediaThumbnail.reservedWidth();
  }

  /// 折叠态的正文是否**真的被裁掉了一截**。
  ///
  /// 和「要不要展开入口」（[exceedsCollapsedHeightForLayout]）是两个问题，
  /// 必须分开问：带媒体的笔记一律可展开——折叠态永远看不到原图——可它的正文
  /// 常常一个字都没少。折叠提示按「可展开」去画，就会在一条完整的短笔记上盖一条
  /// 模糊带，遮住本来看得全的那行字，而且提示的「还有全文」并不存在。
  ///
  /// 这里量的参数**和渲染侧逐位相同**（同样的正文宽度、同样的媒体版式），所以走的
  /// 是 [CollapsedRichTextMetrics.plan] 的同一条缓存记录，不产生额外测量。
  static bool collapsedTextTruncatedForLayout({
    required BuildContext context,
    required Quote quote,
    required TextStyle? style,
    required double maxWidth,
    required String mediaStyle,
    required bool prioritizeBoldContent,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) return false;

    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      // 走渲染侧那**同一个**函数，参数一个不差，命中的也是同一条 plan 缓存：
      // 判定和画出来的东西不可能漂开，也不产生额外测量。
      final layout = _resolveCollapsedLayout(
        context: context,
        quote: quote,
        style: style,
        maxWidth: maxWidth,
        mediaStyle: mediaStyle,
        prioritizeBoldContent: prioritizeBoldContent,
      );
      if (layout != null) return layout.plan.truncated;
    }

    // 纯文本（含 delta 解不出来的兜底）没有「媒体撑出来的可展开」这回事：
    // 排不下就是被裁了，判定和折叠判定是同一个。走缓存那条路，不重复测量。
    return exceedsCollapsedHeightForLayout(
      quote: quote,
      style: style,
      maxWidth: maxWidth,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      boldWeight: collapsedBoldWeight(context),
      richTextBaseStyle: QuillThemeTypography.paragraphStyle(
        context,
        base: style,
      ),
    );
  }

  /// 带媒体的笔记**一律可展开**。
  ///
  /// 折叠卡片无论哪种版式都不会把媒体按原尺寸画出来：thumbnail 摘成 72px 方图、
  /// banner 压成通栏条、inline 也封顶到
  /// [CollapsedRichText.inlineMediaHeight]。既然折叠态永远看不全，「还有没有更多
  /// 可看」的答案就是肯定的，不该再交给高度阈值去猜——按排版高度算的话，「一张图
  /// 配一句话」会因为算出来不到 160px 而失去展开入口，图片就再也放不大了。
  static bool _hasCollapsibleMedia(Quote quote) {
    if (quote.deltaContent == null || quote.editSource != 'fullscreen') {
      return false;
    }
    return DeltaMediaCache.of(quote.deltaContent).hasMedia;
  }

  /// 无宽度兜底用的粗略高度。
  ///
  /// 富文本按 IR 的块逐段估，而不是拿 [Quote.content] 一把估：测试夹具和历史数据
  /// 里 `content` 未必是 delta 的完整纯文本镜像，拿它估会把长正文的富文本笔记判成
  /// 不需要展开。
  static double _estimateRenderedHeight(Quote quote) {
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      // 口径要和渲染侧一致：同样丢掉尾部空块（delta 结尾总有一个 '\n'），
      // 同样算上块间距。差一个块就是 24px，差 4 个间距就是 16px，
      // 足以让兜底判定和实测判定对同一条笔记给出相反的答案。
      final blocks = CollapsedRichText.visibleBlocks(
        DeltaRichTextCache.of(quote.deltaContent),
        showMedia: true,
      );
      if (blocks.isEmpty) {
        return _estimatePlainTextHeight(quote.content);
      }
      var height = 0.0;
      for (final block in blocks) {
        if (height > 0) height += CollapsedRichText.blockGap;
        height += block.isMedia
            ? CollapsedRichText.inlineMediaHeight
            : _estimatePlainTextHeight(block.plainText);
      }
      return height;
    }
    return _estimatePlainTextHeight(quote.content);
  }

  /// 把 [estimatedLineHeight] 对齐到 [style] 代表的正文行高。
  ///
  /// 只剩无宽度兜底那条路在用它。真正的判定已经改成实测，不再依赖这个全局值。
  static void _syncEstimatedLineHeight(TextStyle? style) {
    final fontSize = style?.fontSize;
    final height = style?.height;
    if (fontSize == null || height == null) return;
    estimatedLineHeight = fontSize * height;
  }

  /// 当前布局下 [quote] 是否需要折叠。
  ///
  /// 纯文本和富文本现在是**同一个口径**：都用 [TextPainter] 按真实 [style]、
  /// [maxWidth]、[textDirection]、[textScaler] 和 [locale] 实测。
  ///
  /// 富文本以前只能退回「28 个字符算一行」的静态估算——那个数字对中英文混排、
  /// 标题、列表和字号属性全都不准，足以让一条实际超过 160px 的笔记被判成
  /// 「不需要展开」，展开入口直接不出现。折叠预览改用 `Text.rich` 之后，富文本
  /// 也有 span 可以量了，两条路才终于对齐。
  static bool exceedsCollapsedHeightForLayout({
    required Quote quote,
    required TextStyle? style,
    required double maxWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
    Locale? locale,
    FontWeight boldWeight = FontWeight.bold,

    /// 富文本折叠预览的基准样式，应当是调用方用
    /// [QuillThemeTypography.paragraphStyle] 解析好的那一份——**和渲染同一个对象**。
    ///
    /// 不传时退回 [style]。纯文本分支始终用 [style]，因为它渲染时用的就是 [style]：
    /// 两条路各自和自己的渲染对齐，不能混用同一个样式。
    TextStyle? richTextBaseStyle,
  }) {
    _syncEstimatedLineHeight(style);

    if (!maxWidth.isFinite || maxWidth <= 0) {
      return exceedsCollapsedHeight(quote);
    }

    final isRichText =
        quote.deltaContent != null && quote.editSource == 'fullscreen';

    return _QuotePlainTextLayoutExpansionCache.getOrCreate(
      quote: quote,
      // 富文本的判定读的是 deltaContent，而缓存键原本只认 content。给笔记加一张
      // 图、把一段标成标题这类**只改格式不改纯文本**的编辑，content 一个字都不变，
      // 判定却应该翻转——不把 deltaContent 编进键，卡片就会一直沿用旧答案，
      // 新加的图片永远等不到展开入口。
      contentSignatureSalt: quote.deltaContent?.hashCode,
      style: style,
      // 字重进键：Android + material 下渲染用的是降档后的 w500，判定也得用同一档，
      // 否则贴着 160px 阈值的加粗卡片会「判定说要折叠、画出来其实没超」。
      boldWeight: boldWeight,
      // 富文本实际是按这个样式量的，它必须跟着进键。只把参数加到 getOrCreate 的
      // 签名和键里、忘了从这里传，等于键里永远是 null——参数看着在，其实是死的。
      richTextBaseStyle: richTextBaseStyle,
      maxWidth: maxWidth,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      builder: () {
        // IR 为空说明 delta 解不出来，渲染侧会退回纯文本（见 build）。判定必须跟着
        // 退回同一份内容去量，否则一条正文很长的坏笔记会被判成「不需要折叠」——
        // 纯文本兜底照着这个答案不加裁剪地铺开，整篇糊在列表里，还没有展开入口。
        final blocks =
            isRichText ? DeltaRichTextCache.of(quote.deltaContent) : null;
        if (blocks != null && blocks.isNotEmpty) {
          // 带媒体一律可展开，见 [_hasCollapsibleMedia]。
          if (DeltaMediaCache.of(quote.deltaContent).hasMedia) {
            return true;
          }
          // 判定用的是「媒体还在正文里」的口径：折叠盒是否需要展开入口，取决于
          // 完整内容放不放得下，而不是某个版式摘掉媒体之后剩多少。
          final plan = CollapsedRichTextMetrics.plan(
            blocks: blocks,
            baseStyle: richTextBaseStyle ?? style ?? const TextStyle(),
            maxWidth: maxWidth,
            limit: collapsedContentMaxHeight,
            showMedia: true,
            boldWeight: boldWeight,
            textDirection: textDirection,
            textScaler: textScaler,
            locale: locale,
            // 这里的 blocks 是 DeltaRichTextCache 的原序列，没有按加粗重排。
            cacheContent: quote.deltaContent,
          );
          // 判据是**排版计划有没有画全**，不是它有多高。
          //
          // 正文改成按整行截断之后，计划的高度恒不超过盒子（放不下的整行根本不
          // 排），拿高度和 160 比就永远得到「不用展开」——被裁掉一半的长笔记会
          // 连展开入口一起失去。`truncated` 才是「还有内容没显示」的那个答案。
          return plan.truncated;
        }

        // `maxLines` 不改变这个判断的答案，只砍掉多余的排版量：
        // n 行的真实高度恒 > 160.5（见 [collapsedPlainTextMaxLines]），所以正文
        // 超过 n 行时被夹住的 height 仍然 > 阈值，不超过 n 行时 height 就是精确值。
        final painter = TextPainter(
          text: TextSpan(text: quote.content, style: style),
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
          maxLines: collapsedPlainTextMaxLines(
            style: style,
            textScaler: textScaler,
          ),
        )..layout(maxWidth: maxWidth);
        final exceeds = painter.height > collapsedContentMaxHeight + 0.5;
        painter.dispose();
        return exceeds;
      },
    );
  }

  static double _estimatePlainTextHeight(String content) {
    if (content.trim().isEmpty) {
      return estimatedLineHeight;
    }

    final lines = content.split('\n');
    double height = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        height += estimatedLineHeight * 0.5;
        continue;
      }

      int approxLines = line.length ~/ _averageCharsPerLine;
      if (line.length % _averageCharsPerLine != 0) {
        approxLines += 1;
      }
      if (approxLines < 1) {
        approxLines = 1;
      }

      height += approxLines * estimatedLineHeight;
    }

    if (lines.length > 1) {
      height += (lines.length - 1) * _lineSpacing;
    }

    return height;
  }

  static List<Map<String, dynamic>>? _decodeDeltaOps(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((op) => Map<String, dynamic>.from(op))
            .toList();
      }
      if (decoded is Map && decoded.containsKey('ops')) {
        final ops = decoded['ops'];
        if (ops is List) {
          return ops
              .whereType<Map>()
              .map((op) => Map<String, dynamic>.from(op))
              .toList();
        }
      }
    } catch (_) {
      // ignore and fall back to plain text content
    }
    return null;
  }

  static List<Map<String, dynamic>> _normalizedDocumentOps(
    List<Map<String, dynamic>> ops,
  ) {
    final normalizedOps =
        ops.map((op) => Map<String, dynamic>.from(op)).toList();
    _ensureDocumentOpsEndWithNewline(normalizedOps);
    return normalizedOps;
  }

  static void _ensureDocumentOpsEndWithNewline(
    List<Map<String, dynamic>> ops,
  ) {
    if (ops.isEmpty) {
      ops.add({'insert': '\n'});
      return;
    }

    final lastInsert = ops.last['insert'];
    if (lastInsert is! String || !lastInsert.endsWith('\n')) {
      ops.add({'insert': '\n'});
    }
  }

  /// 展开态和全屏编辑器用的完整 Document。
  ///
  /// 折叠态**不再走这里**：它由 [CollapsedRichText] 直接排 `Text.rich`，既不建
  /// Document 也不建 `QuillEditor`。所以这里没有截断分支了——需要截断的那条路
  /// 已经整个不存在。
  quill.Document _buildRichTextDocument(String deltaContent) {
    final ops = _decodeDeltaOps(deltaContent);
    if (ops != null) {
      return quill.Document.fromJson(_normalizedDocumentOps(ops));
    }
    return _documentFromDelta(deltaContent);
  }

  quill.Document _documentFromDelta(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        return quill.Document.fromJson(decoded);
      }
      if (decoded is Map && decoded.containsKey('ops')) {
        final ops = decoded['ops'];
        if (ops is List) {
          return quill.Document.fromJson(ops);
        }
      }
    } catch (_) {
      // ignore and fall back to plain text content
    }

    return quill.Document()..insert(0, quote.content);
  }

  /// 折叠富文本一次布局需要的全部东西：量好的 plan、缩略图预留宽、媒体摘要，
  /// 以及排版用的基准样式与字重。
  ///
  /// [build] 和 [warmCollapsedLayout] **共用这一处**。空闲预热的全部价值在于
  /// 它跑出来的缓存键和渲染时问的键一模一样；两边各写一份 plan 入参的话，
  /// 哪天有人只改了其中一处，预热就变成静悄悄的空转 —— 日志里只会看到
  /// `planMiss+` 没降，而没人知道为什么。
  ///
  /// 返回 null 表示这条笔记解不出富文本块，调用方应退回纯文本。
  static _CollapsedLayout? _resolveCollapsedLayout({
    required BuildContext context,
    required Quote quote,
    required TextStyle? style,
    required double maxWidth,
    required String mediaStyle,
    required bool prioritizeBoldContent,
  }) {
    final bool stripMedia = mediaStyle != NoteCardMediaStyle.inline;
    final media = stripMedia
        ? DeltaMediaCache.of(quote.deltaContent)
        : DeltaMediaSummary.empty;

    var blocks = DeltaRichTextCache.of(quote.deltaContent);
    if (blocks.isEmpty) return null;
    if (prioritizeBoldContent) {
      blocks = prioritizeBoldBlocks(blocks);
    }

    final baseStyle = QuillThemeTypography.paragraphStyle(context, base: style);
    // 折叠预览的加粗必须和展开态用同一档字重，见 `_buildCustomStyles`：
    // Android + material 下 quill 把 bold 降到 w500，这里不跟着降的话，
    // 同一条笔记折叠时比展开后更粗。
    final boldWeight = collapsedBoldWeight(context);

    // 容器窄到放不下「缩略图 + 一段能读的正文」时**整个不画缩略图**。
    //
    // 只把预留宽度 clamp 小是没用的：Row 的固定子项（gap + 缩略图）恒占
    // 84px，与 reserved 取什么值无关；`constraints.maxWidth` 一旦小于 84，
    // `Expanded` 照样分到负空间、RenderFlex 照样溢出。只有不挂这两个子项
    // 才真的不溢出。折叠正文区正常不会窄到这个程度，这里纯粹是防御。
    final double reserved = collapsedThumbnailInset(
      quote: quote,
      mediaStyle: mediaStyle,
      maxWidth: maxWidth,
    );
    // 文字宽度要先扣掉缩略图占的位，否则排版会按整宽算而少排内容。
    final double textMaxWidth =
        maxWidth.isFinite ? maxWidth - reserved : maxWidth;

    // 量一次，盒高和要画的内容都从这一次的结果来。上限 160：内容排满就是
    // 160，媒体被摘走后只剩一两行就取那几行的高度，卡片里不会留一块空白。
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    CollapsedRichTextPlan planFor(double width) {
      return CollapsedRichTextMetrics.plan(
        blocks: blocks,
        baseStyle: baseStyle,
        maxWidth: width,
        limit: collapsedContentMaxHeight,
        showMedia: !stripMedia,
        boldWeight: boldWeight,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        cacheContent: quote.deltaContent,
        cacheBoldPrioritized: prioritizeBoldContent,
      );
    }

    var plan = planFor(textMaxWidth);
    var thumbnailSize = CollapsedMediaThumbnail.defaultSize;

    // 正文只有一两行时，右边那张 72 见方的小图撑不满卡片，左边一大块空着。
    // 这种卡片把图放大到 96：多出来的高度全给了照片，卡片反而不空。
    //
    // 放大要**重新排一次版**：图宽了正文列就窄了，沿用按 72 算出来的行数会让最后
    // 一行悄悄少几个字——版式必须和测量同宽。重排后仍然短、仍然不截断才真的放大。
    //
    // 这一段留在这里而不是放到 build 里，是因为空闲预热（[warmCollapsedLayout]）
    // 走的也是这个函数：两次排版都得在预热时跑热，否则短笔记卡片滑进来时还要现算
    // 第二次。
    if (reserved > 0 &&
        !plan.truncated &&
        plan.height <= CollapsedMediaThumbnail.shortNoteSize) {
      final double enlargedTextWidth = maxWidth -
          CollapsedMediaThumbnail.reservedWidth(
            size: CollapsedMediaThumbnail.shortNoteSize,
          );
      if (enlargedTextWidth > 0) {
        final enlargedPlan = planFor(enlargedTextWidth);
        if (!enlargedPlan.truncated &&
            enlargedPlan.height <= CollapsedMediaThumbnail.shortNoteSize) {
          plan = enlargedPlan;
          thumbnailSize = CollapsedMediaThumbnail.shortNoteSize;
        }
      }
    }

    return _CollapsedLayout(
      plan: plan,
      thumbnailInset: reserved,
      thumbnailSize: thumbnailSize,
      media: media,
      baseStyle: baseStyle,
      boldWeight: boldWeight,
    );
  }

  /// 空闲预热：用**和渲染完全相同的入参**把这条笔记的折叠排版缓存跑热。
  ///
  /// 首滑卡顿里有一块是每张新卡片首次布局时才第一次做折叠排版（日志里的
  /// `planMiss+`、`planWorkUs+`）。结果只跟内容和布局宽度有关，完全可以在列表
  /// 静止时提前算好；等卡片真的滑进来时全是命中。
  static void warmCollapsedLayout({
    required BuildContext context,
    required Quote quote,
    required TextStyle? style,
    required double maxWidth,
    required String mediaStyle,
    required bool prioritizeBoldContent,
  }) {
    if (quote.deltaContent == null || quote.editSource != 'fullscreen') return;
    if (!maxWidth.isFinite || maxWidth <= 0) return;

    // 结果只为把缓存跑热，本身丢掉即可。
    _resolveCollapsedLayout(
      context: context,
      quote: quote,
      style: style,
      maxWidth: maxWidth,
      mediaStyle: mediaStyle,
      prioritizeBoldContent: prioritizeBoldContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 这条路径也可能在富文本 build 回填之前就走到无宽度兜底。
    _syncEstimatedLineHeight(style);
    final bool needsExpansion =
        needsExpansionOverride ?? exceedsCollapsedHeight(quote);

    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      // 只要不是展开态，列表里的富文本卡片**一律**走 `Text.rich` 预览，长短都一样。
      //
      // 以前这里还要求 `needsExpansion`：短到不用折叠的富文本笔记会落进下面的
      // Quill 分支，于是列表里最常见的那类卡片反而每张都建一棵编辑器树——阶段 D
      // 想去掉的冷首布局有相当一部分就在这里。短卡片没有折叠盒（下面按
      // [needsExpansion] 决定要不要定高裁剪），但渲染路径和长卡片是同一条。
      if (!showFullContent) {
        // 折叠态的媒体有三种版式，开发者模式下可切换，见 [NoteCardMediaStyle]。
        //
        // thumbnail / banner 把媒体摘出正文单独渲染；inline 把媒体留在原位，由
        // [CollapsedRichText] 按「文字段, 媒体, 文字段…」的顺序交错排出来。三种
        // 版式现在都不建 `QuillEditor`，媒体也就都和卡片同时挂载，不再有
        // 「空白 → 灰框 → 图片」的三段式。
        final String mediaStyle = context.select<SettingsService, String>(
          (s) => s.noteCardMediaStyle,
        );
        final bool prioritizeBoldContent =
            context.select<SettingsService, bool>(
          (s) => s.prioritizeBoldContentInCollapse,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final layout = _resolveCollapsedLayout(
              context: context,
              quote: quote,
              style: style,
              maxWidth: constraints.maxWidth,
              mediaStyle: mediaStyle,
              prioritizeBoldContent: prioritizeBoldContent,
            );
            if (layout == null) {
              // delta 解不出来（损坏、导入了别家的格式、同步冲突写坏了）时**退回纯
              // 文本**。旧实现在 `_documentFromDelta` 里也有这条兜底；直接画空的话，
              // 卡片正文整个消失，而且因为量出来是 0 高，连双击展开都进不去——用户会
              // 以为笔记内容丢了。
              return _buildPlainTextContent(
                context,
                needsExpansion: needsExpansion,
              );
            }

            final media = layout.media;
            final baseStyle = layout.baseStyle;
            final boldWeight = layout.boldWeight;
            final double reserved = layout.thumbnailInset;
            final bool showThumbnail = reserved > 0;
            final bool showBanner =
                mediaStyle == NoteCardMediaStyle.banner && media.hasMedia;

            // 排版计划、盒高、缩略图尺寸都由 `_resolveCollapsedLayout` 一次算好，
            // 空闲预热走的是同一个函数，滑进来时全是缓存命中。
            final plan = layout.plan;
            final double thumbnailSize = layout.thumbnailSize;
            final double boxHeight =
                plan.height.clamp(0.0, collapsedContentMaxHeight);

            // 纯媒体笔记（摘掉媒体后一个字都不剩）连正文和间距一起省掉。
            final bool hasTextContent = !plan.isEmpty && boxHeight > 0;

            // 只有音视频、没有可预览的图片时不装点击手势：否则是个空操作，
            // 既吞掉卡片自身的交互，又把不可预览的媒体伪装成可点。
            final VoidCallback? onMediaTap = media.firstImageSource != null
                ? () => _openMediaPreview(context, media)
                : null;

            Widget content = hasTextContent
                ? CollapsedRichText(
                    plan: plan,
                    baseStyle: baseStyle,
                    boldWeight: boldWeight,
                    onMediaTap: (ref) => _openMediaSource(context, ref.source),
                  )
                : const SizedBox.shrink();

            if (hasTextContent) {
              // 定高裁剪只给真正需要折叠的卡片。短卡片让 `Text.rich` 自然定高：
              // 测量与渲染之间哪怕只差半个像素，套在短卡片上也会啃掉一截下伸部。
              if (needsExpansion) {
                content = _CollapsedContentWrapper(
                  key: collapsedWrapperKey,
                  maxHeight: boxHeight,
                  child: content,
                );
              }
              if (collapseRichTextSemantics) {
                content = Semantics(
                  key: const ValueKey('quote_content.rich_text_semantics'),
                  container: true,
                  label: quote.content,
                  child: ExcludeSemantics(child: content),
                );
              }
            }

            if (showBanner) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CollapsedMediaBanner(media: media, onTap: onMediaTap),
                  if (hasTextContent) ...[
                    const SizedBox(height: CollapsedMediaBanner.gap),
                    content,
                  ],
                ],
              );
            }

            if (!showThumbnail) {
              return content;
            }

            // 一个字都没有的纯图笔记，右侧小图会把整张卡片的左边空成一块白。
            // 照片就是这条笔记的全部内容，给它一张更大的方图，居中放。
            //
            // **刻意不铺成通栏**：通栏是定高的，`cover` 会把竖版照片裁成顶部
            // 一条横带（人像只剩半个头），而手机照片竖版居多；解码开销也要贵
            // 一个量级。方图对各种比例的裁切都更温和，也和用户在设置里选的
            // 「右侧小图」是同一种东西，只是大一号。
            if (!hasTextContent) {
              return Align(
                alignment: Alignment.center,
                child: CollapsedMediaThumbnail(
                  media: media,
                  onTap: onMediaTap,
                  size: CollapsedMediaThumbnail.soloMediaSize,
                ),
              );
            }

            return Row(
              // 正文比缩略图矮时（媒体摘走后只剩一两行）顶部对齐会在文字下方留出
              // 一大块空白，这时改成居中；正文更高时仍然顶部对齐。
              crossAxisAlignment: boxHeight <= thumbnailSize
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Expanded(child: content),
                const SizedBox(width: CollapsedMediaThumbnail.gap),
                CollapsedMediaThumbnail(
                  media: media,
                  onTap: onMediaTap,
                  size: thumbnailSize,
                ),
              ],
            );
          },
        );
      }
      return _buildRichTextContent(context);
    }

    return _buildPlainTextContent(context, needsExpansion: needsExpansion);
  }

  /// 纯文本正文。富文本的 delta 解不出来时也走这里兜底。
  Widget _buildPlainTextContent(
    BuildContext context, {
    required bool needsExpansion,
  }) {
    // 折叠态给 `maxLines` 封顶。盒子是 `ClipRect(SizedBox(height: 160))`，而
    // `RenderParagraph` 不看高度约束——不封顶的话整篇正文都会被断行整形一遍，
    // 然后裁到只剩五六行。行数取的是偏大的上界，裁出来的像素和以前逐位相同。
    final bool clampToCollapsedBox = !showFullContent && needsExpansion;

    // 行数预算必须按 `Text` **实际用的**样式算，不能按传进来的 [style] 算。
    // `Text` 会把 [style] 往 `DefaultTextStyle` 上 merge（`inherit` 为 true 时），
    // 字号可能整个来自环境；照着一个 fontSize 为 null 的样式去估，行高就会被
    // 高估，行数被低估，正文尾巴静悄悄少一截。这里复刻 `Text` 自己的合并规则。
    //
    // 下面两个预算**必须共用这一份样式**：`collapsedMaxLines` 是给排版的上界，
    // `wholeLines` 是截断点，两者按不同样式算出来就会互相打架。
    int? collapsedMaxLines;
    // 整行截断：盒子放得下几整行就画几行，末行收省略号。行高是确定的（同一段
    // 纯文本只有一种样式），所以不必测量就能算出来；算不出来时退回原来的
    // 「多排 + 裁掉」，那条路只是会在盒底留半行残字，不会丢内容。
    int? wholeLines;
    if (clampToCollapsedBox) {
      final TextStyle? rawStyle = style;
      final defaultStyle = DefaultTextStyle.of(context).style;
      final effectiveStyle = rawStyle == null || rawStyle.inherit
          ? defaultStyle.merge(rawStyle)
          : rawStyle;
      final textScaler = MediaQuery.textScalerOf(context);
      collapsedMaxLines = collapsedPlainTextMaxLines(
        style: effectiveStyle,
        textScaler: textScaler,
      );
      wholeLines = collapsedPlainTextWholeLines(
        style: effectiveStyle,
        textScaler: textScaler,
      );
    }
    final bool useEllipsis = clampToCollapsedBox && wholeLines != null;

    Widget plainText = Text(
      quote.content,
      style: style,
      softWrap: true,
      maxLines:
          clampToCollapsedBox ? (wholeLines ?? collapsedMaxLines) : maxLines,
      overflow: useEllipsis
          ? TextOverflow.ellipsis
          : (clampToCollapsedBox ? TextOverflow.clip : TextOverflow.visible),
    );

    if (clampToCollapsedBox) {
      plainText = _CollapsedContentWrapper(
        key: collapsedWrapperKey,
        maxHeight: collapsedContentMaxHeight,
        child: plainText,
      );
    }

    return plainText;
  }

  /// 折叠预览里「粗体」该用哪一档字重，规则与 [_buildCustomStyles] 一致。
  ///
  /// 判定侧（`quote_item_widget`）也要拿它，好和渲染侧量同一件事。
  static FontWeight collapsedBoldWeight(BuildContext context) {
    final weightCompensation =
        AppTypographyTokens.of(context).variableWeightCompensation;
    if (kIsWeb || !Platform.isAndroid || weightCompensation <= 0) {
      return FontWeight.bold;
    }
    return FontWeight.w500;
  }

  /// 点击折叠卡片上的媒体：打开首图的大图预览。
  ///
  /// 和「双击卡片展开」是两件事，不冲突：展开看的是完整正文，预览看的是这一张图。
  /// 没有图片（只有音视频）时不做任何事——那两类的播放入口在展开态里。
  void _openMediaPreview(BuildContext context, DeltaMediaSummary media) {
    _openMediaSource(context, media.firstImageSource);
  }

  /// 打开某一张图的大图预览。inline 版式点的是正文里那一张，所以按 source 走，
  /// 不走「首图」。
  void _openMediaSource(BuildContext context, String? source) {
    if (source == null || source.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MotionPhotoPreviewPage(imageUrl: source),
      ),
    );
  }

  /// 展开态与全屏预览的富文本：仍然由真正的 `QuillEditor` 渲染，一个字没动。
  ///
  /// 折叠态已经完全不走这里——它由 [CollapsedRichText] 排 `Text.rich`。所以这个
  /// 方法不再需要截断、占位、每帧额度和恢复队列那一整套时序参数：展开是用户主动
  /// 双击触发的单张卡片，本来就不在滚动热路径上。
  Widget _buildRichTextContent(BuildContext context) {
    final String cacheQuoteId =
        quote.id ?? 'local_${quote.date}_${quote.content.hashCode}';
    const String contentVariant = 'full';
    final String contentSignature =
        '${quote.deltaContent!.hashCode}_${quote.deltaContent!.length}_$contentVariant';

    final _CachedControllerSet controllerSet =
        _QuoteContentControllerCache.getOrCreate(
      quoteId: cacheQuoteId,
      contentSignature: contentSignature,
      variant: contentVariant,
      documentBuilder: () => _QuoteDocumentCache.getOrCreate(
        deltaContent: quote.deltaContent!,
        prioritizeBold: false,
        truncateForCollapse: false,
        builder: () => _buildRichTextDocument(quote.deltaContent!),
      ),
    );

    // quill 把段落的 fontSize/height 硬写成 16 / 1.15，两样都得按主题令牌纠正。
    // 字号原本也硬写 16：material 下 bodyLarge 正好是 16 所以看不出问题，
    // 衬线风格把正文放大到 17（ThemeStyleForm.readingFontScale）之后就露馅了——
    // 同一个列表里富文本笔记比纯文本笔记小一号，纸张横线也只跟纯文本对齐。
    // 纠正规则和全屏编辑器共用一处，见 QuillThemeTypography。
    final paragraphStyle =
        QuillThemeTypography.paragraphStyle(context, base: style);

    Widget richTextEditor = quill.QuillEditor(
      controller: controllerSet.quillController,
      scrollController: controllerSet.scrollController,
      focusNode: controllerSet.focusNode,
      config: _editorConfigFor(
        paragraphStyle,
        AppTypographyTokens.of(context).variableWeightCompensation,
      ),
    );

    if (style != null) {
      richTextEditor = DefaultTextStyle.merge(
        style: style!,
        child: richTextEditor,
      );
    }

    if (collapseRichTextSemantics) {
      richTextEditor = Semantics(
        key: const ValueKey('quote_content.rich_text_semantics'),
        container: true,
        label: quote.content,
        child: ExcludeSemantics(child: richTextEditor),
      );
    }

    return richTextEditor;
  }
}

/// [QuoteContent._resolveCollapsedLayout] 的结果。
@immutable
class _CollapsedLayout {
  const _CollapsedLayout({
    required this.plan,
    required this.thumbnailInset,
    required this.thumbnailSize,
    required this.media,
    required this.baseStyle,
    required this.boldWeight,
  });

  final CollapsedRichTextPlan plan;
  final double thumbnailInset;

  /// 右侧缩略图这次画多大。正文短到撑不满时会放大，见 `_resolveCollapsedLayout`。
  final double thumbnailSize;

  final DeltaMediaSummary media;
  final TextStyle baseStyle;
  final FontWeight boldWeight;
}

class _CollapsedContentWrapper extends StatelessWidget {
  final Widget child;
  final double maxHeight;

  const _CollapsedContentWrapper({
    super.key,
    required this.child,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    // 恒定高度。占位文本和 Quill 文档的自然高度并不相同，一旦盒子跟着内容走，
    // 物化的那一刻卡片就会跳——高度该取多少由 [QuoteContent.collapsedBoxHeightFor]
    // 按版式算好后传进来。
    return ClipRect(
      child: SizedBox(
        height: maxHeight,
        child: child,
      ),
    );
  }
}

class _QuoteHeightEstimateCache {
  static final LinkedHashMap<_HeightEstimateCacheKey, _HeightEstimateCacheEntry>
      _cache =
      LinkedHashMap<_HeightEstimateCacheKey, _HeightEstimateCacheEntry>();

  static const int _maxCacheSize = 300;
  static const int _pruneBatchSize = 50;

  static int _hitCount = 0;
  static int _missCount = 0;
  static int _workMicros = 0;
  static int _worstWorkMicros = 0;

  static double getOrCreate({
    required Quote quote,
    required double Function() builder,
  }) {
    final key = _HeightEstimateCacheKey.fromQuote(quote);
    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      existing.touch();
      _cache[key] = existing;
      return existing.height;
    }

    _missCount++;
    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    final stopwatch = Stopwatch()..start();
    final height = builder();
    stopwatch.stop();
    _workMicros += stopwatch.elapsedMicroseconds;
    if (stopwatch.elapsedMicroseconds > _worstWorkMicros) {
      _worstWorkMicros = stopwatch.elapsedMicroseconds;
    }
    _cache[key] = _HeightEstimateCacheEntry(height: height);
    return height;
  }

  static void clear() {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
    _workMicros = 0;
    _worstWorkMicros = 0;
  }

  static Map<String, dynamic> get stats {
    final total = _hitCount + _missCount;
    final double hitRate = total == 0 ? 0 : _hitCount / total;
    return {
      'cacheSize': _cache.length,
      'maxSize': _maxCacheSize,
      'hitCount': _hitCount,
      'missCount': _missCount,
      'workMicros': _workMicros,
      'worstWorkMicros': _worstWorkMicros,
      'hitRate': hitRate,
    };
  }

  static void _pruneOldest() {
    if (_cache.isEmpty) {
      return;
    }

    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    for (final entry in entries.take(_pruneBatchSize)) {
      _cache.remove(entry.key);
    }
  }
}

class _HeightEstimateCacheKey {
  const _HeightEstimateCacheKey({
    required this.contentSignature,
    required this.isRichText,
    required this.lineHeight,
  });

  factory _HeightEstimateCacheKey.fromQuote(Quote quote) {
    final richContent =
        quote.deltaContent != null && quote.editSource == 'fullscreen';
    final content = richContent ? quote.deltaContent! : quote.content;
    return _HeightEstimateCacheKey(
      contentSignature: Object.hash(content.hashCode, content.length),
      isRichText: richContent,
      // 估算行高随主题变化，切换风格后同一条笔记的估算结果不同，
      // 必须进键，否则会读到上一套风格算出来的高度、把展开按钮判错。
      lineHeight: QuoteContent.estimatedLineHeight,
    );
  }

  final int contentSignature;
  final bool isRichText;
  final double lineHeight;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _HeightEstimateCacheKey &&
        other.contentSignature == contentSignature &&
        other.isRichText == isRichText &&
        other.lineHeight == lineHeight;
  }

  @override
  int get hashCode => Object.hash(contentSignature, isRichText, lineHeight);
}

class _HeightEstimateCacheEntry {
  _HeightEstimateCacheEntry({required this.height})
      : lastAccess = DateTime.now();

  final double height;
  DateTime lastAccess;

  void touch() {
    lastAccess = DateTime.now();
  }
}

class _QuotePlainTextLayoutExpansionCache {
  static final LinkedHashMap<_PlainTextLayoutExpansionCacheKey,
          _PlainTextLayoutExpansionCacheEntry> _cache =
      LinkedHashMap<_PlainTextLayoutExpansionCacheKey,
          _PlainTextLayoutExpansionCacheEntry>();

  static const int _maxCacheSize = 300;
  static const int _pruneBatchSize = 50;

  // 这条路是**每张卡片每次首布局都要走一遍**的：它在 `LayoutBuilder` 里跑一次
  // `TextPainter.layout`（富文本则是一次 `plan()`），就为了回答"要不要展开入口"。
  // 2026-08-13 的诊断点名它"一个计数器都没有"，于是此后每一轮都只能猜首滑的成本
  // 落在哪。补上之后，`itemLayout` 总时间减掉 expandWorkUs 和 planWorkUs，
  // 剩下的才是真正的 widget 布局。
  static int _hitCount = 0;
  static int _missCount = 0;
  static int _workMicros = 0;
  static int _worstWorkMicros = 0;

  static Map<String, dynamic> get stats => {
        'cacheSize': _cache.length,
        'maxSize': _maxCacheSize,
        'hitCount': _hitCount,
        'missCount': _missCount,
        'workMicros': _workMicros,
        'worstWorkMicros': _worstWorkMicros,
      };

  static bool getOrCreate({
    required Quote quote,
    required TextStyle? style,
    required double maxWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
    required bool Function() builder,
    int? contentSignatureSalt,
    FontWeight boldWeight = FontWeight.bold,
    TextStyle? richTextBaseStyle,
  }) {
    final key = _PlainTextLayoutExpansionCacheKey(
      contentSignature: Object.hash(
        quote.content.hashCode,
        quote.content.length,
        contentSignatureSalt,
      ),
      maxWidthKey: (maxWidth * 100).round(),
      styleHash: Object.hash(
        style.hashCode,
        richTextBaseStyle.hashCode,
        boldWeight.value,
      ),
      textDirection: textDirection,
      textScalerHash: textScaler.hashCode,
      localeTag: locale?.toLanguageTag(),
    );
    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      existing.touch();
      _cache[key] = existing;
      return existing.exceedsCollapsedHeight;
    }

    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    final stopwatch = Stopwatch()..start();
    final exceedsCollapsedHeight = builder();
    stopwatch.stop();
    _missCount++;
    _workMicros += stopwatch.elapsedMicroseconds;
    if (stopwatch.elapsedMicroseconds > _worstWorkMicros) {
      _worstWorkMicros = stopwatch.elapsedMicroseconds;
    }
    _cache[key] = _PlainTextLayoutExpansionCacheEntry(
      exceedsCollapsedHeight: exceedsCollapsedHeight,
    );
    return exceedsCollapsedHeight;
  }

  static void clear() {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
    _workMicros = 0;
    _worstWorkMicros = 0;
  }

  static void _pruneOldest() {
    if (_cache.isEmpty) {
      return;
    }

    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    for (final entry in entries.take(_pruneBatchSize)) {
      _cache.remove(entry.key);
    }
  }
}

class _PlainTextLayoutExpansionCacheKey {
  const _PlainTextLayoutExpansionCacheKey({
    required this.contentSignature,
    required this.maxWidthKey,
    required this.styleHash,
    required this.textDirection,
    required this.textScalerHash,
    required this.localeTag,
  });

  final int contentSignature;
  final int maxWidthKey;
  final int styleHash;
  final TextDirection textDirection;
  final int textScalerHash;
  final String? localeTag;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _PlainTextLayoutExpansionCacheKey &&
        other.contentSignature == contentSignature &&
        other.maxWidthKey == maxWidthKey &&
        other.styleHash == styleHash &&
        other.textDirection == textDirection &&
        other.textScalerHash == textScalerHash &&
        other.localeTag == localeTag;
  }

  @override
  int get hashCode => Object.hash(
        contentSignature,
        maxWidthKey,
        styleHash,
        textDirection,
        textScalerHash,
        localeTag,
      );
}

class _PlainTextLayoutExpansionCacheEntry {
  _PlainTextLayoutExpansionCacheEntry({
    required this.exceedsCollapsedHeight,
  }) : lastAccess = DateTime.now();

  final bool exceedsCollapsedHeight;
  DateTime lastAccess;

  void touch() {
    lastAccess = DateTime.now();
  }
}

class _QuoteDocumentCache {
  static final LinkedHashMap<_DocumentCacheKey, _DocumentCacheEntry> _cache =
      LinkedHashMap<_DocumentCacheKey, _DocumentCacheEntry>();
  static const int _maxCacheSize = 120;
  static const int _pruneBatchSize = 20;

  static int _hitCount = 0;
  static int _missCount = 0;
  static int _workMicros = 0;
  static int _worstWorkMicros = 0;

  static quill.Document getOrCreate({
    required String deltaContent,
    required bool prioritizeBold,
    required bool truncateForCollapse,
    String layoutSignature = 'legacy',
    required quill.Document Function() builder,
  }) {
    final key = _DocumentCacheKey(
      deltaContent: deltaContent,
      prioritizeBold: prioritizeBold,
      truncateForCollapse: truncateForCollapse,
      layoutSignature: layoutSignature,
    );

    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      existing.touch();
      _cache[key] = existing;
      return existing.document;
    }

    _missCount++;
    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    quill.Document document;
    final stopwatch = Stopwatch()..start();
    try {
      document = builder();
    } catch (_) {
      document = quill.Document()..insert(0, '');
    }
    stopwatch.stop();
    _workMicros += stopwatch.elapsedMicroseconds;
    if (stopwatch.elapsedMicroseconds > _worstWorkMicros) {
      _worstWorkMicros = stopwatch.elapsedMicroseconds;
    }

    _cache[key] = _DocumentCacheEntry(document: document);
    return document;
  }

  static void clear() {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
    _workMicros = 0;
    _worstWorkMicros = 0;
  }

  static Map<String, dynamic> get stats {
    final total = _hitCount + _missCount;
    final double hitRate = total == 0 ? 0 : _hitCount / total;
    return {
      'cacheSize': _cache.length,
      'maxSize': _maxCacheSize,
      'hitCount': _hitCount,
      'missCount': _missCount,
      'workMicros': _workMicros,
      'worstWorkMicros': _worstWorkMicros,
      'hitRate': hitRate,
    };
  }

  static void _pruneOldest() {
    if (_cache.isEmpty) {
      return;
    }

    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    for (final entry in entries.take(_pruneBatchSize)) {
      _cache.remove(entry.key);
    }
  }
}

class _DocumentCacheKey {
  const _DocumentCacheKey({
    required this.deltaContent,
    required this.prioritizeBold,
    required this.truncateForCollapse,
    required this.layoutSignature,
  });

  final String deltaContent;
  final bool prioritizeBold;
  final bool truncateForCollapse;
  final String layoutSignature;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _DocumentCacheKey &&
        other.prioritizeBold == prioritizeBold &&
        other.truncateForCollapse == truncateForCollapse &&
        other.layoutSignature == layoutSignature &&
        other.deltaContent == deltaContent;
  }

  @override
  int get hashCode => Object.hash(
        deltaContent,
        prioritizeBold,
        truncateForCollapse,
        layoutSignature,
      );
}

class _DocumentCacheEntry {
  _DocumentCacheEntry({required this.document}) : lastAccess = DateTime.now();

  final quill.Document document;
  DateTime lastAccess;

  void touch() {
    lastAccess = DateTime.now();
  }
}

class _QuoteContentControllerCache {
  static final LinkedHashMap<_ControllerCacheKey, _ControllerCacheEntry>
      _cache = LinkedHashMap<_ControllerCacheKey, _ControllerCacheEntry>();

  static const int _maxCacheSize = 50;
  static const int _pruneBatchSize = 10;

  static int _hitCount = 0;
  static int _missCount = 0;
  static int _createCount = 0;
  static int _disposeCount = 0;
  static int _workMicros = 0;
  static int _worstWorkMicros = 0;

  static _CachedControllerSet getOrCreate({
    required String quoteId,
    required String contentSignature,
    required String variant,
    required quill.Document Function() documentBuilder,
  }) {
    final key = _ControllerCacheKey(
      quoteId: quoteId,
      contentSignature: contentSignature,
      variant: variant,
    );

    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      existing.touch();
      _cache[key] = existing;

      // contentSignature 已包含内容哈希+长度，key 匹配即内容一致，无需重建 Document
      existing.controllers.prepareForReuse();
      return existing.controllers;
    }

    _missCount++;
    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    final document = documentBuilder();
    final stopwatch = Stopwatch()..start();
    final controllers = _CachedControllerSet(
      quillController: quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      ),
      scrollController: ScrollController(),
      focusNode: FocusNode(),
      variant: variant,
    );
    stopwatch.stop();
    _workMicros += stopwatch.elapsedMicroseconds;
    if (stopwatch.elapsedMicroseconds > _worstWorkMicros) {
      _worstWorkMicros = stopwatch.elapsedMicroseconds;
    }

    final entry = _ControllerCacheEntry(controllers: controllers);
    _cache[key] = entry;
    _createCount++;
    return controllers;
  }

  static void clear() {
    for (final entry in _cache.values) {
      entry.controllers.dispose();
      _disposeCount++;
    }
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
    _createCount = 0;
    _disposeCount = 0;
    _workMicros = 0;
    _worstWorkMicros = 0;
  }

  static Map<String, dynamic> get stats {
    final total = _hitCount + _missCount;
    final double hitRate = total == 0 ? 0 : _hitCount / total;
    return {
      'cacheSize': _cache.length,
      'maxSize': _maxCacheSize,
      'hitCount': _hitCount,
      'missCount': _missCount,
      'createCount': _createCount,
      'disposeCount': _disposeCount,
      'workMicros': _workMicros,
      'worstWorkMicros': _worstWorkMicros,
      'hitRate': hitRate,
    };
  }

  static void _pruneOldest() {
    if (_cache.isEmpty) {
      return;
    }

    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    for (final entry in entries.take(_pruneBatchSize)) {
      _cache.remove(entry.key);
      entry.value.controllers.dispose();
      _disposeCount++;
    }
  }

  /// 修复问题1：清理特定笔记的所有缓存（用于笔记删除/更新）
  static void removeByQuoteId(String quoteId) {
    removeByQuoteIds({quoteId});
  }

  /// 批量清理特定笔记的所有缓存
  static void removeByQuoteIds(Set<String> quoteIds) {
    _cache.removeWhere((key, entry) {
      if (quoteIds.contains(key.quoteId)) {
        entry.controllers.dispose();
        _disposeCount++;
        return true;
      }
      return false;
    });
  }
}

class _ControllerCacheKey {
  const _ControllerCacheKey({
    required this.quoteId,
    required this.contentSignature,
    required this.variant,
  });

  final String quoteId;
  final String contentSignature;
  final String variant;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ControllerCacheKey &&
        other.quoteId == quoteId &&
        other.contentSignature == contentSignature &&
        other.variant == variant;
  }

  @override
  int get hashCode => Object.hash(quoteId, contentSignature, variant);
}

class _ControllerCacheEntry {
  _ControllerCacheEntry({required this.controllers})
      : lastAccess = DateTime.now();

  final _CachedControllerSet controllers;
  DateTime lastAccess;

  void touch() {
    lastAccess = DateTime.now();
  }
}

class _CachedControllerSet {
  _CachedControllerSet({
    required this.quillController,
    required this.scrollController,
    required this.focusNode,
    required this.variant,
  });

  final quill.QuillController quillController;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final String variant;

  void prepareForReuse() {
    focusNode.unfocus();
    if (scrollController.hasClients) {
      try {
        scrollController.jumpTo(0);
      } catch (_) {
        // 忽略跳转失败，可能由于尚未完成布局或控制器已分离
      }
    }

    final selection = quillController.selection;
    if (selection.baseOffset != 0 || selection.extentOffset != 0) {
      quillController.updateSelection(
        const TextSelection.collapsed(offset: 0),
        quill.ChangeSource.local,
      );
    }
  }

  void dispose() {
    try {
      quillController.dispose();
    } catch (e) {
      debugPrint('[_CachedControllerSet] quillController dispose error: $e');
    }
    try {
      scrollController.dispose();
    } catch (e) {
      debugPrint('[_CachedControllerSet] scrollController dispose error: $e');
    }
    try {
      focusNode.dispose();
    } catch (e) {
      debugPrint('[_CachedControllerSet] focusNode dispose error: $e');
    }
  }
}
