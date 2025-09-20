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

  /// 创建优先显示加粗内容的Document
  quill.Document _createBoldPriorityDocument(
      String deltaContent, int maxLines, {bool hideImages = false}) {
    try {
      final validBoldOps = _extractValidBoldOps(deltaContent);

      if (validBoldOps.isNotEmpty) {
        List<Map<String, dynamic>> finalOps = [];

        // 收集加粗文本（按原顺序）
        for (var op in validBoldOps) {
          finalOps.add(op);
        }

        // 统计加粗的非空逻辑行数
        String allBoldText = '';
        for (var op in validBoldOps) {
          allBoldText += op['insert'].toString();
        }
        final boldLines = allBoldText.split('\n');
        int boldLineCount = 0;
        for (String line in boldLines) {
          if (line.trim().isNotEmpty) boldLineCount++;
        }

        // 标记是否最终需要截断
        bool truncated = false;

        if (boldLineCount < maxLines) {
          // 加粗内容不足maxLines，需要添加换行分隔，然后补充非加粗内容
          // 确保加粗内容以换行结尾
          if (!allBoldText.endsWith('\n')) {
            finalOps.add({'insert': '\n'});
          }

          // 添加一个额外换行作为分隔
          finalOps.add({'insert': '\n'});
          int currentLines = boldLineCount + 1; // +1 for the separator line

          // 补充非加粗内容
          final nonBoldOps = _extractNonBoldOps(deltaContent);
          for (var op in nonBoldOps) {
            if (currentLines >= maxLines) break;

            // 处理媒体嵌入内容
            if (op['insert'] is Map) {
              final embed = op['insert'];
              // 在折叠状态下过滤掉图片
              if (hideImages && embed['image'] != null) {
                continue; // 跳过图片
              }
              finalOps.add(Map<String, dynamic>.from(op));
              continue; // 媒体不计入行数，但保留显示
            }

            final String insert = op['insert'].toString();
            final lines = insert.split('\n');
            final Map<String, dynamic> attributes =
                Map<String, dynamic>.from(op['attributes'] ?? {});

            String buffer = '';
            for (String line in lines) {
              if (currentLines >= maxLines) break;
              if (line.trim().isNotEmpty) {
                buffer += '$line\n';
                currentLines++;
              } else {
                buffer += '\n';
              }
            }

            if (buffer.isNotEmpty) {
              finalOps.add({'insert': buffer, 'attributes': attributes});
            }
          }

          // 判断是否还有未显示的正文
          if (nonBoldOps.isNotEmpty) {
            int totalNonBoldLines = 0;
            for (var op in nonBoldOps) {
              final text = op['insert'].toString();
              for (var l in text.split('\n')) {
                if (l.trim().isNotEmpty) totalNonBoldLines++;
              }
            }
            if (totalNonBoldLines + boldLineCount + 1 > maxLines) {
              // +1 for separator
              truncated = true;
            }
          }
        } else {
          // 加粗内容已经 >= maxLines，需要截断加粗内容
          List<Map<String, dynamic>> truncatedOps = [];
          int currentLines = 0;

          for (var op in validBoldOps) {
            if (currentLines >= maxLines) break;
            final String insert = op['insert'].toString();
            final lines = insert.split('\n');
            String truncatedInsert = '';
            for (String line in lines) {
              if (currentLines >= maxLines) break;
              truncatedInsert += '$line\n';
              if (line.trim().isNotEmpty) currentLines++;
            }
            if (truncatedInsert.isNotEmpty) {
              final Map<String, dynamic> attributes =
                  Map<String, dynamic>.from(op['attributes'] ?? {});
              truncatedOps.add({
                'insert': truncatedInsert,
                'attributes': attributes,
              });
            }
          }
          finalOps = truncatedOps;
          truncated = true; // 肯定截断
        }

        // 如果截断，则在最后一段尾部追加省略号（不新起一行）
        if (truncated && finalOps.isNotEmpty) {
          final lastOp = finalOps.last;
          if (lastOp['insert'] != null) {
            final lastInsert = lastOp['insert'].toString();
            // 去除尾部多余换行，只在内容末尾追加 ... 再补一个换行
            String normalized = lastInsert;
            while (normalized.endsWith('\n')) {
              normalized = normalized.substring(0, normalized.length - 1);
            }
            lastOp['insert'] = '${normalized.trimRight()}...\n';
          }
        }

        // 确保文档以换行结尾（符合 quill Document 习惯）
        if (finalOps.isNotEmpty) {
          final last = finalOps.last;
          if (last['insert'] is String &&
              !last['insert'].toString().endsWith('\n')) {
            finalOps.add({'insert': '\n'});
          }
        }

        return quill.Document.fromJson(finalOps);
      }
    } catch (e) {
      // 解析失败，回退
    }

    // 回退：原始文档
    try {
      return quill.Document.fromJson(jsonDecode(deltaContent));
    } catch (_) {
      return quill.Document()..insert(0, quote.content);
    }
  }

  /// 创建普通折叠模式的Document (仅限制行数，折叠状态下过滤图片)
  quill.Document _createTruncatedDocument(String deltaContent, int maxLines, {bool hideImages = false}) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> finalOps = [];
        int currentLines = 0;

        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            // 如果是嵌入内容（图片、视频等）
            if (op['insert'] is Map) {
              final embed = op['insert'];
              // 在折叠状态下过滤掉图片
              if (hideImages && embed['image'] != null) {
                continue; // 跳过图片
              }
              // 保留其他嵌入内容（如视频等）
              finalOps.add(Map<String, dynamic>.from(op));
              continue;
            }

            if (currentLines >= maxLines) break;

            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];
            final lines = insert.split('\n');
            String truncatedInsert = '';

            for (String line in lines) {
              if (currentLines >= maxLines) break;
              truncatedInsert += '$line\n';
              if (line.trim().isNotEmpty) currentLines++;
            }

            if (truncatedInsert.isNotEmpty) {
              finalOps.add({
                'insert': truncatedInsert,
                'attributes': Map<String, dynamic>.from(attributes ?? {})
              });
            }
          }
        }

        // 检查是否真的需要截断
        int totalLines = 0;
        for (var op in decoded) {
          if (op is Map && op['insert'] != null && op['insert'] is String) {
            final String insert = op['insert'].toString();
            final lines = insert.split('\n');
            for (String line in lines) {
              if (line.trim().isNotEmpty) totalLines++;
            }
          }
        }

        // 只有在真正需要截断时才添加省略号
        if (totalLines > maxLines && finalOps.isNotEmpty) {
          final lastOp = finalOps.last;
          if (lastOp['insert'] is String) {
            final lastInsert = lastOp['insert'].toString();
            lastOp['insert'] = '${lastInsert.trimRight()}...';
          }
        }

        // 确保文档以换行符结尾
        if (finalOps.isNotEmpty) {
          final lastOp = finalOps.last;
          if (lastOp['insert'] is String &&
              !lastOp['insert'].toString().endsWith('\n')) {
            finalOps.add({'insert': '\n'});
          }
        }

        return quill.Document.fromJson(finalOps);
      }
    } catch (e) {
      // 解析失败，回退到原始文档
    }

    // 解析失败，回退到原始文档
    try {
      return quill.Document.fromJson(jsonDecode(deltaContent));
    } catch (_) {
      return quill.Document()..insert(0, quote.content);
    }
  }

  /// 判断富文本内容是否需要折叠（仅检查行数）
  bool _needsExpansionForRichText(String deltaContent) {
    // 折叠策略（与外层保持一致）：只有当逻辑行数 > 4 时才进入折叠模式；
    // 折叠后外层 Text/QuoteContent 统一展示 4 行（或等价的截断文档）。
    // 这里的“逻辑行”基于 plain text 的换行符，不代表视觉自动换行数。
    try {
      final doc = quill.Document.fromJson(jsonDecode(deltaContent));
      final plain = doc.toPlainText();
      final int lineCount = 1 + '\n'.allMatches(plain).length;
      // 策略：>4 行才折叠，折叠后展示 4 行（外层 maxLines=4）
      return lineCount > 4;
    } catch (_) {
      final int lineCount = 1 + '\n'.allMatches(quote.content).length;
      return lineCount > 4;
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
        quill.Document displayDocument;

        if (!showFullContent && maxLines != null) {
          final needsExpansion =
              _needsExpansionForRichText(quote.deltaContent!);

          if (needsExpansion) {
            if (prioritizeBoldContent) {
              // 检查是否有有效的加粗内容
              final validBoldOps = _extractValidBoldOps(quote.deltaContent!);
              if (validBoldOps.isNotEmpty) {
                // 使用加粗优先模式，折叠状态下隐藏图片
                displayDocument =
                    _createBoldPriorityDocument(quote.deltaContent!, maxLines!, hideImages: true);
              } else {
                // 没有有效加粗内容，使用普通截断模式，折叠状态下隐藏图片
                displayDocument =
                    _createTruncatedDocument(quote.deltaContent!, maxLines!, hideImages: true);
              }
            } else {
              // 不启用加粗优先，使用普通截断模式，折叠状态下隐藏图片
              displayDocument =
                  _createTruncatedDocument(quote.deltaContent!, maxLines!, hideImages: true);
            }
          } else {
            // 不需要折叠，但仍需隐藏图片（因为是折叠状态）
            final decoded = jsonDecode(quote.deltaContent!);
            if (decoded is List) {
              final filteredOps = decoded.where((op) {
                if (op is Map && op['insert'] is Map) {
                  final embed = op['insert'];
                  if (embed['image'] != null) {
                    return false; // 过滤图片
                  }
                }
                return true;
              }).toList();
              displayDocument = quill.Document.fromJson(filteredOps);
            } else {
              displayDocument =
                  quill.Document.fromJson(jsonDecode(quote.deltaContent!));
            }
          }
        } else {
          // 展开状态或无行数限制，显示完整内容（包括图片）
          displayDocument =
              quill.Document.fromJson(jsonDecode(quote.deltaContent!));
        }

        // 创建只读QuillController
        final controller = quill.QuillController(
          document: displayDocument,
          selection: const TextSelection.collapsed(offset: 0),
        );

        // 创建QuillEditor
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

        // 如果内容被截断且处于折叠状态，添加极轻的渐变遮罩
        final bool needsExpansion =
            _needsExpansionForRichText(quote.deltaContent!);
        if (!showFullContent && maxLines != null && needsExpansion) {
          final double estimatedLineHeight =
              (style?.height ?? 1.5) * (style?.fontSize ?? 14);
          final double fadeHeight = estimatedLineHeight * 0.4; // 渐变高度约0.4行

          return Stack(
            children: [
              richTextEditor,
              // 极轻的底部渐变遮罩
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: fadeHeight,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.015),
                          Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.035),
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // 展开状态或无需折叠，直接显示
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

    // 使用普通文本显示（仅检查行数）
    final int lineCount = 1 + '\n'.allMatches(quote.content).length;
    final bool needsExpansion = lineCount > 3; // MODIFIED

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
