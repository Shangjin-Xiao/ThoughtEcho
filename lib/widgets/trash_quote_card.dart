import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../theme/app_theme.dart';
import '../utils/string_utils.dart';
import 'quote_content_widget.dart';

enum TrashQuoteCardAction { restore, permanentlyDelete }

class TrashQuoteCard extends StatelessWidget {
  final Quote quote;
  final String deletedAtText;
  final String remainingDaysText;
  final bool actionsEnabled;
  final ValueChanged<TrashQuoteCardAction>? onActionSelected;

  const TrashQuoteCard({
    super.key,
    required this.quote,
    required this.deletedAtText,
    required this.remainingDaysText,
    required this.actionsEnabled,
    this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final cardColor = _resolveCardColor(colorScheme);
    final isLightCard =
        ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light;
    final primaryColor = isLightCard ? Colors.black87 : Colors.white;
    final secondaryColor = primaryColor.withValues(alpha: 0.72);
    final sourceText = _buildSourceText();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        icon: Icons.delete_outline,
                        label: deletedAtText,
                        foregroundColor: secondaryColor,
                      ),
                      _MetaChip(
                        icon: Icons.hourglass_bottom_outlined,
                        label: remainingDaysText,
                        foregroundColor: secondaryColor,
                      ),
                    ],
                  ),
                ),
                if (onActionSelected != null)
                  PopupMenuButton<TrashQuoteCardAction>(
                    enabled: actionsEnabled,
                    tooltip: l10n.moreOptions,
                    icon: Icon(Icons.more_vert, color: secondaryColor),
                    onSelected: onActionSelected,
                    itemBuilder: (context) => [
                      PopupMenuItem<TrashQuoteCardAction>(
                        value: TrashQuoteCardAction.restore,
                        child: Text(l10n.restoreNote),
                      ),
                      PopupMenuItem<TrashQuoteCardAction>(
                        value: TrashQuoteCardAction.permanentlyDelete,
                        child: Text(l10n.permanentlyDelete),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            QuoteContent(
              quote: quote,
              showFullContent: true,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: primaryColor,
                height: 1.55,
              ),
            ),
            if (sourceText != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  sourceText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryColor,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _resolveCardColor(ColorScheme colorScheme) {
    final colorHex = quote.colorHex;
    if (colorHex == null || colorHex.isEmpty) {
      return colorScheme.surfaceContainerLowest;
    }

    try {
      return Color(int.parse(colorHex.substring(1), radix: 16) | 0xFF000000);
    } catch (_) {
      return colorScheme.surfaceContainerLowest;
    }
  }

  String? _buildSourceText() {
    final formatted = StringUtils.formatSource(
      quote.sourceAuthor?.trim(),
      quote.sourceWork?.trim(),
    );
    if (formatted.isNotEmpty) {
      return formatted;
    }

    final source = quote.source?.trim();
    if (source == null || source.isEmpty) {
      return null;
    }
    return source;
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foregroundColor;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: foregroundColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foregroundColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
