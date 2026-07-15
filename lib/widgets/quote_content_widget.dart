import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../models/quote_model.dart';
import '../utils/quill_editor_extensions.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';

part 'quote_content_deferred.dart';

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

  // Flutter 3.41+ Android (Impeller + 精准 wght 轴) 下 FontWeight.bold (w700)
  // 渲染明显偏粗。在 Android 上注入 customStyles 将 bold 降为 w600，
  // 标题按比例降档，使视觉接近升级前效果。
  static quill.DefaultStyles? _buildAndroidCustomStyles() {
    if (kIsWeb || !Platform.isAndroid) return null;
    return quill.DefaultStyles(
      bold: const TextStyle(fontWeight: FontWeight.w500),
      h1: quill.DefaultTextBlockStyle(
        const TextStyle(
          fontSize: 34,
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
        const TextStyle(
          fontSize: 30,
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
        const TextStyle(
          fontSize: 24,
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

  // 性能优化：静态缓存 config，避免每次 build 创建
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
    customStyles: _buildAndroidCustomStyles(),
  );

  static const double collapsedContentMaxHeight = 160.0;
  static const double _estimatedLineHeight = 24.0;
  static const double _lineSpacing = 4.0;
  static const int _averageCharsPerLine = 28;
  static const double _estimatedImageHeight = 200.0;
  static const double _estimatedVideoHeight = 240.0;
  static const double _estimatedAudioHeight = 140.0;
  // Keep a small guard below the clipped viewport so differences between the
  // conservative TextPainter estimate and Quill's block styles cannot expose
  // an empty strip at the bottom of the preview.
  static const double _collapsedDocumentHeightGuard = 96.0;
  static const double _collapsedImagePlaceholderHeight = 96.0;
  static const int _deferredPreviewCodeUnitBudget = 320;
  static const Key collapsedWrapperKey = ValueKey(
    'quote_content.collapsed_wrapper',
  );
  static int _cacheGeneration = 0;

  static void resetCaches() {
    _cacheGeneration++;
    _QuoteDocumentCache.clear();
    _QuoteHeightEstimateCache.clear();
    _QuotePlainTextLayoutExpansionCache.clear();
    _QuoteContentControllerCache.clear();
  }

  /// 预热 Document 缓存：只预热首屏附近内容，且滚动中不抢占主线程。
  static void prewarmDocumentCache(
    List<Quote> quotes, {
    int maxItems = 6,
    Duration delay = const Duration(milliseconds: 500),
  }) {
    final richQuotes = quotes
        .where((q) => q.deltaContent != null && q.editSource == 'fullscreen')
        .take(maxItems)
        .toList();
    if (richQuotes.isEmpty) return;

    const batchSize = 1;
    final generation = _cacheGeneration;
    void processBatch(int startIndex) {
      if (generation != _cacheGeneration) return;
      if (startIndex >= richQuotes.length) return;
      if (isListScrolling.value) {
        Timer(
          const Duration(milliseconds: 240),
          () => processBatch(startIndex),
        );
        return;
      }

      final end = (startIndex + batchSize).clamp(0, richQuotes.length);
      for (int i = startIndex; i < end; i++) {
        final deltaContent = richQuotes[i].deltaContent!;
        _QuoteDocumentCache.getOrCreate(
          deltaContent: deltaContent,
          prioritizeBold: false,
          truncateForCollapse: false,
          builder: () => _buildDocumentFromDelta(deltaContent),
        );
      }
      if (end < richQuotes.length) {
        Timer.run(() => processBatch(end));
      }
    }

    Timer(delay, () => processBatch(0));
  }

  /// 静态版本的 Document 构建，供预热缓存使用
  static quill.Document _buildDocumentFromDelta(String deltaContent) {
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
    } catch (e) {
      debugPrint('[QuoteContent] delta content parse failed: $e');
    }
    return quill.Document()..insert(0, '');
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

  /// Returns lightweight cache counters for performance diagnostics.
  static Map<String, dynamic> debugCacheStats() => {
        'document': _QuoteDocumentCache.stats,
        'heightEstimate': _QuoteHeightEstimateCache.stats,
        'controller': _QuoteContentControllerCache.stats,
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

    final buffer = StringBuffer()
      ..write('doc=${document['cacheSize']}')
      ..write('/${document['maxSize']}')
      ..write(',height=${height['cacheSize']}')
      ..write('/${height['maxSize']}')
      ..write(',ctrl=${controller['cacheSize']}')
      ..write('/${controller['maxSize']}')
      ..write(',ctrlCreate=${controller['createCount']}')
      ..write(',ctrlDispose=${controller['disposeCount']}');

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
        ..write(_debugIntDelta(controller, baselineController, 'disposeCount'));
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

  static String _deferredPreviewText(String content) {
    if (content.length <= _deferredPreviewCodeUnitBudget) {
      return content;
    }
    var end = _deferredPreviewCodeUnitBudget;
    final lastCodeUnit = content.codeUnitAt(end - 1);
    if (lastCodeUnit >= 0xD800 && lastCodeUnit <= 0xDBFF) {
      end--;
    }
    return content.substring(0, end);
  }

  /// 检查是否为媒体软连接或其他应该过滤的内容
  bool _shouldFilterBoldContent(String content) {
    // 去除空白字符进行检查
    final trimmed = content.trim();

    // 过滤空内容
    if (trimmed.isEmpty) return true;

    // 过滤只包含换行符的内容
    if (trimmed == '\n' || trimmed.replaceAll('\n', '').isEmpty) return true;

    // 过滤媒体软连接模式 (通常是特殊字符或占位符)
    if (trimmed.length == 1 && trimmed.codeUnitAt(0) > 127) return true;

    // 过滤包含媒体占位符的内容
    if (trimmed.contains('�') || trimmed.contains('\uFFFC')) return true;

    return false;
  }

  /// 提取有效的加粗文本内容，过滤媒体软连接
  List<Map<String, dynamic>> _extractValidBoldOps(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> validBoldOps = [];

        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];

            // 检查是否有加粗属性且内容有效
            if (attributes != null &&
                attributes['bold'] == true &&
                !_shouldFilterBoldContent(insert)) {
              validBoldOps.add(Map<String, dynamic>.from(op));
            }
          }
        }
        return validBoldOps;
      }
    } catch (_) {
      // 解析失败，返回空列表
    }
    return [];
  }

  /// 获取非加粗的正文内容（包括媒体嵌入）
  List<Map<String, dynamic>> _extractNonBoldOps(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> nonBoldOps = [];

        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            // 如果是嵌入内容（图片、视频等），直接保留
            if (op['insert'] is Map) {
              nonBoldOps.add(Map<String, dynamic>.from(op));
              continue;
            }

            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];

            // 非加粗内容或没有加粗属性的内容
            if (attributes == null || attributes['bold'] != true) {
              // 跳过空内容
              if (insert.trim().isNotEmpty) {
                nonBoldOps.add(Map<String, dynamic>.from(op));
              }
            }
          }
        }
        return nonBoldOps;
      }
    } catch (_) {
      // 解析失败，返回空列表
    }
    return [];
  }

  static bool exceedsCollapsedHeight(Quote quote) {
    return _QuoteHeightEstimateCache.getOrCreate(
          quote: quote,
          builder: () => _estimateRenderedHeight(quote),
        ) >
        collapsedContentMaxHeight;
  }

  /// Returns whether [quote] should be collapsed for the current layout.
  ///
  /// Plain text is measured with [TextPainter] using the actual [style],
  /// [maxWidth], [textDirection], [textScaler], and optional [locale]. Rich text
  /// and non-positive or infinite [maxWidth] values fall back to the lightweight
  /// estimation path used by [exceedsCollapsedHeight]. Callers should pass a
  /// finite content width from layout constraints when available.
  static bool exceedsCollapsedHeightForLayout({
    required Quote quote,
    required TextStyle? style,
    required double maxWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
    Locale? locale,
  }) {
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      return exceedsCollapsedHeight(quote);
    }
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return exceedsCollapsedHeight(quote);
    }

    return _QuotePlainTextLayoutExpansionCache.getOrCreate(
      quote: quote,
      style: style,
      maxWidth: maxWidth,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      builder: () {
        final painter = TextPainter(
          text: TextSpan(text: quote.content, style: style),
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        )..layout(maxWidth: maxWidth);
        return painter.height > collapsedContentMaxHeight + 0.5;
      },
    );
  }

  static double _estimateRenderedHeight(Quote quote) {
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      return _estimateDeltaHeight(quote.deltaContent!);
    }
    return _estimatePlainTextHeight(quote.content);
  }

  static double _estimatePlainTextHeight(String content) {
    if (content.trim().isEmpty) {
      return _estimatedLineHeight;
    }

    final lines = content.split('\n');
    double height = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        height += _estimatedLineHeight * 0.5;
        continue;
      }

      int approxLines = line.length ~/ _averageCharsPerLine;
      if (line.length % _averageCharsPerLine != 0) {
        approxLines += 1;
      }
      if (approxLines < 1) {
        approxLines = 1;
      }

      height += approxLines * _estimatedLineHeight;
    }

    if (lines.length > 1) {
      height += (lines.length - 1) * _lineSpacing;
    }

    return height;
  }

  static double _estimateDeltaHeight(String deltaContent) {
    double height = 0;

    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        for (final node in decoded) {
          if (node is! Map || !node.containsKey('insert')) continue;
          final insert = node['insert'];

          if (insert is Map) {
            if (insert.containsKey('image')) {
              height += _estimatedImageHeight;
            } else if (insert.containsKey('video')) {
              height += _estimatedVideoHeight;
            } else if (insert.containsKey('audio')) {
              height += _estimatedAudioHeight;
            } else {
              height += _estimatedLineHeight;
            }
            continue;
          }

          if (insert != null) {
            height += _estimatePlainTextHeight(insert.toString());
          }
        }
      } else if (decoded is Map && decoded.containsKey('ops')) {
        // 某些备份格式可能包含 ops 包裹
        return _estimateDeltaHeight(jsonEncode(decoded['ops']));
      } else {
        height += _estimatePlainTextHeight(deltaContent);
      }
    } catch (_) {
      height += _estimatePlainTextHeight(deltaContent);
    }

    return height;
  }

  List<Map<String, dynamic>>? _createBoldPriorityOps(String deltaContent) {
    try {
      final boldOps = _extractValidBoldOps(deltaContent);
      if (boldOps.isEmpty) {
        return null;
      }

      final nonBoldOps = _extractNonBoldOps(deltaContent);
      final List<Map<String, dynamic>> orderedOps = [];

      orderedOps.addAll(boldOps);

      if (nonBoldOps.isNotEmpty) {
        if (orderedOps.isNotEmpty &&
            !(orderedOps.last['insert']?.toString() ?? '').endsWith('\n')) {
          orderedOps.add({'insert': '\n'});
        }
        orderedOps.add({'insert': '\n'});
        orderedOps.addAll(nonBoldOps);
      }

      if (orderedOps.isNotEmpty) {
        final last = orderedOps.last;
        if (last['insert'] is String &&
            !last['insert'].toString().endsWith('\n')) {
          orderedOps.add({'insert': '\n'});
        }
      }

      return orderedOps;
    } catch (_) {
      return null;
    }
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

  static List<Map<String, dynamic>> _truncateDeltaOpsForCollapsedDocument(
    List<Map<String, dynamic>> ops, {
    double? maxWidth,
    TextStyle? textStyle,
    TextDirection? textDirection,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
  }) {
    if (ops.isEmpty) {
      return const [
        {'insert': '\n'},
      ];
    }

    if (maxWidth == null || !maxWidth.isFinite || maxWidth <= 0) {
      return _truncateDeltaOpsWithLegacyBudget(ops);
    }

    final truncatedOps = <Map<String, dynamic>>[];
    final targetHeight =
        collapsedContentMaxHeight + _collapsedDocumentHeightGuard;

    for (final op in ops) {
      if (!op.containsKey('insert')) continue;

      final insert = op['insert'];
      final candidate = Map<String, dynamic>.from(op);
      final candidateOps = [...truncatedOps, candidate];
      final candidateHeight = _estimateCollapsedPrefixHeight(
        candidateOps,
        maxWidth: maxWidth,
        textStyle: textStyle,
        textDirection: textDirection ?? TextDirection.ltr,
        textScaler: textScaler,
        locale: locale,
      );
      if (candidateHeight <= targetHeight) {
        truncatedOps.add(candidate);
        continue;
      }

      if (insert is String) {
        final textPrefix = _longestVisibleTextPrefix(
          existingOps: truncatedOps,
          op: candidate,
          text: insert,
          targetHeight: targetHeight,
          maxWidth: maxWidth,
          textStyle: textStyle,
          textDirection: textDirection ?? TextDirection.ltr,
          textScaler: textScaler,
          locale: locale,
        );
        if (textPrefix.isNotEmpty) {
          final truncatedOp = Map<String, dynamic>.from(candidate);
          truncatedOp['insert'] = textPrefix;
          truncatedOps.add(truncatedOp);
        }
      } else if (truncatedOps.isEmpty ||
          _estimateCollapsedPrefixHeight(
                truncatedOps,
                maxWidth: maxWidth,
                textStyle: textStyle,
                textDirection: textDirection ?? TextDirection.ltr,
                textScaler: textScaler,
                locale: locale,
              ) <
              targetHeight) {
        // Preserve the first embed/block crossing the preview boundary. Quill
        // remains the renderer for every pixel that can become visible.
        truncatedOps.add(candidate);
      }
      break;
    }

    if (truncatedOps.isEmpty) {
      truncatedOps.add(Map<String, dynamic>.from(ops.first));
    }

    _ensureDocumentOpsEndWithNewline(truncatedOps);
    return truncatedOps;
  }

  static List<Map<String, dynamic>> _truncateDeltaOpsWithLegacyBudget(
    List<Map<String, dynamic>> ops,
  ) {
    final truncatedOps = <Map<String, dynamic>>[];
    var usedHeight = 0.0;
    final budget = collapsedContentMaxHeight * 4;

    for (final op in ops) {
      if (!op.containsKey('insert')) continue;
      final insert = op['insert'];
      final opHeight = _estimateDeltaOpHeight(insert);
      if (usedHeight + opHeight <= budget) {
        truncatedOps.add(Map<String, dynamic>.from(op));
        usedHeight += opHeight;
        continue;
      }
      if (insert is String && usedHeight < budget) {
        final prefix = _truncateTextForEstimatedHeight(
          insert,
          budget - usedHeight,
        );
        if (prefix.isNotEmpty) {
          truncatedOps.add({...op, 'insert': prefix});
        }
      }
      break;
    }

    if (truncatedOps.isEmpty) {
      truncatedOps.add(Map<String, dynamic>.from(ops.first));
    }
    _ensureDocumentOpsEndWithNewline(truncatedOps);
    return truncatedOps;
  }

  static double _estimateCollapsedPrefixHeight(
    List<Map<String, dynamic>> ops, {
    required double maxWidth,
    required TextStyle? textStyle,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    var height = 0.0;
    final textSpans = <InlineSpan>[];

    void flushText() {
      if (textSpans.isEmpty) return;
      final painter = TextPainter(
        text: TextSpan(style: textStyle, children: [...textSpans]),
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      )..layout(maxWidth: maxWidth);
      height += painter.height;
      textSpans.clear();
    }

    for (final op in ops) {
      final insert = op['insert'];
      if (insert is String) {
        textSpans.add(
          TextSpan(
            text: insert,
            style: _measurementStyleForAttributes(op['attributes']),
          ),
        );
        continue;
      }

      flushText();
      if (insert is Map) {
        if (insert.containsKey('image')) {
          height += _collapsedImagePlaceholderHeight;
        } else if (insert.containsKey('video')) {
          height += _estimatedVideoHeight;
        } else if (insert.containsKey('audio')) {
          height += _estimatedAudioHeight;
        } else {
          height += _estimatedLineHeight;
        }
      }
    }
    flushText();
    return height;
  }

  static TextStyle? _measurementStyleForAttributes(dynamic rawAttributes) {
    if (rawAttributes is! Map) return null;

    final attributes = Map<String, dynamic>.from(rawAttributes);
    TextStyle style = const TextStyle();
    final fontSize = switch (attributes['size']) {
      'small' => 10.0,
      'large' => 18.0,
      'huge' => 22.0,
      _ => null,
    };
    if (fontSize != null) {
      style = style.copyWith(fontSize: fontSize);
    }
    if (attributes['bold'] == true) {
      style = style.copyWith(fontWeight: FontWeight.bold);
    }
    if (attributes['italic'] == true) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    final fontFamily = attributes['font'];
    if (fontFamily is String && fontFamily.isNotEmpty) {
      style = style.copyWith(fontFamily: fontFamily);
    }
    return style;
  }

  static String _longestVisibleTextPrefix({
    required List<Map<String, dynamic>> existingOps,
    required Map<String, dynamic> op,
    required String text,
    required double targetHeight,
    required double maxWidth,
    required TextStyle? textStyle,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    final codePoints = text.runes.toList(growable: false);
    var low = 0;
    var high = codePoints.length;

    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      final candidate = Map<String, dynamic>.from(op)
        ..['insert'] = String.fromCharCodes(codePoints.take(mid));
      final height = _estimateCollapsedPrefixHeight(
        [...existingOps, candidate],
        maxWidth: maxWidth,
        textStyle: textStyle,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      );
      if (height <= targetHeight) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    return String.fromCharCodes(codePoints.take(low));
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

  static double _estimateDeltaOpHeight(dynamic insert) {
    if (insert is Map) {
      if (insert.containsKey('image')) {
        return _estimatedImageHeight;
      }
      if (insert.containsKey('video')) {
        return _estimatedVideoHeight;
      }
      if (insert.containsKey('audio')) {
        return _estimatedAudioHeight;
      }
      return _estimatedLineHeight;
    }
    if (insert == null) {
      return 0;
    }
    return _estimatePlainTextHeight(insert.toString());
  }

  static String _truncateTextForEstimatedHeight(
    String text,
    double remainingHeight,
  ) {
    if (text.isEmpty || remainingHeight <= 0) {
      return '';
    }

    final approxLines = (remainingHeight / _estimatedLineHeight).floor();
    final charLimit =
        (approxLines.clamp(1, 12) * _averageCharsPerLine).clamp(1, text.length);
    return String.fromCharCodes(text.runes.take(charLimit));
  }

  quill.Document _buildRichTextDocument(
    String deltaContent,
    bool prioritizeBold,
    bool truncateForCollapse, {
    double? maxWidth,
    TextStyle? textStyle,
    TextDirection? textDirection,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
  }) {
    List<Map<String, dynamic>>? ops;
    if (prioritizeBold) {
      ops = _createBoldPriorityOps(deltaContent);
    }

    ops ??= _decodeDeltaOps(deltaContent);
    if (ops != null) {
      final documentOps = truncateForCollapse
          ? _truncateDeltaOpsForCollapsedDocument(
              ops,
              maxWidth: maxWidth,
              textStyle: textStyle,
              textDirection: textDirection,
              textScaler: textScaler,
              locale: locale,
            )
          : _normalizedDocumentOps(ops);
      return quill.Document.fromJson(documentOps);
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

  @override
  Widget build(BuildContext context) {
    final prioritizeBoldContent = context.select<SettingsService, bool>(
      (s) => s.prioritizeBoldContentInCollapse,
    );
    final bool needsExpansion =
        needsExpansionOverride ?? exceedsCollapsedHeight(quote);

    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      if (!showFullContent && needsExpansion) {
        return LayoutBuilder(
          builder: (context, constraints) => _buildRichTextContent(
            context,
            needsExpansion: needsExpansion,
            prioritizeBoldContent: prioritizeBoldContent,
            maxWidth: constraints.maxWidth,
          ),
        );
      }
      return _buildRichTextContent(
        context,
        needsExpansion: needsExpansion,
        prioritizeBoldContent: prioritizeBoldContent,
      );
    }

    Widget plainText = Text(
      quote.content,
      style: style,
      softWrap: true,
      overflow: TextOverflow.visible,
    );

    if (!showFullContent && needsExpansion) {
      plainText = _CollapsedContentWrapper(
        key: collapsedWrapperKey,
        maxHeight: collapsedContentMaxHeight,
        child: plainText,
      );
    }

    return plainText;
  }

  Widget _buildRichTextContent(
    BuildContext context, {
    required bool needsExpansion,
    required bool prioritizeBoldContent,
    double? maxWidth,
  }) {
    final bool usePrioritizedDoc = !showFullContent && prioritizeBoldContent;
    final bool truncateForCollapse = !showFullContent && needsExpansion;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final measuredMaxWidth =
        maxWidth != null && maxWidth.isFinite && maxWidth > 0 ? maxWidth : null;
    final layoutSignature = truncateForCollapse && measuredMaxWidth != null
        ? 'w${(measuredMaxWidth * 100).round()}_s${style.hashCode}_'
            'd${textDirection.name}_t${textScaler.hashCode}_'
            'l${locale?.toLanguageTag()}'
        : 'full';
    final String cacheQuoteId =
        quote.id ?? 'local_${quote.date}_${quote.content.hashCode}';
    final baseVariant = _QuoteContentControllerCache.resolveVariant(
      showFullContent: showFullContent,
      usePrioritizedDoc: usePrioritizedDoc,
      needsExpansion: needsExpansion,
    );
    final contentVariant = '${baseVariant}_$layoutSignature';
    final String contentSignature =
        '${quote.deltaContent!.hashCode}_${quote.deltaContent!.length}_$contentVariant';

    // Only fixed-height collapsed cards can use a lightweight stand-in
    // without changing the list extent. Cache hits keep their real Quill tree.
    if (truncateForCollapse &&
        isListScrolling.value &&
        !_QuoteContentControllerCache.contains(
          quoteId: cacheQuoteId,
          contentSignature: contentSignature,
          variant: contentVariant,
        )) {
      Widget placeholder = _CollapsedContentWrapper(
        key: collapsedWrapperKey,
        maxHeight: collapsedContentMaxHeight,
        child: Text(
          _deferredPreviewText(quote.content),
          style: style,
          softWrap: true,
          maxLines: 8,
          overflow: TextOverflow.clip,
        ),
      );
      if (collapseRichTextSemantics) {
        placeholder = Semantics(
          key: const ValueKey('quote_content.rich_text_semantics'),
          container: true,
          label: quote.content,
          child: ExcludeSemantics(child: placeholder),
        );
      }
      return _DeferredRichTextContent(
        placeholder: placeholder,
        richTextBuilder: (context) => _buildRichTextContent(
          context,
          needsExpansion: needsExpansion,
          prioritizeBoldContent: prioritizeBoldContent,
          maxWidth: maxWidth,
        ),
      );
    }

    final _CachedControllerSet controllerSet =
        _QuoteContentControllerCache.getOrCreate(
      quoteId: cacheQuoteId,
      contentSignature: contentSignature,
      variant: contentVariant,
      documentBuilder: () => _QuoteDocumentCache.getOrCreate(
        deltaContent: quote.deltaContent!,
        prioritizeBold: usePrioritizedDoc,
        truncateForCollapse: truncateForCollapse,
        layoutSignature: layoutSignature,
        builder: () => _buildRichTextDocument(
          quote.deltaContent!,
          usePrioritizedDoc,
          truncateForCollapse,
          maxWidth: measuredMaxWidth,
          textStyle: style,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        ),
      ),
    );

    Widget richTextEditor = quill.QuillEditor(
      controller: controllerSet.quillController,
      scrollController: controllerSet.scrollController,
      focusNode: controllerSet.focusNode,
      config: _staticEditorConfig,
    );

    if (style != null) {
      richTextEditor = DefaultTextStyle.merge(
        style: style!,
        child: richTextEditor,
      );
    }

    if (!showFullContent && needsExpansion) {
      richTextEditor = _CollapsedContentWrapper(
        key: collapsedWrapperKey,
        maxHeight: collapsedContentMaxHeight,
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
  });

  factory _HeightEstimateCacheKey.fromQuote(Quote quote) {
    final richContent =
        quote.deltaContent != null && quote.editSource == 'fullscreen';
    final content = richContent ? quote.deltaContent! : quote.content;
    return _HeightEstimateCacheKey(
      contentSignature: Object.hash(content.hashCode, content.length),
      isRichText: richContent,
    );
  }

  final int contentSignature;
  final bool isRichText;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _HeightEstimateCacheKey &&
        other.contentSignature == contentSignature &&
        other.isRichText == isRichText;
  }

  @override
  int get hashCode => Object.hash(contentSignature, isRichText);
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

  static bool getOrCreate({
    required Quote quote,
    required TextStyle? style,
    required double maxWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
    required bool Function() builder,
  }) {
    final key = _PlainTextLayoutExpansionCacheKey(
      contentSignature:
          Object.hash(quote.content.hashCode, quote.content.length),
      maxWidthKey: (maxWidth * 100).round(),
      styleHash: style.hashCode,
      textDirection: textDirection,
      textScalerHash: textScaler.hashCode,
      localeTag: locale?.toLanguageTag(),
    );
    final existing = _cache.remove(key);
    if (existing != null) {
      existing.touch();
      _cache[key] = existing;
      return existing.exceedsCollapsedHeight;
    }

    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    final exceedsCollapsedHeight = builder();
    _cache[key] = _PlainTextLayoutExpansionCacheEntry(
      exceedsCollapsedHeight: exceedsCollapsedHeight,
    );
    return exceedsCollapsedHeight;
  }

  static void clear() {
    _cache.clear();
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

  static bool contains({
    required String quoteId,
    required String contentSignature,
    required String variant,
  }) {
    return _cache.containsKey(
      _ControllerCacheKey(
        quoteId: quoteId,
        contentSignature: contentSignature,
        variant: variant,
      ),
    );
  }

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

  static String resolveVariant({
    required bool showFullContent,
    required bool usePrioritizedDoc,
    required bool needsExpansion,
  }) {
    final buffer = StringBuffer()
      ..write(showFullContent ? 'full' : 'collapsed')
      ..write(usePrioritizedDoc ? '_bold' : '_plain')
      ..write(needsExpansion ? '_expandable' : '_static');
    return buffer.toString();
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
