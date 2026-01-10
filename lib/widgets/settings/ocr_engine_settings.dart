/// 本地 AI OCR 引擎设置界面
///
/// 允许用户选择 OCR 引擎：Tesseract、VLM 或自动选择

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/local_ai/local_ai_service.dart';
import '../../services/local_ai/hybrid_ocr_service.dart';

/// OCR 引擎设置Widget
class OCREngineSettings extends StatelessWidget {
  const OCREngineSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localAI = LocalAIService.instance;
    final hybridOCR = localAI.hybridOCRService;

    return ListenableBuilder(
      listenable: hybridOCR,
      builder: (context, _) {
        final currentEngine = hybridOCR.preferredEngine;
        final mlkitAvailable = hybridOCR.isMLKitAvailable;
        final tesseractAvailable = hybridOCR.isTesseractAvailable;
        final vlmAvailable = hybridOCR.isVLMAvailable;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.ocrEngineSettings,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 当前引擎状态
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${l10n.ocrCurrentEngine}: ${_getEngineDisplayName(l10n, currentEngine)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // 自动选择选项
            RadioListTile<OCREngineType>(
              value: OCREngineType.auto,
              groupValue: currentEngine,
              onChanged: (value) {
                if (value != null) {
                  localAI.setOCREngine(value);
                }
              },
              title: Text(l10n.ocrEngineAuto),
              subtitle: Text(l10n.ocrEngineAutoDesc),
              secondary: Icon(
                Icons.auto_awesome,
                color: currentEngine == OCREngineType.auto
                    ? theme.colorScheme.primary
                    : null,
              ),
            ),

            const Divider(height: 1, indent: 72),

            // MLKit 选项（仅移动端）
            if (mlkitAvailable) ...[
              RadioListTile<OCREngineType>(
                value: OCREngineType.mlkit,
                groupValue: currentEngine,
                onChanged: (value) {
                  if (value != null) {
                    localAI.setOCREngine(value);
                  }
                },
                title: Row(
                  children: [
                    Text(l10n.ocrEngineMLKit),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '推荐',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(l10n.ocrEngineMLKitDesc),
                secondary: Icon(
                  Icons.phone_android,
                  color: currentEngine == OCREngineType.mlkit
                      ? theme.colorScheme.primary
                      : null,
                ),
              ),
              const Divider(height: 1, indent: 72),
            ],

            // Tesseract 选项
            RadioListTile<OCREngineType>(
              value: OCREngineType.tesseract,
              groupValue: currentEngine,
              onChanged: tesseractAvailable
                  ? (value) {
                      if (value != null) {
                        localAI.setOCREngine(value);
                      }
                    }
                  : null,
              title: Row(
                children: [
                  Text(l10n.ocrEngineTesseract),
                  if (!tesseractAvailable) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                  ],
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.ocrEngineTesseractDesc),
                  if (!tesseractAvailable)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '未下载 Tesseract 模型',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              secondary: Icon(
                Icons.text_fields,
                color: currentEngine == OCREngineType.tesseract && tesseractAvailable
                    ? theme.colorScheme.primary
                    : null,
              ),
            ),

            const Divider(height: 1, indent: 72),

            // VLM 选项
            RadioListTile<OCREngineType>(
              value: OCREngineType.vlm,
              groupValue: currentEngine,
              onChanged: vlmAvailable
                  ? (value) {
                      if (value != null) {
                        localAI.setOCREngine(value);
                      }
                    }
                  : null,
              title: Row(
                children: [
                  Text(l10n.ocrEngineVLM),
                  if (!vlmAvailable) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                  ],
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.ocrEngineVLMDesc),
                  if (!vlmAvailable)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.ocrVLMNotAvailable,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              secondary: Icon(
                Icons.psychology,
                color: currentEngine == OCREngineType.vlm && vlmAvailable
                    ? theme.colorScheme.primary
                    : null,
              ),
            ),

            const Divider(height: 1),

            // 下载提示
            if (!vlmAvailable)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.ocrVLMRecommendation,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '手写文字识别准确率：\n• Tesseract: 15-30%\n• VLM (PaliGemma): 85-92%',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () {
                            // 跳转到模型管理页面
                            Navigator.pushNamed(context, '/model-management');
                          },
                          icon: const Icon(Icons.download),
                          label: Text(l10n.ocrDownloadVLMModel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _getEngineDisplayName(AppLocalizations l10n, OCREngineType engine) {
    switch (engine) {
      case OCREngineType.auto:
        return l10n.ocrEngineAuto;
      case OCREngineType.mlkit:
        return l10n.ocrEngineMLKit;
      case OCREngineType.tesseract:
        return l10n.ocrEngineTesseract;
      case OCREngineType.vlm:
        return l10n.ocrEngineVLM;
    }
  }
}
