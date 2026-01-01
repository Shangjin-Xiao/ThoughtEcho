import 'package:flutter/material.dart';
import 'package:thoughtecho/services/text_processing_service.dart';
import '../../gen_l10n/app_localizations.dart';

/// AI 操作按钮组件
/// 
/// 提供 AI 纠错和识别来源功能
class AIActionButtons extends StatelessWidget {
  final String text;
  final Function(String)? onCorrectionResult;
  final Function(String?, String?)? onSourceResult;

  const AIActionButtons({
    super.key,
    required this.text,
    this.onCorrectionResult,
    this.onSourceResult,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _applyCorrection(context),
            icon: const Icon(Icons.auto_fix_high),
            label: Text(l10n.voiceApplyCorrection),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _recognizeSource(context),
            icon: const Icon(Icons.search),
            label: Text(l10n.voiceRecognizeSource),
          ),
        ),
      ],
    );
  }

  /// AI 纠错 - 仅修复识别错误，不润色
  Future<void> _applyCorrection(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    // Check if model is available
    // For now we assume LocalAIService check was done before entering this screen or button enabled state
    // but good to show loading.

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.processingPleaseWait ?? 'Processing...')),
    );

    final correctedText = await TextProcessingService.instance.correctText(text);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.aiCorrectionApplied)),
    );

    onCorrectionResult?.call(correctedText);
  }

  /// 识别来源 - 提取作者和作品名
  Future<void> _recognizeSource(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.processingPleaseWait ?? 'Processing...')),
    );

    final result = await TextProcessingService.instance.extractSourceDetails(text);
    final author = result.$1;
    final work = result.$2;

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (author == null && work == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiNoSourceFound)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiSourceRecognized)),
      );
      onSourceResult?.call(author, work);
    }
  }
}
