import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import '../models/quote_model.dart';
import '../utils/quill_editor_extensions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';

/// 统一显示Quote内容的组件，支持富文本和普通文本
class QuoteContent extends StatelessWidget {
  final Quote quote;
  final TextStyle? style;
  final int? maxLines;
  final bool showFullContent;

  const QuoteContent({
    super.key,
    required this.quote,
    this.style,
    this.maxLines,
    this.showFullContent = false,
  });

  // 性能优化：提取为静态常量，避免每次 build 创建
  static final quill.QuillEditorConfig _staticEditorConfig = quill.QuillEditorConfig(
    enableInteractiveSelection: false,
    enableSelectionToolbar: false,
    showCursor: false,
    embedBuilders: kIsWeb
        ? FlutterQuillEmbeds.editorWebBuilders()
        : QuillEditorExtensions.getEmbedBuilders(),
    padding: EdgeInsets.zero,
    expands: false,
    scrollable: false,
  );

  static const double collapsedContentMaxHeight = 160.0;
  static const double _estimatedLineHeight = 24.0;
  static const double _lineSpacing = 4.0;
  static const int _averageCharsPerLine = 28;
  static const double _estimatedImageHeight = 200.0;
  static const double _estimatedVideoHeight = 240.0;
  static const double _estimatedAudioHeight = 140.0;
  static const Key collapsedWrapperKey =
      ValueKey('quote_content.collapsed_wrapper');

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
    return _estimateRenderedHeight(quote) > collapsedContentMaxHeight;
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

  /// 创建优先显示加粗内容的 Document（保持原始嵌入，重新排序）。
  quill.Document? _createBoldPriorityDocument(String deltaContent) {
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

      return quill.Document.fromJson(orderedOps);
    } catch (_) {
      return null;
    }
  }

  quill.Document _buildRichTextDocument(
    String deltaContent,
    bool prioritizeBold,
  ) {
    if (prioritizeBold) {
      final prioritizedDoc = _createBoldPriorityDocument(deltaContent);
      if (prioritizedDoc != null) {
        return prioritizedDoc;
      }
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
    final settingsService = Provider.of<SettingsService>(context);
    final prioritizeBoldContent =
        settingsService.prioritizeBoldContentInCollapse;
    final bool needsExpansion = exceedsCollapsedHeight(quote);

    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      final bool usePrioritizedDoc =
          !showFullContent && prioritizeBoldContent;
      final quill.Document document = _buildRichTextDocument(
        quote.deltaContent!,
        usePrioritizedDoc,
      );

      Widget richTextEditor = quill.QuillEditor(
        controller: quill.QuillController(
          document: document,
          selection: const TextSelection.collapsed(offset: 0),
        ),
        scrollController: ScrollController(),
        focusNode: FocusNode(),
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

      return richTextEditor;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final double resolvedMaxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;

        return ClipRect(
          child: SizedBox(
            height: maxHeight,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: resolvedMaxWidth,
              minHeight: 0,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
