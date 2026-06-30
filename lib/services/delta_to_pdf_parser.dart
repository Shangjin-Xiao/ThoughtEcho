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
          text: sanitizeTextForPdf(quote.content),
          style: pw.TextStyle(
            font: fontSet.regular,
            fontBold: fontSet.bold,
            fontItalic: fontSet.italic,
            fontBoldItalic: fontSet.boldItalic,
            fontFallback: fontSet.fallbackFonts,
            fontSize: 12,
            lineSpacing: 4,
          ),
        ),
      );
      return widgets;
    }

    try {
      final ops = _decodeDeltaOps(deltaStr);
      List<pw.InlineSpan> currentSpans = [];
      var orderedListIndex = 1;

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
            orderedListIndex = _flushLine(
              widgets: widgets,
              spans: currentSpans,
              lineAttributes: attributes,
              fontSet: fontSet,
              orderedListIndex: orderedListIndex,
            );
            currentSpans = [];
            continue;
          }

          final lines = insert.split('\n');
          for (int i = 0; i < lines.length; i++) {
            final lineText = sanitizeTextForPdf(lines[i]);
            if (lineText.isNotEmpty) {
              final span = _buildTextSpan(lineText, attributes, fontSet);
              currentSpans.add(span);
            }

            if (i < lines.length - 1) {
              orderedListIndex = _flushLine(
                widgets: widgets,
                spans: currentSpans,
                lineAttributes: attributes,
                fontSet: fontSet,
                orderedListIndex: orderedListIndex,
              );
              currentSpans = [];
            }
          }
        }
      }

      if (currentSpans.isNotEmpty) {
        _flushLine(
          widgets: widgets,
          spans: currentSpans,
          lineAttributes: const {},
          fontSet: fontSet,
          orderedListIndex: orderedListIndex,
        );
      }
    } catch (e, stack) {
      logError("DeltaToPdfParser 解析异常", error: e, stackTrace: stack);
      // 异常兜底：返回纯文本段落
      widgets.add(
        pw.Paragraph(
          text: sanitizeTextForPdf(quote.content),
          style: pw.TextStyle(
            font: fontSet.regular,
            fontBold: fontSet.bold,
            fontItalic: fontSet.italic,
            fontBoldItalic: fontSet.boldItalic,
            fontFallback: fontSet.fallbackFonts,
            fontSize: 12,
            lineSpacing: 4,
          ),
        ),
      );
    }

    return widgets;
  }

  static List<dynamic> _decodeDeltaOps(String deltaStr) {
    final decoded = json.decode(deltaStr);
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map<String, dynamic> && decoded['ops'] is List) {
      return decoded['ops'] as List<dynamic>;
    }
    throw const FormatException('Unsupported Delta JSON format');
  }

  static String sanitizeTextForPdf(String text) {
    if (text.isEmpty) return text;
    final sanitizedRunes = text.runes.where((rune) {
      if (rune == 0xFFFC) return false; // Object replacement character.
      if (rune == 0x200D) return false; // Zero-width joiner.
      if (rune >= 0xFE00 && rune <= 0xFE0F) return false;
      if (rune >= 0xE0100 && rune <= 0xE01EF) return false;
      if (rune >= 0x1F3FB && rune <= 0x1F3FF) return false;
      if (rune == 0x20E3) return false; // Keycap combining mark.
      if (rune >= 0xE0020 && rune <= 0xE007F) return false;
      return true;
    });
    return String.fromCharCodes(sanitizedRunes);
  }

  static int _flushLine({
    required List<pw.Widget> widgets,
    required List<pw.InlineSpan> spans,
    required Map<String, dynamic> lineAttributes,
    required PdfFontSet fontSet,
    required int orderedListIndex,
  }) {
    final listType = lineAttributes['list']?.toString();
    if (spans.isEmpty && listType == null) {
      widgets.add(pw.SizedBox(height: 8));
      return 1;
    }

    final line = pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: _buildLineContent(
        spans,
        listType: listType,
        fontSet: fontSet,
        orderedListIndex: orderedListIndex,
      ),
    );
    widgets.add(line);

    if (listType == 'ordered') {
      return orderedListIndex + 1;
    }
    return 1;
  }

  static pw.Widget _buildLineContent(
    List<pw.InlineSpan> spans, {
    required String? listType,
    required PdfFontSet fontSet,
    required int orderedListIndex,
  }) {
    final text = pw.RichText(text: pw.TextSpan(children: List.of(spans)));
    final marker = switch (listType) {
      'bullet' => _bulletMarker(),
      'ordered' => _textMarker('$orderedListIndex.', fontSet),
      'checked' => _checkboxMarker(checked: true),
      'unchecked' => _checkboxMarker(checked: false),
      _ => null,
    };

    if (marker == null) {
      return text;
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 18,
          alignment: pw.Alignment.topRight,
          padding: const pw.EdgeInsets.only(top: 2),
          child: marker,
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(child: text),
      ],
    );
  }

  static pw.Widget _bulletMarker() {
    return pw.Container(
      width: 4,
      height: 4,
      margin: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        color: PdfColors.black,
        shape: pw.BoxShape.circle,
      ),
    );
  }

  static pw.Widget _textMarker(String text, PdfFontSet fontSet) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        font: fontSet.regular,
        fontFallback: fontSet.fallbackFonts,
        fontSize: 10,
      ),
    );
  }

  static pw.Widget _checkboxMarker({required bool checked}) {
    return pw.Container(
      width: 9,
      height: 9,
      margin: const pw.EdgeInsets.only(top: 1.5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: checked
          ? pw.Center(
              child: pw.Container(
                width: 5,
                height: 5,
                color: PdfColors.black,
              ),
            )
          : null,
    );
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
        fontFallback: fontSet.fallbackFonts,
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
