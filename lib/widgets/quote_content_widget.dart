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

  /// 创建优先显示加粗内容的Document (基于高度预估)
  quill.Document _createBoldPriorityDocument(String deltaContent, int maxLines,
      {bool hideImages = false}) {
    try {
      final validBoldOps = _extractValidBoldOps(deltaContent);

      if (validBoldOps.isNotEmpty) {
        List<Map<String, dynamic>> finalOps = [];

        // 收集加粗文本（按原顺序）
        for (var op in validBoldOps) {
          finalOps.add(op);
        }

        // 统计加粗内容的逻辑行数和字符数
        String allBoldText = '';
        for (var op in validBoldOps) {
          allBoldText += op['insert'].toString();
        }
        final boldLines = allBoldText.split('\n');
        int boldLineCount = 0;
        for (String line in boldLines) {
          if (line.trim().isNotEmpty) boldLineCount++;
        }

        // 基于高度预估：假设每行约30像素，120像素约4行
        // 如果加粗内容预估高度未超过限制，可以补充正文内容
        const int maxEstimatedLines = 4;
        bool truncated = false;

        if (boldLineCount < maxEstimatedLines) {
          // 加粗内容不足，添加换行分隔，然后补充非加粗内容
          if (!allBoldText.endsWith('\n')) {
            finalOps.add({'insert': '\n'});
          }

          // 添加分隔换行
          finalOps.add({'insert': '\n'});
          int currentLines = boldLineCount + 1; // +1 for separator

          // 补充非加粗内容
          final nonBoldOps = _extractNonBoldOps(deltaContent);
          for (var op in nonBoldOps) {
            if (currentLines >= maxEstimatedLines) break;

            // 处理媒体嵌入内容 - 现在不隐藏图片
            if (op['insert'] is Map) {
              final embed = op['insert'];
              // 图片/媒体内容会占用一定高度，但不隐藏
              finalOps.add(Map<String, dynamic>.from(op));
              // 图片大约占用1-2行的高度
              if (embed['image'] != null) {
                currentLines += 1; // 图片占用约1行空间
              }
              continue;
            }

            final String insert = op['insert'].toString();
            final lines = insert.split('\n');
            final Map<String, dynamic> attributes =
                Map<String, dynamic>.from(op['attributes'] ?? {});

            String buffer = '';
            for (String line in lines) {
              if (currentLines >= maxEstimatedLines) break;
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

          // 检查是否需要截断标记
          if (currentLines >= maxEstimatedLines) {
            truncated = true;
          }
        } else {
          // 加粗内容已经超过预估高度限制，截断加粗内容
          List<Map<String, dynamic>> truncatedOps = [];
          int currentLines = 0;

          for (var op in validBoldOps) {
            if (currentLines >= maxEstimatedLines) break;
            final String insert = op['insert'].toString();
            final lines = insert.split('\n');
            String truncatedInsert = '';
            for (String line in lines) {
              if (currentLines >= maxEstimatedLines) break;
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
          truncated = true;
        }

        // 如果截断，在末尾添加省略号
        if (truncated && finalOps.isNotEmpty) {
          final lastOp = finalOps.last;
          if (lastOp['insert'] != null) {
            final lastInsert = lastOp['insert'].toString();
            String normalized = lastInsert;
            while (normalized.endsWith('\n')) {
              normalized = normalized.substring(0, normalized.length - 1);
            }
            lastOp['insert'] = '${normalized.trimRight()}...\n';
          }
        }

        // 确保文档以换行结尾
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

  /// 创建普通折叠模式的Document (基于高度限制)
  quill.Document _createTruncatedDocument(String deltaContent, int maxLines,
      {bool hideImages = false}) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> finalOps = [];
        int currentLines = 0;
        const int maxEstimatedLines = 4; // 对应120像素高度

        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            // 如果是嵌入内容（图片、视频等）
            if (op['insert'] is Map) {
              final embed = op['insert'];
              // 现在不隐藏图片，但计算其占用的高度
              finalOps.add(Map<String, dynamic>.from(op));
              if (embed['image'] != null) {
                currentLines += 1; // 图片占用约1行空间
              }
              continue;
            }

            if (currentLines >= maxEstimatedLines) break;

            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];
            final lines = insert.split('\n');
            String truncatedInsert = '';

            for (String line in lines) {
              if (currentLines >= maxEstimatedLines) break;
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

        // 检查是否需要截断标记
        int totalLines = 0;
        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            if (op['insert'] is Map) {
              final embed = op['insert'];
              if (embed['image'] != null) {
                totalLines += 1; // 图片计为1行
              }
            } else {
              final String insert = op['insert'].toString();
              final lines = insert.split('\n');
              for (String line in lines) {
                if (line.trim().isNotEmpty) totalLines++;
              }
            }
          }
        }

        if (totalLines > maxEstimatedLines && finalOps.isNotEmpty) {
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

  /// 判断富文本内容是否需要折叠（基于高度预估）
  bool _needsExpansionForRichText(String deltaContent) {
    // 基于内容特征预估高度来判断是否需要折叠
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        bool hasImage = false;
        int lineCount = 0;
        int totalLength = 0;

        for (var op in decoded) {
          if (op is Map) {
            // 检查是否包含图片
            if (op['insert'] is Map && op['insert']['image'] != null) {
              hasImage = true;
            } else if (op['insert'] != null) {
              final String insert = op['insert'].toString();
              final lines = insert.split('\n');
              lineCount += lines.length - 1;
              if (!insert.endsWith('\n') && insert.isNotEmpty) lineCount++;
              totalLength += insert.length;
            }
          }
        }

        // 如果包含图片，默认需要折叠（因为图片会占用较大高度）
        // 或者文本内容超过一定阈值（预估高度约120像素，约4-5行）
        return hasImage || lineCount > 4 || totalLength > 150;
      }
    } catch (_) {
      final int lineCount = 1 + '\n'.allMatches(quote.content).length;
      return lineCount > 4;
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
        quill.Document displayDocument;

        if (!showFullContent &&
            _needsExpansionForRichText(quote.deltaContent!)) {
          const int maxLines = 4; // 固定使用4行作为折叠时的行数限制

          if (prioritizeBoldContent) {
            // 检查是否有有效的加粗内容
            final validBoldOps = _extractValidBoldOps(quote.deltaContent!);
            if (validBoldOps.isNotEmpty) {
              // 使用加粗优先模式，折叠状态下隐藏图片
              displayDocument = _createBoldPriorityDocument(
                  quote.deltaContent!, maxLines,
                  hideImages: false);
            } else {
              // 没有有效加粗内容，使用普通截断模式，折叠状态下隐藏图片
              displayDocument = _createTruncatedDocument(
                  quote.deltaContent!, maxLines,
                  hideImages: false);
            }
          } else {
            // 不启用加粗优先，使用普通截断模式，折叠状态下隐藏图片
            displayDocument = _createTruncatedDocument(
                quote.deltaContent!, maxLines,
                hideImages: false);
          }
        } else if (!showFullContent) {
          // 折叠状态但不需要截断，显示完整内容（包括图片）
          displayDocument =
              quill.Document.fromJson(jsonDecode(quote.deltaContent!));
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
        if (!showFullContent && needsExpansion) {
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
          maxLines: showFullContent ? null : 4,
          overflow:
              showFullContent ? TextOverflow.visible : TextOverflow.ellipsis,
        );
      }
    }

    // 使用普通文本显示（基于高度预估判断）
    final int lineCount = 1 + '\n'.allMatches(quote.content).length;
    final bool needsExpansion = lineCount > 4 || quote.content.length > 150;

    return Text(
      quote.content,
      style: style,
      maxLines: showFullContent ? null : (needsExpansion ? 4 : null),
      overflow: showFullContent
          ? TextOverflow.visible
          : (needsExpansion ? TextOverflow.ellipsis : TextOverflow.visible),
    );
  }
}
