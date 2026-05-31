import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

class PdfPreviewDialog extends StatelessWidget {
  final Uint8List pdfBytes;
  final String fileName;

  const PdfPreviewDialog({
    super.key,
    required this.pdfBytes,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Scaffold(
            appBar: AppBar(
              title: const Text("PDF 预览 & 打印"),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              elevation: 0,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            body: PdfPreview(
              build: (format) => pdfBytes,
              pdfFileName: fileName,
              allowPrinting: true,
              allowSharing: true,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              initialPageFormat: PdfPageFormat.a4,
            ),
          ),
        ),
      ),
    );
  }
}
