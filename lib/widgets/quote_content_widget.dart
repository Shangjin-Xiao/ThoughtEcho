import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import '../models/quote_model.dart';
import '../utils/quill_editor_extensions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

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

  /// 判断富文本内容是否需要折叠
  bool _needsExpansionForRichText(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
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
        // 超过3行或内容长度超过150字符时需要折叠
        return lineCount > 3 || totalLength > 150;
      }
    } catch (_) {
      // 富文本解析失败，回退到纯文本判断
      final int lineCount = 1 + '\n'.allMatches(quote.content).length;
      return lineCount > 3 || quote.content.length > 150;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 如果有富文本内容且来源是全屏编辑器，使用QuillEditor显示富文本
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      try {
        // 解析富文本内容
        final document = quill.Document.fromJson(
          jsonDecode(quote.deltaContent!),
        ); // 创建只读QuillController
        final controller = quill.QuillController(
          document: document,
          selection: const TextSelection.collapsed(offset: 0),
        );

        // 使用Container包装QuillEditor以控制高度和实现展开/折叠功能
        Widget richTextEditor = quill.QuillEditor(
          controller: controller,
          scrollController: ScrollController(),
          focusNode: FocusNode(),
          config: quill.QuillEditorConfig(
            // 禁用交互
            enableInteractiveSelection: false,
            enableSelectionToolbar: false,
            showCursor: false,
            // 添加扩展的嵌入构建器以支持图片、视频等
            embedBuilders: kIsWeb
                ? FlutterQuillEmbeds.editorWebBuilders()
                : QuillEditorExtensions.getEmbedBuilders(),
            // 内边距设置为0，让外层Container控制间距
            padding: EdgeInsets.zero,
            expands: false,
            scrollable: false,
          ),
        );

        // 只有当内容确实需要折叠且处于折叠状态时，才应用高度限制
        final bool needsExpansion =
            _needsExpansionForRichText(quote.deltaContent!);
        if (!showFullContent && maxLines != null && needsExpansion) {
          // 计算最大高度（每行大约24像素，根据实际字体大小调整）
          final estimatedLineHeight =
              (style?.height ?? 1.5) * (style?.fontSize ?? 14);
          final maxHeight = estimatedLineHeight * maxLines!;

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ClipRect(
              child: richTextEditor,
            ),
          );
        }

        // 展开状态，显示完整内容
        return richTextEditor;
      } catch (e) {
        // 富文本解析失败，回退到普通文本显示
        return Text(
          quote.content,
          style: style,
          maxLines: showFullContent ? null : maxLines,
          overflow:
              showFullContent ? TextOverflow.visible : TextOverflow.ellipsis,
        );
      }
    }

    // 使用普通文本显示
    // 判断普通文本是否需要折叠
    final int lineCount = 1 + '\n'.allMatches(quote.content).length;
    final bool needsExpansion = lineCount > 3 || quote.content.length > 150;

    return Text(
      quote.content,
      style: style,
      maxLines: showFullContent ? null : (needsExpansion ? maxLines : null),
      overflow: showFullContent
          ? TextOverflow.visible
          : (needsExpansion ? TextOverflow.ellipsis : TextOverflow.visible),
    );
  }
}
