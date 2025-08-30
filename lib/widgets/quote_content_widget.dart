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

  /// 创建优先显示加粗内容的截断版本
  quill.Document _createBoldPriorityDocument(
      String deltaContent, int maxLines) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> prioritizedOps = [];
        List<Map<String, dynamic>> regularOps = [];

        // 分离加粗和普通内容
        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            final Map<String, dynamic>? attributes = op['attributes'];

            if (attributes != null && attributes['bold'] == true) {
              prioritizedOps.add(Map<String, dynamic>.from(op));
            } else {
              regularOps.add(Map<String, dynamic>.from(op));
            }
          }
        }

        // 如果有加粗内容，优先显示加粗内容
        if (prioritizedOps.isNotEmpty) {
          List<Map<String, dynamic>> finalOps = [];
          int currentLines = 0;
          int targetLines = maxLines;

          // 首先添加加粗内容
          for (var op in prioritizedOps) {
            if (currentLines >= targetLines) break;

            String insert = op['insert'].toString();
            int lineCount = '\n'.allMatches(insert).length;
            if (insert.isNotEmpty && !insert.endsWith('\n')) lineCount++;

            if (currentLines + lineCount <= targetLines) {
              finalOps.add(op);
              currentLines += lineCount;
            } else {
              // 截断内容以适应剩余行数
              int remainingLines = targetLines - currentLines;
              if (remainingLines > 0) {
                List<String> lines = insert.split('\n');
                if (lines.length > remainingLines) {
                  String truncatedInsert =
                      lines.take(remainingLines).join('\n');
                  if (remainingLines < lines.length) {
                    truncatedInsert += '...';
                  }
                  var truncatedOp = Map<String, dynamic>.from(op);
                  truncatedOp['insert'] = truncatedInsert;
                  finalOps.add(truncatedOp);
                }
              }
              break;
            }
          }

          // 如果还有空间，添加部分普通内容
          if (currentLines < targetLines && regularOps.isNotEmpty) {
            for (var op in regularOps) {
              if (currentLines >= targetLines) break;

              String insert = op['insert'].toString();
              int lineCount = '\n'.allMatches(insert).length;
              if (insert.isNotEmpty && !insert.endsWith('\n')) lineCount++;

              if (currentLines + lineCount <= targetLines) {
                finalOps.add(op);
                currentLines += lineCount;
              } else {
                // 截断内容
                int remainingLines = targetLines - currentLines;
                if (remainingLines > 0) {
                  List<String> lines = insert.split('\n');
                  if (lines.length > remainingLines) {
                    String truncatedInsert =
                        lines.take(remainingLines).join('\n');
                    truncatedInsert += '...';
                    var truncatedOp = Map<String, dynamic>.from(op);
                    truncatedOp['insert'] = truncatedInsert;
                    finalOps.add(truncatedOp);
                  }
                }
                break;
              }
            }
          }

          // 确保文档以换行符结尾（Quill要求）
          if (finalOps.isNotEmpty) {
            var lastOp = finalOps.last;
            String lastInsert = lastOp['insert'].toString();
            if (!lastInsert.endsWith('\n')) {
              finalOps.add({'insert': '\n'});
            }
          } else {
            finalOps.add({'insert': '\n'});
          }

          return quill.Document.fromJson(finalOps);
        }
      }
    } catch (_) {
      // 解析失败，回退到原始文档
    }

    // 回退到原始文档的普通截断
    try {
      return quill.Document.fromJson(jsonDecode(deltaContent));
    } catch (_) {
      return quill.Document()..insert(0, quote.content);
    }
  }

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

        // 如果开启了优先显示加粗内容且需要折叠，使用优化后的文档
        quill.Document displayDocument;
        if (!showFullContent && maxLines != null && prioritizeBoldContent) {
          final needsExpansion =
              _needsExpansionForRichText(quote.deltaContent!);
          if (needsExpansion) {
            final boldTexts = _extractBoldText(quote.deltaContent!);
            if (boldTexts.isNotEmpty) {
              displayDocument =
                  _createBoldPriorityDocument(quote.deltaContent!, maxLines!);
            } else {
              displayDocument = document;
            }
          } else {
            displayDocument = document;
          }
        } else {
          displayDocument = document;
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
