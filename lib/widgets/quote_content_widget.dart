import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import '../models/quote_model.dart';

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

  @override
  Widget build(BuildContext context) {
    // 如果有富文本内容且来源是全屏编辑器，尝试使用富文本渲染
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      try {
        // 解析富文本内容
        final document = quill.Document.fromJson(
          jsonDecode(quote.deltaContent!),
        );

        // 创建Controller
        final controller = quill.QuillController(
          document: document,
          selection: const TextSelection.collapsed(offset: 0),
        );

        // 使用与项目中其他部分相同的 API 方式
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                showFullContent
                    ? double.infinity
                    : (maxLines ?? 3) * 36.0, // 调整为36像素高度以匹配1.5行距
          ),
          child: ClipRect(
            // 使用ClipRect确保内容不会溢出
            child: Theme(
              data: Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.copyWith(
                  bodyMedium: (style ?? Theme.of(context).textTheme.bodyLarge)
                      ?.copyWith(
                        height: 1.5, // 设置和普通文本一样的行距
                      ),
                  bodyLarge: (style ?? Theme.of(context).textTheme.bodyLarge)
                      ?.copyWith(
                        height: 1.5, // 设置和普通文本一样的行距
                      ),
                ),
              ),
              child: quill.QuillEditor.basic(
                controller: controller,
                config: quill.QuillEditorConfig(
                  // 禁用编辑功能
                  autoFocus: false,
                  expands: false,
                  padding: EdgeInsets.zero,
                  scrollable: false,
                  enableInteractiveSelection: false,
                  placeholder: '',
                  // 设置自定义样式来匹配普通文本的行距
                  customStyles: quill.DefaultStyles(
                    paragraph: quill.DefaultTextBlockStyle(
                      (style ??
                              Theme.of(context).textTheme.bodyLarge ??
                              const TextStyle())
                          .copyWith(
                            height: 1.5, // 设置和普通文本一样的行距
                          ),
                      const quill.HorizontalSpacing(0, 0),
                      const quill.VerticalSpacing(0, 0),
                      const quill.VerticalSpacing(0, 0),
                      null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
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
    return Text(
      quote.content,
      style: style,
      maxLines: showFullContent ? null : maxLines,
      overflow: showFullContent ? TextOverflow.visible : TextOverflow.ellipsis,
    );
  }
}
