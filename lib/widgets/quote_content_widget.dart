import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import 'dart:ui' as ui;
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

  /// 提取加粗文本内容，用于优先显示
  List<String> _extractBoldText(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<String> boldTexts = [];
        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];

            // 检查是否有加粗属性
            if (attributes != null && attributes['bold'] == true) {
              boldTexts.add(insert);
            }
          }
        }
        return boldTexts;
      }
    } catch (_) {
      // 解析失败，返回空列表
    }
    return [];
  }

  /// 创建仅显示加粗内容的Document（用户需求：只显示加粗，其余折叠）
  quill.Document _createBoldOnlyDocument(String deltaContent, int maxLines) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> boldOps = [];

        // 提取所有加粗内容
        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            final Map<String, dynamic>? attributes = op['attributes'];

            // 只保留加粗文本
            if (attributes != null && attributes['bold'] == true) {
              boldOps.add(Map<String, dynamic>.from(op));
            }
          }
        }

        // 如果有加粗内容，显示所有加粗内容（与普通折叠保持一致的限制）
        if (boldOps.isNotEmpty) {
          List<Map<String, dynamic>> finalOps = [];
          String allBoldText = '';

          // 收集所有加粗文本，保持原始换行
          for (var op in boldOps) {
            String insert = op['insert'].toString();
            allBoldText += insert;
          }

          // 按行分割并限制行数，与普通折叠保持一致
          final lines = allBoldText.split('\n');
          List<String> limitedLines = [];

          for (int i = 0; i < lines.length && i < maxLines; i++) {
            limitedLines.add(lines[i]);
          }

          // 如果超过了行数限制，添加省略号
          if (lines.length > maxLines) {
            if (limitedLines.isNotEmpty) {
              limitedLines[limitedLines.length - 1] += '...';
            } else {
              limitedLines.add('...');
            }
          }

          // 重新构建操作列表
          String finalText = limitedLines.join('\n');
          if (finalText.isEmpty) {
            try {
              return quill.Document.fromJson(jsonDecode(deltaContent));
            } catch (_) {
              return quill.Document()..insert(0, quote.content);
            }
          }

          finalOps.add({
            'insert': finalText,
            'attributes': {'bold': true}
          });

          // 确保文档以换行符结尾（Quill要求）
          if (!finalText.endsWith('\n')) {
            finalOps.add({'insert': '\n'});
          }

          return quill.Document.fromJson(finalOps);
        }
      }
    } catch (e) {
      // 解析失败，回退到原始文档
    }

    // 没有加粗内容或解析失败，回退到原始文档
    try {
      return quill.Document.fromJson(jsonDecode(deltaContent));
    } catch (_) {
      return quill.Document()..insert(0, quote.content);
    }
  }

  /// 判断富文本内容是否需要折叠
  bool _needsExpansionForRichText(String deltaContent) {
    try {
      final doc = quill.Document.fromJson(jsonDecode(deltaContent));
      final plain = doc.toPlainText();
      final int lineCount = 1 + '\n'.allMatches(plain).length;
      return lineCount > 3 || plain.length > 150;
    } catch (_) {
      final int lineCount = 1 + '\n'.allMatches(quote.content).length;
      return lineCount > 3 || quote.content.length > 150;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final prioritizeBoldContent =
        settingsService.prioritizeBoldContentInCollapse;

    // 如果有富文本内容且来源是全屏编辑器，使用QuillEditor显示富文本
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      try {
        // 解析富文本内容
        final document = quill.Document.fromJson(
          jsonDecode(quote.deltaContent!),
        );

        // 如果开启了优先显示加粗内容且需要折叠
        quill.Document displayDocument = document;
        bool usedBoldOnlyMode = false;

        if (!showFullContent && maxLines != null && prioritizeBoldContent) {
          final needsExpansion =
              _needsExpansionForRichText(quote.deltaContent!);
          if (needsExpansion) {
            final boldTexts = _extractBoldText(quote.deltaContent!);
            if (boldTexts.isNotEmpty) {
              // 有加粗内容，只显示加粗内容
              displayDocument =
                  _createBoldOnlyDocument(quote.deltaContent!, maxLines!);
              usedBoldOnlyMode = true;
            }
            // 注意：没有加粗内容时，保持使用原始document，稍后会应用普通的高度限制
          }
        }

        // 创建只读QuillController
        final controller = quill.QuillController(
          document: displayDocument,
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
          // 如果使用了加粗优先模式，直接显示（已经在_createBoldOnlyDocument中处理了截断）
          if (usedBoldOnlyMode) {
            final estimatedLineHeight =
                (style?.height ?? 1.5) * (style?.fontSize ?? 14);
            final maxHeight = estimatedLineHeight * maxLines!;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Stack(
                children: [
                  ClipRect(
                    child: richTextEditor,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 24,
                    child: IgnorePointer(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Theme.of(context)
                                    .scaffoldBackgroundColor
                                    .withValues(alpha: 0.18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // 普通模式或没有加粗内容时，使用高度限制
          final estimatedLineHeight =
              (style?.height ?? 1.5) * (style?.fontSize ?? 14);
          final maxHeight = estimatedLineHeight * maxLines!;

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Stack(
              children: [
                ClipRect(
                  child: richTextEditor,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 24,
                  child: IgnorePointer(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Theme.of(context)
                                  .scaffoldBackgroundColor
                                  .withValues(alpha: 0.18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // 展开状态或无需折叠，显示完整内容
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
