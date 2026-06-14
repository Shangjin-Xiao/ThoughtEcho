import 'dart:typed_data';
import 'package:flutter/material.dart'
    show BuildContext, IconData, Localizations;
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

    if (!context.mounted) {
      return Uint8List(0);
    }

    final isZh = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final headerTitle = isZh
        ? "心迹 — 你的专属灵感摘录本"
        : "ThoughtEcho — Your Personal Inspiration Notebook";

    // 3. 组装 PDF 页面布局
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48), // 增加留白
        header: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerLeft,
            margin: const pw.EdgeInsets.only(bottom: 16),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
              ),
            ),
            child: pw.Text(
              headerTitle,
              style: pw.TextStyle(
                font: fontSet.bold, // 使用粗体让字迹更锐利
                fontBold: fontSet.bold,
                fontItalic: fontSet.italic,
                fontBoldItalic: fontSet.boldItalic,
                fontSize: 10.5, // 增大字号
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex("64748B"), // 颜色加深（Slate 500），提高对比度
              ),
            ),
          );
        },

        build: (pw.Context pdfContext) {
          final List<pw.Widget> content = [];

          for (int i = 0; i < quotes.length; i++) {
            final quote = quotes[i];

            PdfColor cardColor = PdfColors.white;
            if (quote.colorHex != null && quote.colorHex!.isNotEmpty) {
              try {
                String hex = quote.colorHex!.trim();
                if (!hex.startsWith('#')) {
                  hex = '#$hex';
                }
                cardColor = PdfColor.fromHex(hex);
              } catch (e) {
                cardColor = PdfColors.white;
              }
            }

            // 每一个笔记卡片以容器封装，还原应用内的圆润卡片质感
            content.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 20),
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: cardColor,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(12)),
                  border: pw.Border.all(
                      color: PdfColor.fromHex("F1F5F9"), width: 1.0),
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
                                  fontSize: 9,
                                  color: PdfColor.fromHex("475569"),
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
                                  fontSize: 9,
                                  color: PdfColor.fromHex("475569"),
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
                    if ((quote.sourceAuthor != null &&
                            quote.sourceAuthor!.isNotEmpty) ||
                        (quote.sourceWork != null &&
                            quote.sourceWork!.isNotEmpty)) ...[
                      pw.SizedBox(height: 8),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          _formatSource(
                              quote.sourceAuthor ?? '', quote.sourceWork ?? ''),
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
                    ] else if (quote.source != null &&
                        quote.source!.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          quote.source!,
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
                                fontSize: 9,
                                color: PdfColor.fromHex("334155"),
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
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        buildTagIcon(
          tag,
          fontSet,
          size: (style.fontSize ?? 8) + 1,
          color: style.color ?? PdfColors.grey700,
        ),
        pw.SizedBox(width: 3),
        pw.Text(text, style: style),
      ],
    );
  }

  static pw.Widget buildTagIcon(
    NoteCategory? tag,
    PdfFontSet fontSet, {
    double size = 9,
    PdfColor color = PdfColors.grey700,
  }) {
    final iconName = tag?.iconName;
    if (IconUtils.isEmoji(iconName)) {
      // 过滤 Unicode 变体选择符（U+FE00–U+FE0F），避免 ✈️（U+2708 + U+FE0F）等
      // 由「传统符号 + VS-16」组成的 emoji 把 U+FE0F 溢出到主字体，渲染成乱码字形（如 #）。
      final emojiText = iconName!.replaceAll(RegExp(r'[\uFE00-\uFE0F]'), '');
      return pw.Text(
        emojiText,
        style: pw.TextStyle(
          font: fontSet.regular,
          fontFallback: fontSet.fallbackFonts,
          fontSize: size,
        ),
      );
    }
    if (fontSet.materialIcons != null &&
        IconUtils.categoryIcons.containsKey(iconName)) {
      final icon = IconUtils.getIconData(iconName) as IconData;
      return pw.Icon(
        pw.IconData(
          icon.codePoint,
          matchTextDirection: icon.matchTextDirection,
        ),
        font: fontSet.materialIcons,
        size: size,
        color: color,
      );
    }
    return PdfExportIcons.build(PdfExportIcon.tag, size: size, color: color);
  }

  static String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      result += ' 《$work》';
    }
    return result;
  }
}
