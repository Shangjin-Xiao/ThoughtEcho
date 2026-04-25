part of '../trash_quote_card.dart';

extension _TrashCardHelpers on _TrashQuoteCardState {
  IconData _getWeatherIcon(String weatherKey) {
    return WeatherService.getWeatherIconDataByKey(weatherKey);
  }

  Color _resolveCardColor(ColorScheme colorScheme) {
    final colorHex = widget.quote.colorHex;
    if (colorHex == null || colorHex.isEmpty) {
      return colorScheme.surfaceContainerLowest;
    }

    try {
      return Color(int.parse(colorHex.substring(1), radix: 16) | 0xFF000000);
    } catch (_) {
      return colorScheme.surfaceContainerLowest;
    }
  }
}

class TrashCardMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foregroundColor;

  const TrashCardMetaChip({
    super.key,
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
