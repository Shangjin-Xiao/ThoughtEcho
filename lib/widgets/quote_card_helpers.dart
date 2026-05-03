import 'package:flutter/material.dart';
import '../models/note_category.dart';
import '../utils/icon_utils.dart';

class QuoteCardColors {
  final Color cardColor;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final Color iconColor;
  final Color baseContentColor;

  const QuoteCardColors({
    required this.cardColor,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.iconColor,
    required this.baseContentColor,
  });

  factory QuoteCardColors.fromHex(String? colorHex, ColorScheme colorScheme) {
    Color cardColor;
    if (colorHex != null && colorHex.isNotEmpty) {
      try {
        cardColor = Color(
          int.parse(colorHex.substring(1), radix: 16) | 0xFF000000,
        );
      } catch (_) {
        cardColor = colorScheme.surfaceContainerLowest;
      }
    } else {
      cardColor = colorScheme.surfaceContainerLowest;
    }

    final bool isLightCard =
        ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light;
    final Color base = isLightCard ? Colors.black : Colors.white;

    return QuoteCardColors(
      cardColor: cardColor,
      primaryTextColor: base.withValues(alpha: 0.9),
      secondaryTextColor: base.withValues(alpha: 0.7),
      iconColor: base.withValues(alpha: 0.65),
      baseContentColor: base,
    );
  }
}

class QuoteTagChip extends StatelessWidget {
  final NoteCategory tag;
  final Color secondaryTextColor;
  final Color baseContentColor;
  final bool highlighted;

  const QuoteTagChip({
    super.key,
    required this.tag,
    required this.secondaryTextColor,
    required this.baseContentColor,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: baseContentColor.withValues(alpha: highlighted ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: baseContentColor.withValues(alpha: highlighted ? 0.4 : 0.15),
          width: highlighted ? 1.0 : 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag.iconName?.isNotEmpty == true) ...[
            if (IconUtils.isEmoji(tag.iconName!)) ...[
              Text(
                IconUtils.getDisplayIcon(tag.iconName!),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 3),
            ] else ...[
              Icon(
                IconUtils.getIconData(tag.iconName!),
                size: 12,
                color: secondaryTextColor,
              ),
              const SizedBox(width: 3),
            ],
          ],
          Text(
            tag.name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: secondaryTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
