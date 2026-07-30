import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/generated_card.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/ai_card_generation_service.dart';
import 'package:thoughtecho/services/svg_to_image_service.dart';
import 'package:thoughtecho/theme/app_semantic_colors.dart';
import 'package:thoughtecho/widgets/app_snackbar.dart';
import 'package:thoughtecho/widgets/svg_card_widget.dart';

/// Owns the complete AI-card interaction flow used by the home page.
///
/// Callers only start generation. Preview, regeneration, image export, share,
/// save, progress feedback and failures remain local to this module.
class HomeCardActions {
  HomeCardActions({
    required this.context,
    required this.isMounted,
    required AICardGenerationService? cardService,
  }) : _cardService = cardService;

  final BuildContext context;
  final bool Function() isMounted;
  AICardGenerationService? _cardService;

  void configure(AICardGenerationService service) {
    _cardService ??= service;
  }

  Future<void> generateCard(Quote quote) async {
    final service = _cardService;
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).aiCardServiceNotInitialized,
          ),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CardGenerationLoadingDialog(),
    );

    try {
      final brandName = AppLocalizations.of(context).appTitle;
      final card = await service.generateCard(
        note: quote,
        brandName: brandName,
      );
      if (!isMounted() || !context.mounted) return;

      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => CardPreviewDialog(
          card: card,
          onShare: _shareCard,
          onSave: (selected) => _saveCard(service, selected),
          onRegenerate: () => service.generateCard(
            note: quote,
            isRegeneration: true,
            brandName: brandName,
          ),
        ),
      );
    } catch (error) {
      if (!isMounted() || !context.mounted) return;
      Navigator.of(context).pop();
      AppSnackBar.error(
        context,
        AppLocalizations.of(context).generateCardFailed(error.toString()),
      );
    }
  }

  Future<void> _shareCard(GeneratedCard card) async {
    try {
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(AppLocalizations.of(context).generatingShareImage),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      final imageBytes = await card.toImageBytes(
        width: 800,
        height: 1200,
        context: context,
        scaleFactor: 2,
        renderMode: ExportRenderMode.contain,
      );
      final tempDir = await getTemporaryDirectory();
      final fileName = '心迹_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);
      await SharePlus.instance.share(
        ShareParams(
          text: '来自心迹的精美卡片\n\n'
              '"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
          files: [XFile(file.path)],
        ),
      );

      if (!isMounted() || !context.mounted) return;
      final semantic = AppSemanticColors.of(context);
      AppSnackBar.showCustom(
        context,
        Row(
          children: [
            Icon(Icons.check_circle, color: semantic.onSuccessContainer),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context).cardSharedSuccessfully),
          ],
        ),
        backgroundColor: semantic.successContainer,
      );
    } catch (error) {
      if (!isMounted() || !context.mounted) return;
      final errorColorScheme = Theme.of(context).colorScheme;
      AppSnackBar.showCustom(
        context,
        Row(
          children: [
            Icon(Icons.error, color: errorColorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context).shareFailed(error.toString()),
              ),
            ),
          ],
        ),
        backgroundColor: errorColorScheme.errorContainer,
      );
    }
  }

  Future<void> _saveCard(
    AICardGenerationService service,
    GeneratedCard card,
  ) async {
    try {
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(AppLocalizations.of(context).savingCardToGallery),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      final filePath = await service.saveCardAsImage(
        card,
        width: 800,
        height: 1200,
        scaleFactor: 2,
        renderMode: ExportRenderMode.contain,
        context: context,
        fileNamePrefix: AppLocalizations.of(context).cardFileNamePrefix,
      );
      if (!isMounted() || !context.mounted) return;

      final l10n = AppLocalizations.of(context);
      final semantic = AppSemanticColors.of(context);
      AppSnackBar.showCustom(
        context,
        Row(
          children: [
            Icon(Icons.check_circle, color: semantic.onSuccessContainer),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.cardSavedToGallery(filePath))),
          ],
        ),
        backgroundColor: semantic.successContainer,
        action: SnackBarAction(
          label: l10n.view,
          textColor: semantic.onSuccessContainer,
          onPressed: () {},
        ),
      );
    } catch (error) {
      if (!isMounted() || !context.mounted) return;
      final errorColorScheme = Theme.of(context).colorScheme;
      AppSnackBar.showCustom(
        context,
        Row(
          children: [
            Icon(Icons.error, color: errorColorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context).saveFailed(error.toString()),
              ),
            ),
          ],
        ),
        backgroundColor: errorColorScheme.errorContainer,
      );
    }
  }
}
