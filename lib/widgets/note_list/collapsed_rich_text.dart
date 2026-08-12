import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../utils/delta_media_extractor.dart';
import '../../utils/delta_rich_text_parser.dart';
import 'collapsed_media_image.dart';

/// 折叠卡片的富文本正文，用 `Text.rich` 渲染 [RichTextBlock] 序列。
///
/// 这是「折叠卡片彻底不跑 `QuillEditor`」的落点：没有 Quill 就没有 20~48ms 的冷
/// 首布局，也就不需要滚动期间的占位、每帧额度和恢复队列——那一整套时序机制连同
/// 它造出来的「空白 → 灰框 → 图片」三段式一起消失了。
///
/// **布局工作量必须有上界**。折叠盒只有 160px，可是笔记正文可以有几千字，直接把
/// 整篇丢给 `Text.rich` 再靠 `ClipRect` 裁掉，等于每帧为看不见的像素做全文换行。
/// 所以每个块都带 [maxLines] 预算：预算从总行数出发，每落一个块至少扣 1 行（任何
/// 块都至少占一行），扣完即停。最坏情况的排版量是 N²/2 行（N≈7 时约 25 行），
/// 与正文长度无关。
///
/// 这一点也是旧实现最贵的地方消失的原因：原来的
/// `_truncateDeltaOpsForCollapsedDocument` 每加一个 op 就把已累积的全部 span 重新
/// `TextPainter.layout` 一次，单次最坏实测 14.5ms，而且发生在滚动帧内。
class CollapsedRichText extends StatelessWidget {
  const CollapsedRichText({
    super.key,
    required this.plan,
    required this.baseStyle,
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

    Widget child;
    if (media.kind == DeltaMediaKind.image && source != null) {
      child = CollapsedMediaImage(source: source);
    } else {
      // 视频和音频在折叠态**只画一个占位**，不实例化 `MediaPlayerWidget`——
      // 在滚动列表里建播放器正是这一轮要去掉的开销。播放入口在展开态里。
      final l10n = AppLocalizations.of(context);
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
  });

  final InlineSpan span;

  /// 列表符号列 / 引用左线占掉的宽度，正文可用宽度要减掉它。
  final double leadingInset;

  /// 列表符号的文字，没有符号时为 null（待办框另行绘制）。
  final String? marker;
}

/// 把一个文字块翻成 `Text.rich` 能吃的 span 和块级样式。
///
/// 标题字号取 `flutter_quill` 的 `DefaultStyles` 默认值（h1=34、h2=30、h3=24），
/// 不按主题正文字号缩放——quill 那边也是绝对值，跟着缩放反而会和展开态对不上。
CollapsedBlockLayout buildCollapsedBlockLayout({
  required RichTextBlock block,
  required TextStyle baseStyle,
  required CollapsedRichTextPalette palette,
}) {
  var blockStyle = baseStyle;
  var leadingInset = 0.0;
  String? marker;

  switch (block.kind) {
    case RichTextBlockKind.header:
      blockStyle = blockStyle.copyWith(
        fontSize: switch (block.headerLevel) {
          1 => 34.0,
          2 => 30.0,
          _ => 24.0,
        },
        fontWeight: FontWeight.bold,
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
            : run.styleOn(blockStyle, inlineCodeStyle: inlineCodeStyle),
      ),
    if (block.runs.isEmpty) const TextSpan(text: ''),
  ];

  return CollapsedBlockLayout(
    span: TextSpan(style: blockStyle, children: children),
    leadingInset: leadingInset,
    marker: marker,
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
  static CollapsedRichTextPlan plan({
    required List<RichTextBlock> blocks,
    required TextStyle baseStyle,
    required double maxWidth,
    required double limit,
    required bool showMedia,
    TextDirection textDirection = TextDirection.ltr,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
  }) {
    final visible = CollapsedRichText.visibleBlocks(
      blocks,
      showMedia: showMedia,
    );
    if (visible.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
      return CollapsedRichTextPlan.empty;
    }

    final lineHeight = CollapsedRichText.effectiveLineHeight(baseStyle);
    var remaining = lineHeight > 0 ? (limit / lineHeight).ceil() + 1 : 1;

    final entries = <CollapsedPlannedBlock>[];
    var height = 0.0;

    for (final block in visible) {
      if (remaining <= 0 || height > limit) break;

      final gap = entries.isEmpty ? 0.0 : CollapsedRichText.blockGap;

      if (block.isMedia) {
        entries.add(CollapsedPlannedBlock(block: block, maxLines: 1));
        height += gap + CollapsedRichText.inlineMediaHeight;
        // 媒体按它占的高度折算成行数扣预算，一张图后面不该还排满整屏文字。
        remaining -= (CollapsedRichText.inlineMediaHeight / lineHeight)
            .ceil()
            .clamp(1, 99);
        continue;
      }

      final layout = buildCollapsedBlockLayout(
        block: block,
        baseStyle: baseStyle,
        palette: CollapsedRichTextPalette.measurement,
      );
      final textWidth = maxWidth - layout.leadingInset;
      if (textWidth <= 0) {
        entries.add(CollapsedPlannedBlock(block: block, maxLines: 1));
        height += gap + lineHeight;
        remaining -= 1;
        continue;
      }

      final painter = TextPainter(
        text: layout.span,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        maxLines: remaining,
      )..layout(maxWidth: textWidth);
      final usedLines = painter.computeLineMetrics().length;
      final blockHeight = painter.height;
      painter.dispose();

      entries.add(
        CollapsedPlannedBlock(block: block, maxLines: remaining),
      );
      height += gap + blockHeight;
      // **按实际用掉的行数扣**，不是每块固定扣 1。一个填满整屏的长段落必须把预算
      // 一次吃光，否则它后面的块（尤其是媒体）会被当成还放得下而建出来。
      remaining -= usedLines < 1 ? 1 : usedLines;
    }

    return CollapsedRichTextPlan(
      entries: List<CollapsedPlannedBlock>.unmodifiable(entries),
      height: height,
      showMedia: showMedia,
    );
  }
}

class _CollapsedRichTextBlock extends StatelessWidget {
  const _CollapsedRichTextBlock({
    required this.block,
    required this.baseStyle,
    required this.palette,
    required this.maxLines,
  });

  final RichTextBlock block;
  final TextStyle baseStyle;
  final CollapsedRichTextPalette palette;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final layout = buildCollapsedBlockLayout(
      block: block,
      baseStyle: baseStyle,
      palette: palette,
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
