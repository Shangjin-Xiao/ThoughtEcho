import 'dart:collection';

import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../utils/delta_media_extractor.dart';
import '../../utils/delta_rich_text_parser.dart';
import '../../utils/quill_editor_extensions.dart';
import 'collapsed_media_image.dart';

/// 折叠卡片的富文本正文，用 `Text.rich` 渲染 [RichTextBlock] 序列。
///
/// 这是「折叠卡片彻底不跑 `QuillEditor`」的落点：没有 Quill 就没有 20~48ms 的冷
/// 首布局，也就不需要滚动期间的占位、每帧额度和恢复队列——那一整套时序机制连同
/// 它造出来的「空白 → 灰框 → 图片」三段式一起消失了。
///
/// **布局工作量必须有上界**。折叠盒只有 160px，可是笔记正文可以有几千字，直接把
/// 整篇丢给 `Text.rich` 再靠 `ClipRect` 裁掉，等于每帧为看不见的像素做全文换行。
/// 所以每个块都带 `maxLines`，由 [CollapsedRichTextMetrics.plan] 按**剩余像素**
/// 算出来，排版量与正文长度无关。
///
/// 这一点也是旧实现最贵的地方消失的原因：原来的
/// `_truncateDeltaOpsForCollapsedDocument` 每加一个 op 就把已累积的全部 span 重新
/// `TextPainter.layout` 一次，单次最坏实测 14.5ms，而且发生在滚动帧内。
class CollapsedRichText extends StatelessWidget {
  const CollapsedRichText({
    super.key,
    required this.plan,
    required this.baseStyle,
    this.boldWeight = FontWeight.bold,
    this.onMediaTap,
  });

  /// 要画哪些块、每块最多几行，由 [CollapsedRichTextMetrics.plan] 算好。
  ///
  /// 排版计划和高度**出自同一次测量**：`build` 里量一次，盒子的高度和这里要画的
  /// 内容都从那一次结果来。分两次算的话，「量出来的高度」和「画出来的内容」会各
  /// 走各的——上一版就是这么让正文之后的图片仍然进了 widget 树：一个填满整屏的
  /// 长段落只从行数预算里扣掉 1 行，后面的媒体于是照样被建出来、照样解码。
  final CollapsedRichTextPlan plan;

  /// 正文基准样式。字号、行高、字重下限全由主题令牌下发，这里只做叠加，
  /// 不自己写死任何一项。
  final TextStyle baseStyle;

  /// 「粗体」实际用哪一档字重，见 [RichTextRun.styleOn]。必须和传给
  /// [CollapsedRichTextMetrics.plan] 的值一致，否则量出来的宽度和画出来的不一样。
  final FontWeight boldWeight;

  final ValueChanged<DeltaMediaRef>? onMediaTap;

  /// 块与块之间的垂直间距。
  ///
  /// 块级间距细节（quill 的 `VerticalSpacing`）明确不投入还原：折叠卡片只显示
  /// 5~6 行，逐类块调间距既看不出来，又会把行数预算算歪。统一取一个 4 的倍数。
  static const double blockGap = 4.0;

  /// 列表符号列的宽度与它到正文的间距。
  ///
  /// 序号可能是两位数（`12.`），列宽给够才不会挤。真挤不下时符号整体缩放，
  /// **绝不换行**：换行的符号会自己多占一行，把整个列表项的高度顶成两倍。
  static const double markerWidth = 24.0;
  static const double markerGap = 8.0;

  /// 引用左线宽度与线到正文的间距。
  static const double quoteBarWidth = 4.0;
  static const double quoteGap = 8.0;

  /// 正文里一个媒体块的高度。
  ///
  /// 定值而不是按原图比例：折叠盒本身定高，媒体高度跟着图片解码结果变会让卡片在
  /// 图片到达那一刻跳一下——正是这一轮要消除的「内容会动」。
  static const double inlineMediaHeight = 96.0;

  /// 是否在正文里画媒体。thumbnail / banner 版式把媒体摘出去单独画。
  bool get showMedia => plan.showMedia;

  /// 计划里的块序列，供测试和调试查看。
  List<RichTextBlock> get blocks =>
      plan.entries.map((entry) => entry.block).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (plan.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = CollapsedRichTextPalette.of(context);

    final children = <Widget>[
      for (final entry in plan.entries)
        if (entry.block.isMedia)
          _buildMedia(context, entry.block)
        else
          _CollapsedRichTextBlock(
            block: entry.block,
            baseStyle: baseStyle,
            palette: palette,
            maxLines: entry.maxLines,
            boldWeight: boldWeight,
          ),
    ];

    if (children.length == 1) {
      return children.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: blockGap),
          children[i],
        ],
      ],
    );
  }

  Widget _buildMedia(BuildContext context, RichTextBlock block) {
    final media = block.media!;
    final source = media.source;

    final l10n = AppLocalizations.of(context);

    Widget child;
    if (media.kind == DeltaMediaKind.image) {
      // 图片没有可用来源时画「加载失败」，**不能掉进音频分支**——否则一个畸形的
      // 图片节点会被读屏播报成「音频」，还配一个音符图标。
      child = source == null
          ? Semantics(
              label: l10n.imageLoadFailed,
              child: const CollapsedMediaPlaceholder(
                icon: Icons.broken_image_outlined,
              ),
            )
          : CollapsedMediaImage(source: source);
    } else {
      // 视频和音频在折叠态**只画一个占位**，不实例化 `MediaPlayerWidget`——
      // 在滚动列表里建播放器正是这一轮要去掉的开销。播放入口在展开态里。
      child = Semantics(
        label: media.kind == DeltaMediaKind.video ? l10n.video : l10n.audio,
        child: CollapsedMediaPlaceholder(
          icon: media.kind == DeltaMediaKind.video
              ? Icons.videocam_outlined
              : Icons.audiotrack_outlined,
        ),
      );
    }

    Widget box = SizedBox(height: inlineMediaHeight, child: child);
    final onTap = onMediaTap;
    if (onTap != null && media.kind == DeltaMediaKind.image && source != null) {
      box = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(media),
        child: box,
      );
    }
    return ClipRect(child: box);
  }

  /// 按版式过滤块序列：摘掉媒体的版式连同媒体块一起去掉，并丢弃尾部空块。
  ///
  /// 丢尾部空块是必须的：编辑器保存的 delta 结尾总有一个 `'\n'`，不丢的话折叠盒
  /// 底部永远挂着一行空段。
  static List<RichTextBlock> visibleBlocks(
    List<RichTextBlock> blocks, {
    required bool showMedia,
  }) {
    final filtered = showMedia
        ? blocks
        : blocks.where((block) => !block.isMedia).toList(growable: false);

    var end = filtered.length;
    while (end > 0 && filtered[end - 1].isBlank) {
      end--;
    }
    if (end == filtered.length) return filtered;
    return filtered.sublist(0, end);
  }

  /// 基准样式代表的单行高度。
  static double effectiveLineHeight(TextStyle style) {
    final fontSize = style.fontSize ?? 16.0;
    final height = style.height ?? 1.2;
    return fontSize * height;
  }
}

/// 一个块在折叠盒里的排版名额。
@immutable
class CollapsedPlannedBlock {
  const CollapsedPlannedBlock({required this.block, required this.maxLines});

  final RichTextBlock block;

  /// 这个块最多排几行。媒体块恒为 1，只是占位。
  final int maxLines;
}

/// 折叠盒的排版计划：画哪些块、每块几行、一共多高。
@immutable
class CollapsedRichTextPlan {
  const CollapsedRichTextPlan({
    required this.entries,
    required this.height,
    required this.showMedia,
  });

  static const CollapsedRichTextPlan empty = CollapsedRichTextPlan(
    entries: [],
    height: 0,
    showMedia: false,
  );

  final List<CollapsedPlannedBlock> entries;

  /// 这些块排下来的总高度，上限由 `plan` 的 limit 决定。
  final double height;

  final bool showMedia;

  bool get isEmpty => entries.isEmpty;
}

/// 折叠富文本用到的、来自主题的几种颜色。
///
/// 单独拎出来是为了让**测量和渲染共用同一套 span 构建代码**：测量只关心字号、
/// 字重、字体族和行高，颜色一项都不影响度量，所以测量侧可以拿一份占位调色板，
/// 不必持有 `BuildContext`。两边共用构建代码，量出来的高度才等于画出来的高度。
@immutable
class CollapsedRichTextPalette {
  const CollapsedRichTextPalette({
    required this.quoteBar,
    required this.quoteText,
    required this.codeBackground,
    required this.codeText,
    required this.marker,
  });

  /// 测量专用：颜色不影响度量，取值无所谓，但字段不能缺。
  static const CollapsedRichTextPalette measurement = CollapsedRichTextPalette(
    quoteBar: Color(0xFF000000),
    quoteText: Color(0xFF000000),
    codeBackground: Color(0xFF000000),
    codeText: Color(0xFF000000),
    marker: Color(0xFF000000),
  );

  /// 取值和 quill 的 `DefaultStyles` 有**刻意的差别**：那边的引用左线是
  /// `Colors.grey.shade300`、行内代码底是 `Colors.grey.shade100`、代码块字是
  /// `Colors.blue.shade900`，三个都是不随 M3 动态取色变化的固定浅色，暗色模式下
  /// 会变成刺眼白块或对比度不足。折叠卡片改用 surface 层级和 outline 令牌。
  ///
  /// 用户**自己标记的**字色、背景色仍然逐位还原（见 [RichTextRun.styleOn]），
  /// 这里换掉的只有 quill 自己的装饰色。
  factory CollapsedRichTextPalette.of(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CollapsedRichTextPalette(
      quoteBar: colorScheme.outlineVariant,
      quoteText: colorScheme.onSurfaceVariant,
      codeBackground: colorScheme.surfaceContainerHighest,
      codeText: colorScheme.onSurfaceVariant,
      marker: colorScheme.onSurfaceVariant,
    );
  }

  final Color quoteBar;
  final Color quoteText;
  final Color codeBackground;
  final Color codeText;
  final Color marker;
}

/// 一个块的排版结果：正文 span、块级样式、以及正文可用宽度被侵占了多少。
///
/// 测量和渲染都从这里取，两边不会漂。
@immutable
class CollapsedBlockLayout {
  const CollapsedBlockLayout({
    required this.span,
    required this.leadingInset,
    required this.marker,
    required this.minLineHeight,
  });

  final InlineSpan span;

  /// 列表符号列 / 引用左线占掉的宽度，正文可用宽度要减掉它。
  final double leadingInset;

  /// 列表符号的文字，没有符号时为 null（待办框另行绘制）。
  final String? marker;

  /// 本块可能出现的**最矮**一行有多高。
  ///
  /// 行数预算要按它换算，不能按正文基准行高：用户把一段文字标成 `small`（10px）
  /// 之后，那几行只有基准行高的一半多，按基准行高算预算会在盒子还没填满时就把
  /// 后面的内容丢掉——而且因为量出来的高度不到 160px，卡片连展开入口都不会有，
  /// 内容就这么静悄悄地少了一截。
  final double minLineHeight;
}

/// 把一个文字块翻成 `Text.rich` 能吃的 span 和块级样式。
///
/// 标题字号从 [QuillThemeTypography.headerFontSize] 取，和展开态的 `QuillEditor`
/// 共用同一组常量——两边各写一份字面量的话，改了一处就会在展开的那一刻看见标题
/// 跳一下。
CollapsedBlockLayout buildCollapsedBlockLayout({
  required RichTextBlock block,
  required TextStyle baseStyle,
  required CollapsedRichTextPalette palette,
  FontWeight boldWeight = FontWeight.bold,
}) {
  var blockStyle = baseStyle;
  var leadingInset = 0.0;
  String? marker;

  switch (block.kind) {
    case RichTextBlockKind.header:
      blockStyle = blockStyle.copyWith(
        fontSize: QuillThemeTypography.headerFontSize(block.headerLevel),
        fontWeight: boldWeight,
        height: 1.15,
      );
    case RichTextBlockKind.quote:
      blockStyle = blockStyle.copyWith(color: palette.quoteText);
      leadingInset =
          CollapsedRichText.quoteBarWidth + CollapsedRichText.quoteGap;
    case RichTextBlockKind.codeBlock:
      blockStyle = blockStyle.copyWith(
        color: palette.codeText,
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Courier'],
      );
    case RichTextBlockKind.bullet:
      marker = '•';
      leadingInset =
          CollapsedRichText.markerWidth + CollapsedRichText.markerGap;
    case RichTextBlockKind.ordered:
      marker = '${block.orderedIndex}.';
      leadingInset =
          CollapsedRichText.markerWidth + CollapsedRichText.markerGap;
    case RichTextBlockKind.checkbox:
      leadingInset =
          CollapsedRichText.markerWidth + CollapsedRichText.markerGap;
    case RichTextBlockKind.paragraph:
    case RichTextBlockKind.media:
      break;
  }

  final inlineCodeStyle = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Courier'],
    backgroundColor: palette.codeBackground,
  );

  // 空块也要给一个空 span：`Text.rich` 拿不到 children 时高度为 0，而空段落在
  // quill 里是占一行的，直接省掉会让折叠预览比展开态少一行。
  final children = <InlineSpan>[
    for (final run in block.runs)
      TextSpan(
        text: run.text,
        style: run.isPlain
            ? null
            : run.styleOn(
                blockStyle,
                inlineCodeStyle: inlineCodeStyle,
                boldWeight: boldWeight,
              ),
      ),
    if (block.runs.isEmpty) const TextSpan(text: ''),
  ];

  // 块内可能有 `small` 等更小的字号，取最小值算预算才不会少排。
  var minFontSize = blockStyle.fontSize ?? 16.0;
  for (final run in block.runs) {
    final runFontSize = run.fontSize;
    if (runFontSize != null && runFontSize > 0 && runFontSize < minFontSize) {
      minFontSize = runFontSize;
    }
  }
  final lineHeightFactor = blockStyle.height ?? 1.2;

  return CollapsedBlockLayout(
    span: TextSpan(style: blockStyle, children: children),
    leadingInset: leadingInset,
    marker: marker,
    minLineHeight: minFontSize * lineHeightFactor,
  );
}

/// 折叠富文本的度量与排版计划。
///
/// 用它取代了原来「28 个字符算一行」的静态估算：那个估算连中英文混排都算不准，
/// 更别提标题、列表和字号属性，导致一条实际超过 160px 的笔记被判成「不需要展开」，
/// 展开入口直接不出现。纯文本那条路本来就是 `TextPainter` 实测的，富文本只是因为
/// 拿不到 span 才退回估算——转换器补上这一块之后，两条路终于是同一个口径。
///
/// 工作量有界：每个块的 `TextPainter` 都带 `maxLines`，超过预算的行根本不排；
/// 预算按**实际用掉的行数**扣，累计高度越过 limit 立刻收工。长笔记既不会把全文
/// 排一遍，也不会在正文之后再挂上看不见的媒体。
class CollapsedRichTextMetrics {
  const CollapsedRichTextMetrics._();

  /// 量出折叠盒该画哪些块、每块几行、一共多高。
  ///
  /// 这是**唯一**一次测量：盒子的高度和要画的内容都从这一次的结果来，两者不会漂。
  ///
  /// 传 [cacheContent]（笔记的 `deltaContent`）即启用结果缓存。**强烈建议传**：
  /// 这个方法是在 `LayoutBuilder` 里调的，卡片每重建一次就要把每个可见块重新
  /// `TextPainter.layout` 一遍，而列表里有几十张卡片是永久 keepAlive 的——一次
  /// `setState` 就是几十次全量重量。结果只取决于参数，缓存不会让测量和渲染漂开。
  ///
  /// [cacheBoldPrioritized] 必须如实反映 [blocks] 是否已被 [prioritizeBoldBlocks]
  /// 重排过：同一份 delta 在开关两种状态下的计划不同，不进键就会串味。
  static CollapsedRichTextPlan plan({
    required List<RichTextBlock> blocks,
    required TextStyle baseStyle,
    required double maxWidth,
    required double limit,
    required bool showMedia,
    FontWeight boldWeight = FontWeight.bold,
    TextDirection textDirection = TextDirection.ltr,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
    String? cacheContent,
    bool cacheBoldPrioritized = false,
  }) {
    _CollapsedRichTextPlanCacheKey? cacheKey;
    // 宽度必须是有限的才建键：`double.infinity.round()` 会直接抛
    // `UnsupportedError`，那会赶在 [_computePlan] 自己的非有限宽度兜底之前炸掉。
    // 无界横向约束下直接走计算分支，由那条兜底返回空计划。
    if (cacheContent != null &&
        cacheContent.isNotEmpty &&
        maxWidth.isFinite &&
        limit.isFinite) {
      cacheKey = _CollapsedRichTextPlanCacheKey(
        fingerprint: DeltaContentFingerprint.of(cacheContent),
        boldPrioritized: cacheBoldPrioritized,
        showMedia: showMedia,
        // 宽度**按原值进键，不做量化**。同一张卡片在同一次布局里拿到的约束逐位
        // 相同，精确相等本来就命中；而量化成 0.01px 的桶会让两个相差不到 0.01px、
        // 却恰好跨过 `TextPainter` 换行阈值的宽度共用一份计划——那是按另一个宽度
        // 算出来的行数和盒高，内容会被多裁一行。省那点命中率不值得。
        maxWidth: maxWidth,
        limit: limit,
        styleHash: baseStyle.hashCode,
        boldWeightValue: boldWeight.value,
        textDirection: textDirection,
        textScalerHash: textScaler.hashCode,
        localeTag: locale?.toLanguageTag(),
      );
      final cached = CollapsedRichTextPlanCache._get(cacheKey);
      if (cached != null) {
        return cached;
      }
    }

    final stopwatch = cacheKey == null ? null : (Stopwatch()..start());
    final computed = _computePlan(
      blocks: blocks,
      baseStyle: baseStyle,
      maxWidth: maxWidth,
      limit: limit,
      showMedia: showMedia,
      boldWeight: boldWeight,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    );

    // 计划里排到了 `data:` 内嵌媒体就不进缓存：那个 source 是整段 base64，
    // 缓存住等于把若干 MB 长期钉在堆上。`DeltaMediaCache` 和 `DeltaRichTextCache`
    // 跳过这类笔记是同一个理由。
    //
    // 判据是**计划自己排到的块**，不是整篇 blocks：折叠盒只有 160px，正文长的
    // 笔记根本排不到后面那张内嵌图，那种计划不持有 base64，可以照常缓存。
    if (cacheKey != null) {
      stopwatch!.stop();
      // miss 和耗时**先记**，再决定要不要存。跳过存储的那些计划照样是真金白银
      // 算出来的；不记的话性能日志会漏掉它们，`planWorstUs` 恰好把最贵的一类
      // （带内嵌媒体的）系统性地漏没。
      CollapsedRichTextPlanCache._recordMiss(stopwatch.elapsedMicroseconds);
      if (!_holdsInlineDataMedia(computed)) {
        CollapsedRichTextPlanCache._put(cacheKey, computed);
      }
    }
    return computed;
  }

  static bool _holdsInlineDataMedia(CollapsedRichTextPlan plan) {
    for (final entry in plan.entries) {
      if (isInlineDataUri(entry.block.media?.source)) return true;
    }
    return false;
  }

  static CollapsedRichTextPlan _computePlan({
    required List<RichTextBlock> blocks,
    required TextStyle baseStyle,
    required double maxWidth,
    required double limit,
    required bool showMedia,
    required FontWeight boldWeight,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    final visible = CollapsedRichText.visibleBlocks(
      blocks,
      showMedia: showMedia,
    );
    if (visible.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
      return CollapsedRichTextPlan.empty;
    }

    final entries = <CollapsedPlannedBlock>[];
    var height = 0.0;

    for (final block in visible) {
      // 预算是**像素**，不是行数。按行数算就得挑一个行高当尺子，而块与块、
      // 甚至同一块里的不同 run 行高都可能不同（标题 34px、`small` 10px），
      // 挑哪个都会在另一头算错。
      final gap = entries.isEmpty ? 0.0 : CollapsedRichText.blockGap;
      final remainingHeight = limit - height - gap;
      // 第一个块无论多高都要画，否则纯标题笔记会得到一个空计划。
      if (remainingHeight <= 0 && entries.isNotEmpty) break;

      if (block.isMedia) {
        entries.add(CollapsedPlannedBlock(block: block, maxLines: 1));
        height += gap + CollapsedRichText.inlineMediaHeight;
        continue;
      }

      final layout = buildCollapsedBlockLayout(
        block: block,
        baseStyle: baseStyle,
        palette: CollapsedRichTextPalette.measurement,
        boldWeight: boldWeight,
      );
      final textWidth = maxWidth - layout.leadingInset;
      if (textWidth <= 0) {
        entries.add(CollapsedPlannedBlock(block: block, maxLines: 1));
        height += gap + layout.minLineHeight;
        continue;
      }

      // 用本块**最矮**的一行换算行数上限：宁可多排一两行（`ClipRect` 会裁掉），
      // 也不能少排——少排的内容是静悄悄消失的，没有任何提示。
      final maxLines = (remainingHeight <= 0
              ? 1
              : (remainingHeight / layout.minLineHeight).ceil() + 1)
          .clamp(1, _maxLinesPerBlock);

      final painter = TextPainter(
        text: layout.span,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        maxLines: maxLines,
      )..layout(maxWidth: textWidth);
      final blockHeight = painter.height;
      painter.dispose();

      entries.add(CollapsedPlannedBlock(block: block, maxLines: maxLines));
      height += gap + blockHeight;
    }

    return CollapsedRichTextPlan(
      entries: List<CollapsedPlannedBlock>.unmodifiable(entries),
      height: height,
      showMedia: showMedia,
    );
  }

  /// 单个块的排版行数硬上限。
  ///
  /// 折叠盒 160px 配最小的 `small`（10px × 1.2 ≈ 12px）也就十几行，这个值只是
  /// 防止畸形样式（比如 `size: "0.1"`）把预算算成天文数字。
  static const int _maxLinesPerBlock = 32;
}

/// [CollapsedRichTextMetrics.plan] 的 LRU 缓存。
///
/// 键**不持有 delta 字符串本身**，只存指纹——和 [DeltaMediaCache]、
/// [DeltaRichTextCache] 同一套理由：带 `data:` 内嵌媒体的笔记，一个 source 就是
/// 整段 base64。计划本身只有块引用和行数，不含像素数据，可以放心常驻。
class CollapsedRichTextPlanCache {
  CollapsedRichTextPlanCache._();

  static final LinkedHashMap<_CollapsedRichTextPlanCacheKey,
          CollapsedRichTextPlan> _cache =
      LinkedHashMap<_CollapsedRichTextPlanCacheKey, CollapsedRichTextPlan>();

  static const int _maxCacheSize = 300;
  static const int _pruneBatchSize = 50;

  static int _hitCount = 0;
  static int _missCount = 0;
  static int _workMicros = 0;
  static int _worstWorkMicros = 0;

  static CollapsedRichTextPlan? _get(_CollapsedRichTextPlanCacheKey key) {
    final existing = _cache.remove(key);
    if (existing == null) {
      return null;
    }
    _hitCount++;
    _cache[key] = existing;
    return existing;
  }

  static void _recordMiss(int workMicros) {
    _missCount++;
    _workMicros += workMicros;
    if (workMicros > _worstWorkMicros) {
      _worstWorkMicros = workMicros;
    }
  }

  static void _put(
    _CollapsedRichTextPlanCacheKey key,
    CollapsedRichTextPlan plan,
  ) {
    if (_cache.length >= _maxCacheSize) {
      final victims = _cache.keys.take(_pruneBatchSize).toList();
      for (final victim in victims) {
        _cache.remove(victim);
      }
    }
    _cache[key] = plan;
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
    return {
      'cacheSize': _cache.length,
      'maxSize': _maxCacheSize,
      'hitCount': _hitCount,
      'missCount': _missCount,
      'hitRate': total == 0 ? 0.0 : _hitCount / total,
      'workMicros': _workMicros,
      'worstWorkMicros': _worstWorkMicros,
    };
  }
}

@immutable
class _CollapsedRichTextPlanCacheKey {
  const _CollapsedRichTextPlanCacheKey({
    required this.fingerprint,
    required this.boldPrioritized,
    required this.showMedia,
    required this.maxWidth,
    required this.limit,
    required this.styleHash,
    required this.boldWeightValue,
    required this.textDirection,
    required this.textScalerHash,
    required this.localeTag,
  });

  final DeltaContentFingerprint fingerprint;
  final bool boldPrioritized;
  final bool showMedia;
  final double maxWidth;
  final double limit;
  final int styleHash;
  final int boldWeightValue;
  final TextDirection textDirection;
  final int textScalerHash;
  final String? localeTag;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _CollapsedRichTextPlanCacheKey &&
        other.fingerprint == fingerprint &&
        other.boldPrioritized == boldPrioritized &&
        other.showMedia == showMedia &&
        other.maxWidth == maxWidth &&
        other.limit == limit &&
        other.styleHash == styleHash &&
        other.boldWeightValue == boldWeightValue &&
        other.textDirection == textDirection &&
        other.textScalerHash == textScalerHash &&
        other.localeTag == localeTag;
  }

  @override
  int get hashCode => Object.hash(
        fingerprint,
        boldPrioritized,
        showMedia,
        maxWidth,
        limit,
        styleHash,
        boldWeightValue,
        textDirection,
        textScalerHash,
        localeTag,
      );
}

class _CollapsedRichTextBlock extends StatelessWidget {
  const _CollapsedRichTextBlock({
    required this.block,
    required this.baseStyle,
    required this.palette,
    required this.maxLines,
    required this.boldWeight,
  });

  final RichTextBlock block;
  final TextStyle baseStyle;
  final CollapsedRichTextPalette palette;
  final int maxLines;
  final FontWeight boldWeight;

  @override
  Widget build(BuildContext context) {
    final layout = buildCollapsedBlockLayout(
      block: block,
      baseStyle: baseStyle,
      palette: palette,
      boldWeight: boldWeight,
    );

    final Widget text = Text.rich(
      layout.span,
      maxLines: maxLines,
      overflow: TextOverflow.clip,
      softWrap: true,
    );

    switch (block.kind) {
      case RichTextBlockKind.quote:
        return Container(
          padding: const EdgeInsets.only(left: CollapsedRichText.quoteGap),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: CollapsedRichText.quoteBarWidth,
                color: palette.quoteBar,
              ),
            ),
          ),
          child: text,
        );

      case RichTextBlockKind.codeBlock:
        return ColoredBox(
          color: palette.codeBackground,
          child: text,
        );

      case RichTextBlockKind.bullet:
      case RichTextBlockKind.ordered:
      case RichTextBlockKind.checkbox:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: CollapsedRichText.markerWidth,
              child: _marker(context, layout.marker),
            ),
            const SizedBox(width: CollapsedRichText.markerGap),
            Expanded(child: text),
          ],
        );

      case RichTextBlockKind.paragraph:
      case RichTextBlockKind.header:
      case RichTextBlockKind.media:
        return text;
    }
  }

  Widget _marker(BuildContext context, String? marker) {
    if (block.kind == RichTextBlockKind.checkbox) {
      return Padding(
        // 方框比文字矮，垫一点才和首行文字对齐。
        padding: EdgeInsets.only(
          top: CollapsedRichText.effectiveLineHeight(baseStyle) * 0.2,
        ),
        child: Icon(
          block.checked ? Icons.check_box : Icons.check_box_outline_blank,
          size: (baseStyle.fontSize ?? 16) * 0.95,
          color: palette.marker,
        ),
      );
    }
    // FittedBox + softWrap:false：列宽放不下时缩小，而不是折行。折行的 `1.` 会让
    // 这一项高出一整行，列表看起来忽宽忽窄。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topRight,
      child: Text(
        marker ?? '',
        maxLines: 1,
        softWrap: false,
        style: baseStyle.copyWith(color: palette.marker),
      ),
    );
  }
}
