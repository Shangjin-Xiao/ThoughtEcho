import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/delta_to_pdf_parser.dart';
import 'package:thoughtecho/services/pdf_font_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/icon_utils.dart';
import 'package:thoughtecho/utils/time_utils.dart';

enum PdfExportIcon { calendar, weather, location, tag }

class PdfExportIcons {
  static const values = PdfExportIcon.values;

  static pw.Widget build(
    PdfExportIcon icon, {
    double size = 9,
    PdfColor color = PdfColors.grey700,
  }) {
    return pw.SvgImage(
      svg: _svg(icon),
      width: size,
      height: size,
      fit: pw.BoxFit.contain,
      colorFilter: color,
    );
  }

  static String _svg(PdfExportIcon icon) => switch (icon) {
        PdfExportIcon.calendar =>
          '<svg viewBox="0 0 24 24"><path d="M7 2h2v3h6V2h2v3h2a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2V2Zm12 8H5v9h14v-9Z"/></svg>',
        PdfExportIcon.weather =>
          '<svg viewBox="0 0 24 24"><path d="M12 7a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0-5 1 3h-2l1-3Zm0 20-1-3h2l-1 3ZM2 12l3-1v2l-3-1Zm20 0-3 1v-2l3 1ZM5 5l3 1-2 2-1-3Zm14 14-3-1 2-2 1 3Zm0-14-1 3-2-2 3-1ZM5 19l1-3 2 2-3 1Z"/></svg>',
        PdfExportIcon.location =>
          '<svg viewBox="0 0 24 24"><path d="M12 2a8 8 0 0 1 8 8c0 5.5-8 12-8 12S4 15.5 4 10a8 8 0 0 1 8-8Zm0 5a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z"/></svg>',
        PdfExportIcon.tag =>
          '<svg viewBox="0 0 24 24"><path d="M3 4a1 1 0 0 1 1-1h7l10 10a2 2 0 0 1 0 3l-5 5a2 2 0 0 1-3 0L3 11V4Zm5 2a2 2 0 1 0 0 4 2 2 0 0 0 0-4Z"/></svg>',
      };
}

class PdfExportService {
  /// 将一组笔记编译组装成一个符合 A4 标准、排版精致的 PDF 文件字节流
  static Future<Uint8List> exportNotesToPdf(
    List<Quote> quotes,
    PdfFontSet fontSet,
    BuildContext context,
  ) async {
    final pdf = pw.Document(
      title: "ThoughtEcho Notes Export",
      author: "ThoughtEcho",
      theme: pw.ThemeData.withFont(
        base: fontSet.regular,
        bold: fontSet.bold,
        italic: fontSet.italic,
        boldItalic: fontSet.boldItalic,
        fontFallback: fontSet.fallbackFonts,
      ),
    );

    // 1. 获取全局标签分类映射，用来还原标签名字
    Map<String, NoteCategory> tagMap = {};
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      final categories = await db.getCategories();
      tagMap = {for (var c in categories) c.id: c};
    } catch (e) {
      logDebug("PdfExportService 获取标签映射失败: $e", source: "PdfExportService");
    }

    // 2. 预解析所有笔记富文本内容（避免在同步的 build 方法中执行异步解析）
    List<List<pw.Widget>> parsedQuotes = [];
    for (var quote in quotes) {
      parsedQuotes.add(await DeltaToPdfParser.parse(quote, fontSet));
    }

    // 3. 组装 PDF 页面布局
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36), // 0.5 英寸边距
        header: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  "ThoughtEcho (心迹) — 专属思想摘录本",
                  style: pw.TextStyle(
                    font: fontSet.regular,
                    fontBold: fontSet.bold,
                    fontItalic: fontSet.italic,
                    fontBoldItalic: fontSet.boldItalic,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  "导出日期: ${DateTime.now().toString().substring(0, 10)}",
                  style: pw.TextStyle(
                    font: fontSet.regular,
                    fontBold: fontSet.bold,
                    fontItalic: fontSet.italic,
                    fontBoldItalic: fontSet.boldItalic,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 16),
            child: pw.Text(
              "第 ${context.pageNumber} 页 / 共 ${context.pagesCount} 页",
              style: pw.TextStyle(
                font: fontSet.regular,
                fontBold: fontSet.bold,
                fontItalic: fontSet.italic,
                fontBoldItalic: fontSet.boldItalic,
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
          );
        },
        build: (pw.Context pdfContext) {
          final List<pw.Widget> content = [];

          for (int i = 0; i < quotes.length; i++) {
            final quote = quotes[i];

            // 每一个笔记卡片以容器封装，配有细虚线或实线边框
            content.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(
                      color: PdfColor.fromHex("E2E8F0"), width: 0.8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // --- 元数据头部 ---
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        // 日期与时间段
                        _iconText(
                          PdfExportIcon.calendar,
                          "${quote.date.substring(0, 10)}${quote.dayPeriod != null ? ' ${TimeUtils.getLocalizedDayPeriodLabel(context, quote.dayPeriod!)}' : ''}",
                          pw.TextStyle(
                            font: fontSet.regular,
                            fontBold: fontSet.bold,
                            fontItalic: fontSet.italic,
                            fontBoldItalic: fontSet.boldItalic,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex("4A5568"),
                          ),
                        ),
                        // 天气与位置
                        pw.Row(
                          children: [
                            if (quote.weather != null) ...[
                              _iconText(
                                PdfExportIcon.weather,
                                "${WeatherService.getLocalizedWeatherLabel(context, quote.weather!)} ${quote.temperature ?? ''}",
                                pw.TextStyle(
                                  font: fontSet.regular,
                                  fontBold: fontSet.bold,
                                  fontItalic: fontSet.italic,
                                  fontBoldItalic: fontSet.boldItalic,
                                  fontSize: 8,
                                  color: PdfColor.fromHex("718096"),
                                ),
                              ),
                              pw.SizedBox(width: 8),
                            ],
                            if (quote.location != null &&
                                quote.location!.isNotEmpty)
                              _iconText(
                                PdfExportIcon.location,
                                quote.location!,
                                pw.TextStyle(
                                  font: fontSet.regular,
                                  fontBold: fontSet.bold,
                                  fontItalic: fontSet.italic,
                                  fontBoldItalic: fontSet.boldItalic,
                                  fontSize: 8,
                                  color: PdfColor.fromHex("718096"),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    pw.Divider(
                        color: PdfColor.fromHex("EDF2F7"),
                        thickness: 0.6,
                        height: 12),

                    // --- 富文本解析出的主体内容段落 ---
                    ...parsedQuotes[i],

                    // --- 出处作者 ---
                    if (quote.source != null && quote.source!.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          "—— ${quote.source}",
                          style: pw.TextStyle(
                            font: fontSet.italic,
                            fontBold: fontSet.boldItalic,
                            fontItalic: fontSet.italic,
                            fontBoldItalic: fontSet.boldItalic,
                            fontSize: 10,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColor.fromHex("4A5568"),
                          ),
                        ),
                      ),
                    ],

                    // --- 标签列表 ---
                    if (quote.tagIds.isNotEmpty) ...[
                      pw.SizedBox(height: 10),
                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: quote.tagIds.map((tagId) {
                          final tag = tagMap[tagId];
                          final tagName = tag != null ? tag.name : "未知标签";
                          return pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex("EDF2F7"),
                              borderRadius: const pw.BorderRadius.all(
                                  pw.Radius.circular(4)),
                            ),
                            child: _tagText(
                              tag,
                              tagName,
                              fontSet,
                              pw.TextStyle(
                                font: fontSet.regular,
                                fontBold: fontSet.bold,
                                fontItalic: fontSet.italic,
                                fontBoldItalic: fontSet.boldItalic,
                                fontSize: 8,
                                color: PdfColor.fromHex("4A5568"),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return content;
        },
      ),
    );

    // 4. 编译并生成 PDF 字节数据
    return await pdf.save();
  }

  static pw.Widget _iconText(
    PdfExportIcon icon,
    String text,
    pw.TextStyle style,
  ) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        PdfExportIcons.build(
          icon,
          size: style.fontSize ?? 9,
          color: style.color ?? PdfColors.grey700,
        ),
        pw.SizedBox(width: 3),
        pw.Text(text, style: style),
      ],
    );
  }

  static pw.Widget _tagText(
    NoteCategory? tag,
    String text,
    PdfFontSet fontSet,
    pw.TextStyle style,
  ) {
    final iconName = tag?.iconName;
    if (IconUtils.isEmoji(iconName)) {
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            iconName!,
            style: pw.TextStyle(
              font: fontSet.regular,
              fontFallback: fontSet.fallbackFonts,
              fontSize: (style.fontSize ?? 8) + 1,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Text(text, style: style),
        ],
      );
    }
    return _iconText(PdfExportIcon.tag, text, style);
  }
}
