import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/delta_to_pdf_parser.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class PdfExportService {
  /// 将一组笔记编译组装成一个符合 A4 标准、排版精致的 PDF 文件字节流
  static Future<Uint8List> exportNotesToPdf(
    List<Quote> quotes,
    pw.Font font,
    BuildContext context,
  ) async {
    final pdf = pw.Document(
      title: "ThoughtEcho Notes Export",
      author: "ThoughtEcho",
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

    // 2. 组装 PDF 页面布局
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
                    font: font,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  "导出日期: ${DateTime.now().toString().substring(0, 10)}",
                  style: pw.TextStyle(
                    font: font,
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
                font: font,
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
          );
        },
        build: (pw.Context context) {
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
                        pw.Text(
                          "📅 ${quote.date.substring(0, 10)} ${quote.dayPeriod ?? ''}",
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex("4A5568"),
                          ),
                        ),
                        // 天气与位置
                        pw.Row(
                          children: [
                            if (quote.weather != null) ...[
                              pw.Text(
                                "☀️ ${quote.weather!} ${quote.temperature ?? ''}",
                                style: pw.TextStyle(
                                  font: font,
                                  fontSize: 8,
                                  color: PdfColor.fromHex("718096"),
                                ),
                              ),
                              pw.SizedBox(width: 8),
                            ],
                            if (quote.location != null &&
                                quote.location!.isNotEmpty)
                              pw.Text(
                                "📍 ${quote.location}",
                                style: pw.TextStyle(
                                  font: font,
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
                    ...DeltaToPdfParser.parse(quote, font),

                    // --- 出处作者 ---
                    if (quote.source != null && quote.source!.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          "—— ${quote.source}",
                          style: pw.TextStyle(
                            font: font,
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
                            child: pw.Text(
                              "🏷️ $tagName",
                              style: pw.TextStyle(
                                font: font,
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

    // 3. 编译并生成 PDF 字节数据
    return await pdf.save();
  }
}
