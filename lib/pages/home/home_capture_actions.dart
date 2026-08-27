import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/local_ai/ocr_capture_page.dart';
import 'package:thoughtecho/widgets/local_ai/ocr_result_sheet.dart';
import 'package:thoughtecho/widgets/local_ai/voice_input_overlay.dart';

/// Owns the home-page voice and OCR capture journey.
class HomeCaptureActions {
  const HomeCaptureActions({
    required this.context,
    required this.isMounted,
    required this.onInsertText,
  });

  final BuildContext context;
  final bool Function() isMounted;
  final ValueChanged<String> onInsertText;

  Future<void> startVoiceCapture() async {
    final settings = context.read<SettingsService>().localAISettings;
    if (!settings.enabled || !settings.speechToTextEnabled) return;
    if (!isMounted() || !context.mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'voice_input_overlay',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return VoiceInputOverlay(
          transcribedText: null,
          onSwipeUpForOCR: () async {
            Navigator.of(dialogContext).pop();
            await _openOcrFlow();
          },
          onRecordComplete: () {
            Navigator.of(dialogContext).pop();
            if (!isMounted() || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).featureComingSoon),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(opacity: curved, child: child);
      },
      transitionDuration: const Duration(milliseconds: 180),
    );
  }

  Future<void> _openOcrFlow() async {
    if (!isMounted() || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const OCRCapturePage()),
    );
    if (!isMounted() || !context.mounted) return;

    final l10n = AppLocalizations.of(context);
    var resultText = l10n.featureComingSoon;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return OCRResultSheet(
          recognizedText: resultText,
          onTextChanged: (text) => resultText = text,
          onInsertToEditor: () {
            Navigator.of(sheetContext).pop();
            onInsertText(resultText);
          },
          onRecognizeSource: () {},
        );
      },
    );
  }
}
