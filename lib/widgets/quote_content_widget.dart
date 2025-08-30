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

  /// 创建仅显示加粗内容的Document（用户需求：只显示加粗，其余折叠）
  quill.Document _createBoldOnlyDocument(String deltaContent, int maxLines) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> boldOps = [];

        // 提取所有加粗内容，并保留原文中的换行（即使换行本身不是加粗）
        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];

            // 只保留加粗文本
            if (attributes != null && attributes['bold'] == true) {
              boldOps.add(Map<String, dynamic>.from(op));
              continue;
            }

            // 非加粗：如果包含换行，保留换行用于保持原有的行结构
            final newlineOnly = insert.replaceAll(RegExp(r'[^\n]'), '');
            if (newlineOnly.isNotEmpty) {
              boldOps.add({'insert': newlineOnly});
            }
          }
        }

        // 如果有加粗内容
        if (boldOps.isNotEmpty) {
          List<Map<String, dynamic>> finalOps = [];
          int currentLines = 0;

          // 工具：计算op可视行数（基于换行 + 末尾未闭合行）
          int _opLineCount(String s) {
            final newlineCount = '\n'.allMatches(s).length;
            final hasText = s.replaceAll('\n', '').isNotEmpty;
            if (hasText) {
              // 有文本内容，若非以\n结尾，多一行
              return newlineCount + (s.endsWith('\n') ? 0 : 1);
            }
            // 纯换行
            return newlineCount;
          }

          for (var op in boldOps) {
            String insert = op['insert'].toString();
            final int opLineCount = _opLineCount(insert);

            // 尚未达到限制，完整加入
            if (currentLines + opLineCount <= maxLines) {
              finalOps.add(op);
              currentLines += opLineCount;
              continue;
            }

            // 需要在当前op截断
            final int remainingLines = maxLines - currentLines;
            if (remainingLines <= 0) {
              // 直接补省略号
              finalOps.add({'insert': '...'});
              break;
            }

            // 根据剩余行数截断insert
            final parts = insert.split('\n');
            List<String> kept = [];
            int linesBudget = remainingLines;
            for (int i = 0; i < parts.length && linesBudget > 0; i++) {
              final segment = parts[i];
              // 将段加入
              kept.add(segment);
              // 如果不是最后一段，意味着存在一个换行，会消耗一行
              if (i < parts.length - 1) {
                // 追加换行占行
                linesBudget -= 1;
                if (linesBudget > 0) {
                  // 仍有预算，保留换行进入文本
                  kept[kept.length - 1] = kept.last + '\n';
                }
              } else {
                // 最后一段（无后续显式换行），如果该段非空，显示为一行
                if (segment.isNotEmpty) {
                  linesBudget -= 1;
                }
              }
            }

            String truncatedInsert = kept.join();

            // 写回截断op
            var truncatedOp = Map<String, dynamic>.from(op);
            truncatedOp['insert'] = truncatedInsert;
            finalOps.add(truncatedOp);

            // 添加省略号并终止
            finalOps.add({'insert': '...'});
            break;
          }

          // 如果没有找到任何加粗内容在行数限制内，至少显示一个占位符
          if (finalOps.isEmpty) {
            finalOps.add({
              'insert': '...',
              'attributes': {'bold': true}
            });
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
        } else {
          // 没有加粗内容，显示省略提示
          return quill.Document.fromJson([
            {'insert': '(无加粗内容，点击展开查看全文)', 'attributes': {'italic': true}},
            {'insert': '\n'}
          ]);
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

        // 如果开启了优先显示加粗内容且需要折叠
    quill.Document displayDocument;
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
            } else {
              // 没有加粗内容，使用原来的逻辑（显示前面几行）
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
    if (!usedBoldOnlyMode && !showFullContent && maxLines != null && needsExpansion) {
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
