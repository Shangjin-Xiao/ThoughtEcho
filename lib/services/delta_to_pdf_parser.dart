import 'dart:convert';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/pdf_font_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class DeltaToPdfParser {
  /// 将富文本的 Delta JSON 解析编译为适合 pdf 渲染的 Widget 列表
  static Future<List<pw.Widget>> parse(Quote quote, PdfFontSet fontSet) async {
    final List<pw.Widget> widgets = [];
    final deltaStr = quote.deltaContent;

    // 如果没有富文本格式，退回到普通纯文本段落渲染
    if (deltaStr == null || deltaStr.isEmpty) {
      widgets.add(
        pw.Paragraph(
          text: quote.content,
          style: pw.TextStyle(
            font: fontSet.regular,
            fontBold: fontSet.bold,
            fontItalic: fontSet.italic,
            fontBoldItalic: fontSet.boldItalic,
            fontSize: 12,
            lineSpacing: 4,
          ),
        ),
      );
      return widgets;
    }

    try {
      final List<dynamic> ops = json.decode(deltaStr);
      List<pw.InlineSpan> currentSpans = [];

      for (final op in ops) {
        if (op is! Map<String, dynamic>) continue;
        final insert = op['insert'];
        if (insert == null) continue;

        final attributes = op['attributes'] as Map<String, dynamic>? ?? {};

        // 1. 处理内联或独立图片
        if (insert is Map<String, dynamic> && insert.containsKey('image')) {
          if (currentSpans.isNotEmpty) {
            widgets.add(pw.RichText(text: pw.TextSpan(children: currentSpans)));
            currentSpans = [];
          }

          final imagePath = insert['image'] as String;
          final imageWidget = await _buildPdfImage(imagePath);
          if (imageWidget != null) {
            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: imageWidget,
            ));
          }
          continue;
        }

        // 2. 处理普通样式文本段落
        if (insert is String) {
          if (insert == '\n') {
            if (currentSpans.isNotEmpty) {
              widgets.add(pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                child: pw.RichText(text: pw.TextSpan(children: currentSpans)),
              ));
              currentSpans = [];
            } else {
              widgets.add(pw.SizedBox(height: 8));
            }
            continue;
          }

          final lines = insert.split('\n');
          for (int i = 0; i < lines.length; i++) {
            final lineText = lines[i];
            if (lineText.isNotEmpty) {
              final span = _buildTextSpan(lineText, attributes, fontSet);
              currentSpans.add(span);
            }

            if (i < lines.length - 1) {
              if (currentSpans.isNotEmpty) {
                widgets.add(pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.RichText(text: pw.TextSpan(children: currentSpans)),
                ));
                currentSpans = [];
              } else {
                widgets.add(pw.SizedBox(height: 8));
              }
            }
          }
        }
      }

      if (currentSpans.isNotEmpty) {
        widgets.add(pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          child: pw.RichText(text: pw.TextSpan(children: currentSpans)),
        ));
      }
    } catch (e, stack) {
      logError("DeltaToPdfParser 解析异常", error: e, stackTrace: stack);
      // 异常兜底：返回纯文本段落
      widgets.add(
        pw.Paragraph(
          text: quote.content,
          style: pw.TextStyle(
            font: fontSet.regular,
            fontBold: fontSet.bold,
            fontItalic: fontSet.italic,
            fontBoldItalic: fontSet.boldItalic,
            fontSize: 12,
            lineSpacing: 4,
          ),
        ),
      );
    }

    return widgets;
  }

  static pw.InlineSpan _buildTextSpan(
    String text,
    Map<String, dynamic> attrs,
    PdfFontSet fontSet,
  ) {
    final isBold = attrs['bold'] == true;
    final isItalic = attrs['italic'] == true;
    final isUnderline = attrs['underline'] == true;
    final colorHex = attrs['color'] as String?;

    PdfColor? fontColor;
    if (colorHex != null) {
      try {
        final hexStr = colorHex.replaceFirst('#', '');
        fontColor = PdfColor.fromHex(hexStr);
      } catch (_) {}
    }

    // 根据样式组合选择正确的字体变体，确保中文在粗体/斜体情况下不乱码
    final pw.Font activeFont;
    if (isBold && isItalic) {
      activeFont = fontSet.boldItalic;
    } else if (isBold) {
      activeFont = fontSet.bold;
    } else if (isItalic) {
      activeFont = fontSet.italic;
    } else {
      activeFont = fontSet.regular;
    }

    return pw.TextSpan(
      text: text,
      style: pw.TextStyle(
        font: activeFont,
        fontBold: fontSet.bold,
        fontItalic: fontSet.italic,
        fontBoldItalic: fontSet.boldItalic,
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
        decoration:
            isUnderline ? pw.TextDecoration.underline : pw.TextDecoration.none,
        color: fontColor,
      ),
    );
  }

  static Future<pw.Widget?> _buildPdfImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final image = pw.MemoryImage(bytes);
          return pw.Container(
            alignment: pw.Alignment.centerLeft,
            constraints: const pw.BoxConstraints(
              maxHeight: 200,
              maxWidth: 440, // 适应 A4 页面最大内边距限制
            ),
            child: pw.Image(image, fit: pw.BoxFit.contain),
          );
        }
      }
    } catch (e) {
      logDebug("DeltaToPdfParser 加载内联图片失败: $e", source: "DeltaToPdfParser");
    }
    return null;
  }
}
