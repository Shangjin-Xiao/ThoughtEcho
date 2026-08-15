/// 折叠卡片富文本预览的中间表示（IR）。
///
/// 折叠卡片**不再跑 `QuillEditor`**：建一棵编辑器树要走 Document → Node →
/// RenderEditableTextLine 整条链路，冷首布局实测 20~48ms/张；而卡片只显示
/// 160px（5~6 行），这些成本一分钱都没花在能看见的像素上。这里改成把 Delta
/// 直接翻成 `Text.rich` 能吃的 `InlineSpan`——纯数据变换，O(ops)，无布局、无
/// RenderObject，比建整棵编辑器树便宜两个数量级。
///
/// **IR 刻意不含任何主题信息**（不含 `TextStyle`、不含 `Color` 之外的取值来源），
/// 属性只以「粗体 / 斜体 / 字号 token」这类**内容事实**的形式存在。这样缓存键就
/// 只是 delta 的内容指纹：换主题、换风格、换正文颜色都不需要让缓存失效，也不会
/// 像把 `TextStyle` 编进键那样在切主题时整表作废。样式在渲染时由
/// [RichTextRun.styleOn] 叠到调用方给的基准样式上。
///
/// 保真范围（与用户确认过）：粗体、斜体、下划线、删除线、字色、背景色、字号、
/// 行内代码、列表符号、引用左线、标题层级。**不投入**：块级间距细节
/// （`VerticalSpacing`）、多级嵌套列表缩进、表格、代码块内边距——折叠卡片只有
/// 5~6 行，这些本来就看不全。
library;

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'delta_media_extractor.dart';
import 'string_utils.dart';

/// 一个块（≈ 一个段落 / 一个列表项 / 一段引用 / 一个媒体嵌入）。
enum RichTextBlockKind {
  paragraph,
  header,
  bullet,
  ordered,
  checkbox,
  quote,
  codeBlock,
  media,
}

/// 一段样式连续的文字。
///
/// 字段全部是 delta 属性的直接映射，不掺任何主题取值：[colorArgb] /
/// [backgroundArgb] 来自用户在编辑器里选的颜色，[fontSize] 来自 quill 的 size
/// 属性（token 已在解析期解析成绝对值，口径与 `flutter_quill` 的
/// `DefaultStyles` 一致：small=10、large=18、huge=22）。
@immutable
class RichTextRun {
  const RichTextRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.inlineCode = false,
    this.colorArgb,
    this.backgroundArgb,
    this.fontSize,
    this.fontFamily,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool inlineCode;
  final int? colorArgb;
  final int? backgroundArgb;
  final double? fontSize;
  final String? fontFamily;

  bool get isPlain =>
      !bold &&
      !italic &&
      !underline &&
      !strikethrough &&
      !inlineCode &&
      colorArgb == null &&
      backgroundArgb == null &&
      fontSize == null &&
      fontFamily == null;

  /// 把本段的属性叠到 [base] 上。
  ///
  /// 下划线和删除线可以同时存在，所以 `decoration` 用 [TextDecoration.combine]
  /// 合并，而不是后者覆盖前者——这一点 `Text.rich` 和 quill 的行为一致。
  ///
  /// 斜体在这里是**忠实呈现用户手动标记的富文本格式**，不是 UI 自己的装饰选择，
  /// 属于项目里明确保留斜体的那一类（见 AGENTS.md 的例外说明）。
  /// [boldWeight] 是「粗体」实际用哪一档字重。Android + material 风格下 quill 会把
  /// 加粗降到 w500（`_buildCustomStyles` 里的可变字重补偿），折叠预览必须跟着降，
  /// 否则同一条笔记折叠时的粗体比展开后更重。
  TextStyle styleOn(
    TextStyle? base, {
    TextStyle? inlineCodeStyle,
    FontWeight boldWeight = FontWeight.bold,
  }) {
    var style = base ?? const TextStyle();
    if (inlineCode && inlineCodeStyle != null) {
      style = style.merge(inlineCodeStyle);
    }
    final decorations = <TextDecoration>[
      if (underline) TextDecoration.underline,
      if (strikethrough) TextDecoration.lineThrough,
    ];
    return style.copyWith(
      fontWeight: bold ? boldWeight : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration:
          decorations.isEmpty ? null : TextDecoration.combine(decorations),
      color: colorArgb == null ? null : Color(colorArgb!),
      backgroundColor: backgroundArgb == null ? null : Color(backgroundArgb!),
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RichTextRun &&
        other.text == text &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline &&
        other.strikethrough == strikethrough &&
        other.inlineCode == inlineCode &&
        other.colorArgb == colorArgb &&
        other.backgroundArgb == backgroundArgb &&
        other.fontSize == fontSize &&
        other.fontFamily == fontFamily;
  }

  @override
  int get hashCode => Object.hash(
        text,
        bold,
        italic,
        underline,
        strikethrough,
        inlineCode,
        colorArgb,
        backgroundArgb,
        fontSize,
        fontFamily,
      );

  @override
  String toString() => 'RichTextRun("$text")';
}

/// IR 的一个块。文字块带 [runs]，媒体块带 [media]。
@immutable
class RichTextBlock {
  const RichTextBlock({
    required this.kind,
    this.runs = const [],
    this.headerLevel = 0,
    this.orderedIndex = 0,
    this.checked = false,
    this.media,
  });

  final RichTextBlockKind kind;
  final List<RichTextRun> runs;

  /// 1~3，非标题为 0。折叠预览只认到 h3（quill 工具栏也只给到 h3）。
  final int headerLevel;

  /// 有序列表项的序号，1 起；其余为 0。
  final int orderedIndex;

  /// 待办列表项是否勾选。
  final bool checked;

  /// [RichTextBlockKind.media] 时的媒体来源，其余为 null。
  final DeltaMediaRef? media;

  bool get isMedia => kind == RichTextBlockKind.media;

  /// 本块的纯文字，用于测量和无障碍标签。
  String get plainText => runs.map((run) => run.text).join();

  bool get isBlank => !isMedia && plainText.trim().isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RichTextBlock &&
        other.kind == kind &&
        other.headerLevel == headerLevel &&
        other.orderedIndex == orderedIndex &&
        other.checked == checked &&
        other.media?.kind == media?.kind &&
        other.media?.source == media?.source &&
        listEquals(other.runs, runs);
  }

  @override
  int get hashCode => Object.hash(
        kind,
        headerLevel,
        orderedIndex,
        checked,
        media?.kind,
        media?.source,
        Object.hashAll(runs),
      );

  @override
  String toString() =>
      'RichTextBlock(${kind.name}, ${isMedia ? media?.source : '"$plainText"'})';
}

/// 把 delta JSON 解析成折叠预览用的块序列。**纯函数**，畸形输入返回空表。
///
/// 不做任何 IO，也不碰 `BuildContext`——它会被 `build` 直接调用。
List<RichTextBlock> parseDeltaRichText(String? deltaContent) {
  if (deltaContent == null || deltaContent.isEmpty) {
    return const [];
  }
  final ops = _decodeOps(deltaContent);
  if (ops == null || ops.isEmpty) {
    return const [];
  }

  final blocks = <RichTextBlock>[];
  var pendingRuns = <RichTextRun>[];
  var orderedIndex = 1;

  /// delta 的行属性挂在**换行符自己**身上，不在它前面的文字上。所以每遇到一个
  /// `\n` 才知道刚累积的这些 run 属于什么块——这是 Delta 格式的定义，不是这里
  /// 的取巧。
  void flushLine(Map<String, dynamic> lineAttributes) {
    final block = _blockFor(
      runs: pendingRuns,
      lineAttributes: lineAttributes,
      orderedIndex: orderedIndex,
    );
    orderedIndex =
        block.kind == RichTextBlockKind.ordered ? orderedIndex + 1 : 1;
    blocks.add(block);
    pendingRuns = <RichTextRun>[];
  }

  for (final op in ops) {
    if (op is! Map) continue;
    final insert = op['insert'];
    if (insert == null) continue;

    final media = readDeltaMediaEmbed(insert);
    if (media != null) {
      // 媒体前面攒着的文字先落成一段，媒体才好按原位插进序列里——
      // 「文字段, 媒体, 文字段…」的顺序就是 inline 版式的原位交错。
      if (pendingRuns.isNotEmpty) {
        flushLine(const {});
      }
      blocks.add(
        RichTextBlock(kind: RichTextBlockKind.media, media: media),
      );
      continue;
    }

    if (insert is! String) {
      // 非媒体嵌入（公式等）：折叠预览不投入渲染，跳过即可。
      continue;
    }

    final attributes = _asAttributeMap(op['attributes']);
    StringUtils.forEachLine(insert, (text, isLast) {
      if (text.isNotEmpty) {
        pendingRuns.add(_runFor(text, attributes));
      }
      // split 产生的最后一段后面没有换行符，留给下一个 op 继续累积。
      if (!isLast) {
        flushLine(attributes);
      }
    });
  }

  if (pendingRuns.isNotEmpty) {
    flushLine(const {});
  }

  return blocks;
}

/// 「折叠时加粗内容优先」设置下的块排序：带加粗的块提到前面，其余保持原序。
///
/// 没有加粗内容时内容原样返回。返回值一律不可修改——调用方拿到的是共享缓存里的
/// 块序列，能写就意味着一次误改会污染所有复用这份内容的卡片。
///
/// 和旧实现的差别：原来是在 **op** 粒度上把加粗片段拼到前面，一行里只加粗了半句
/// 时会把那半句单独拽出来，读起来是断的。这里改成 **块**（行）粒度——加粗所在的
/// 整行一起提前，句子保持完整。
List<RichTextBlock> prioritizeBoldBlocks(List<RichTextBlock> blocks) {
  final bold = <RichTextBlock>[];
  final rest = <RichTextBlock>[];

  for (final block in blocks) {
    if (block.isMedia) {
      rest.add(block);
      continue;
    }
    // 空行不参与排序：它们只是间距，提到前面会在预览顶部堆出一段空白。
    if (block.isBlank) {
      rest.add(block);
      continue;
    }
    if (block.runs.any((run) => run.bold)) {
      bold.add(block);
    } else {
      rest.add(block);
    }
  }

  if (bold.isEmpty) return List<RichTextBlock>.unmodifiable(blocks);
  return List<RichTextBlock>.unmodifiable([...bold, ...rest]);
}

RichTextBlock _blockFor({
  required List<RichTextRun> runs,
  required Map<String, dynamic> lineAttributes,
  required int orderedIndex,
}) {
  final frozen = List<RichTextRun>.unmodifiable(runs);

  final header = _asInt(lineAttributes['header']);
  if (header != null && header >= 1) {
    return RichTextBlock(
      kind: RichTextBlockKind.header,
      runs: frozen,
      headerLevel: header > 3 ? 3 : header,
    );
  }

  if (lineAttributes['blockquote'] == true) {
    return RichTextBlock(kind: RichTextBlockKind.quote, runs: frozen);
  }

  if (lineAttributes['code-block'] == true ||
      lineAttributes['code-block'] is String) {
    return RichTextBlock(kind: RichTextBlockKind.codeBlock, runs: frozen);
  }

  switch (lineAttributes['list']?.toString()) {
    case 'bullet':
      return RichTextBlock(kind: RichTextBlockKind.bullet, runs: frozen);
    case 'ordered':
      return RichTextBlock(
        kind: RichTextBlockKind.ordered,
        runs: frozen,
        orderedIndex: orderedIndex,
      );
    case 'checked':
      return RichTextBlock(
        kind: RichTextBlockKind.checkbox,
        runs: frozen,
        checked: true,
      );
    case 'unchecked':
      return RichTextBlock(kind: RichTextBlockKind.checkbox, runs: frozen);
  }

  return RichTextBlock(kind: RichTextBlockKind.paragraph, runs: frozen);
}

RichTextRun _runFor(String text, Map<String, dynamic> attributes) {
  if (attributes.isEmpty) {
    return RichTextRun(text: text);
  }
  return RichTextRun(
    text: text,
    bold: attributes['bold'] == true,
    italic: attributes['italic'] == true,
    underline: attributes['underline'] == true,
    strikethrough: attributes['strike'] == true,
    inlineCode: attributes['code'] == true,
    colorArgb: parseDeltaColor(attributes['color']),
    backgroundArgb: parseDeltaColor(attributes['background']),
    fontSize: _parseFontSize(attributes['size']),
    fontFamily: _parseFontFamily(attributes['font']),
  );
}

/// quill 的 size 属性：三个 token 或一个数字字符串。
///
/// token 的绝对值取 `flutter_quill` 的 `DefaultStyles` 默认值（small=10、
/// large=18、huge=22），这样折叠预览和展开态的 `QuillEditor` 字号一致——两边
/// 同屏出现在同一个列表里，差一号会很显眼。
double? _parseFontSize(Object? raw) {
  if (raw == null) return null;
  switch (raw.toString()) {
    case 'small':
      return 10.0;
    case 'large':
      return 18.0;
    case 'huge':
      return 22.0;
  }
  final parsed = double.tryParse(raw.toString());
  return (parsed != null && parsed > 0) ? parsed : null;
}

String? _parseFontFamily(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return raw;
}

/// 解析 delta 里的颜色字符串，解不出来时返回 null（表示不覆盖基准色）。
///
/// 本项目的编辑器只写 `#RRGGBB`（见 `editor_color_and_media.dart`），但导入和
/// 同步进来的笔记可能带其它写法，所以 `#RGB` / `#AARRGGBB` / `rgb()` / `rgba()`
/// 和 quill 支持的具名色一并认。
///
/// 和 quill 的 `stringToColor` 有一个**刻意的差别**：那边解不出来直接抛
/// `UnsupportedError`，这里返回 null。折叠预览是只读展示，一个坏颜色值不该让整
/// 张卡片炸掉，退回正文色是正确的降级。
int? parseDeltaColor(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  final named = _namedDeltaColors[value];
  if (named != null) return named;

  if (value.startsWith('#')) {
    return _parseHexColor(value.substring(1));
  }
  if (value.startsWith('rgba(') || value.startsWith('rgb(')) {
    return _parseRgbColor(value);
  }
  // 裸十六进制（部分导出工具会省掉 '#'）。
  return _parseHexColor(value);
}

int? _parseHexColor(String hex) {
  var value = hex;
  if (value.length == 3) {
    // #abc → #aabbcc
    value = value.split('').map((char) => '$char$char').join();
  }
  if (value.length == 6) {
    value = 'ff$value';
  }
  if (value.length != 8) return null;
  return int.tryParse(value, radix: 16);
}

int? _parseRgbColor(String value) {
  final start = value.indexOf('(');
  final end = value.lastIndexOf(')');
  if (start < 0 || end <= start) return null;
  final parts = value
      .substring(start + 1, end)
      .split(',')
      .map((part) => part.trim())
      .toList();
  if (parts.length < 3) return null;

  final red = int.tryParse(parts[0]);
  final green = int.tryParse(parts[1]);
  final blue = int.tryParse(parts[2]);
  if (red == null || green == null || blue == null) return null;

  var alpha = 255;
  if (parts.length >= 4) {
    final opacity = double.tryParse(parts[3]);
    if (opacity == null) return null;
    alpha = (opacity.clamp(0.0, 1.0) * 255).round();
  }
  if (red > 255 || green > 255 || blue > 255) return null;
  if (red < 0 || green < 0 || blue < 0) return null;

  return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

/// quill 认的具名色。
///
/// 取值必须和 `flutter_quill` 的 `stringToColor` 逐个对齐：同一条笔记折叠时走
/// 这里、展开时走 quill，颜色对不上就是肉眼可见的跳变。
///
/// 这里出现 `Colors.grey` 这类 Material 命名色是**还原用户在编辑器里选的颜色**，
/// 不是 UI 自己的配色选择——和 PDF 导出还原用户格式属于同一类例外，不适用
/// AGENTS.md 里「UI 不得使用 Material 命名色」的约束。
const Map<String, int> _namedDeltaColors = <String, int>{
  'transparent': 0x00000000,
  'black': 0xFF000000,
  'black12': 0x1F000000,
  'black26': 0x42000000,
  'black38': 0x61000000,
  'black45': 0x73000000,
  'black54': 0x8A000000,
  'black87': 0xDD000000,
  'white': 0xFFFFFFFF,
  'white10': 0x1AFFFFFF,
  'white12': 0x1FFFFFFF,
  'white24': 0x3DFFFFFF,
  'white30': 0x4DFFFFFF,
  'white38': 0x62FFFFFF,
  'white54': 0x8AFFFFFF,
  'white60': 0x99FFFFFF,
  'white70': 0xB3FFFFFF,
  'red': 0xFFF44336,
  'redAccent': 0xFFFF5252,
  'amber': 0xFFFFC107,
  'amberAccent': 0xFFFFD740,
  'yellow': 0xFFFFEB3B,
  'yellowAccent': 0xFFFFFF00,
  'teal': 0xFF009688,
  'tealAccent': 0xFF64FFDA,
  'purple': 0xFF9C27B0,
  'purpleAccent': 0xFFE040FB,
  'pink': 0xFFE91E63,
  'pinkAccent': 0xFFFF4081,
  'orange': 0xFFFF9800,
  'orangeAccent': 0xFFFFAB40,
  'deepOrange': 0xFFFF5722,
  'deepOrangeAccent': 0xFFFF6E40,
  'indigo': 0xFF3F51B5,
  'indigoAccent': 0xFF536DFE,
  'lime': 0xFFCDDC39,
  'limeAccent': 0xFFEEFF41,
  'grey': 0xFF9E9E9E,
  'blueGrey': 0xFF607D8B,
  'green': 0xFF4CAF50,
  'greenAccent': 0xFF69F0AE,
  'lightGreen': 0xFF8BC34A,
  'lightGreenAccent': 0xFFB2FF59,
  'blue': 0xFF2196F3,
  'blueAccent': 0xFF448AFF,
  'lightBlue': 0xFF03A9F4,
  'lightBlueAccent': 0xFF40C4FF,
  'cyan': 0xFF00BCD4,
  'cyanAccent': 0xFF18FFFF,
  'brown': 0xFF795548,
};

Map<String, dynamic> _asAttributeMap(Object? raw) {
  if (raw is! Map) return const {};
  return Map<String, dynamic>.from(raw);
}

int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

List<Object?>? _decodeOps(String deltaContent) {
  try {
    final decoded = jsonDecode(deltaContent);
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map && decoded['ops'] is List) {
      return decoded['ops'] as List<Object?>;
    }
  } catch (_) {
    // 畸形 delta 不该让卡片崩掉，交给上层按「没有富文本」处理。
  }
  return null;
}

/// [parseDeltaRichText] 的 LRU 缓存。
///
/// 折叠卡片每次 build 都要问一次块序列。IR 不含主题信息，所以键只是内容指纹——
/// 换主题、换风格、换正文颜色都不会让缓存失效。
class DeltaRichTextCache {
  DeltaRichTextCache._();

  static final LinkedHashMap<DeltaContentFingerprint, List<RichTextBlock>>
      _cache = LinkedHashMap<DeltaContentFingerprint, List<RichTextBlock>>();

  static const int _maxCacheSize = 200;
  static const int _pruneBatchSize = 40;

  static int _hitCount = 0;
  static int _missCount = 0;
  static int _workMicros = 0;
  static int _worstWorkMicros = 0;

  static List<RichTextBlock> of(String? deltaContent) {
    if (deltaContent == null || deltaContent.isEmpty) {
      return const [];
    }

    final key = DeltaContentFingerprint.of(deltaContent);
    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      _cache[key] = existing;
      return existing;
    }

    _missCount++;
    final stopwatch = Stopwatch()..start();
    final blocks = List<RichTextBlock>.unmodifiable(
      parseDeltaRichText(deltaContent),
    );
    stopwatch.stop();
    final micros = stopwatch.elapsedMicroseconds;
    _workMicros += micros;
    if (micros > _worstWorkMicros) {
      _worstWorkMicros = micros;
    }

    // 带 `data:` 内嵌媒体的笔记不进缓存：那种 source 就是整段 base64，200 条缓存
    // 全是这种笔记时能把若干十 MB 长期钉在堆上。这类笔记本来就少，重解一次远比
    // 常驻内存便宜。`DeltaMediaCache` 出于同样的理由也跳过它们。
    if (_holdsInlineDataMedia(blocks)) {
      return blocks;
    }

    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }
    _cache[key] = blocks;
    return blocks;
  }

  static bool _holdsInlineDataMedia(List<RichTextBlock> blocks) {
    for (final block in blocks) {
      if (isInlineDataUri(block.media?.source)) return true;
    }
    return false;
  }

  /// LinkedHashMap 的迭代顺序就是最近使用顺序，取前 N 个即最旧。
  static void _pruneOldest() {
    final victims = _cache.keys.take(_pruneBatchSize).toList();
    for (final key in victims) {
      _cache.remove(key);
    }
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
