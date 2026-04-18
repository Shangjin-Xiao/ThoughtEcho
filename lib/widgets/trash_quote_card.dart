import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart'; // For showExactTime
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../utils/icon_utils.dart'; // For tag icons
import '../utils/string_utils.dart';
import '../utils/time_utils.dart'; // For time formatting
import 'quote_content_widget.dart';

enum TrashQuoteCardAction { restore, permanentlyDelete }

class TrashQuoteCard extends StatefulWidget {
  final Quote quote;
  final String deletedAtText;
  final String remainingDaysText;
  final bool actionsEnabled;
  final ValueChanged<TrashQuoteCardAction>? onActionSelected;
  final Map<String, NoteCategory> tagMap; // Assume tagMap is passed in

  const TrashQuoteCard({
    super.key,
    required this.quote,
    required this.deletedAtText,
    required this.remainingDaysText,
    required this.actionsEnabled,
    required this.tagMap,
    this.onActionSelected,
  });

  @override
  State<TrashQuoteCard> createState() => _TrashQuoteCardState();
}

class _TrashQuoteCardState extends State<TrashQuoteCard> {
  // Helper methods from QuoteItemWidget, adapted for TrashQuoteCard

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final quote = widget.quote;

    // Determine the background color of the card
    final Color cardColor = _resolveCardColor(colorScheme);

    // 计算卡片背景的亮度，决定内容颜色
    final bool isLightCard =
        ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light;
    final Color baseContentColor = isLightCard ? Colors.black : Colors.white;

    final Color primaryTextColor = baseContentColor.withValues(alpha: 0.9);
    final Color secondaryTextColor = baseContentColor.withValues(alpha: 0.7);
    final Color iconColor = baseContentColor.withValues(alpha: 0.65);

    // Formatted date and time (from QuoteItemWidget)
    final DateTime quoteDate = DateTime.parse(quote.date);
    final showExactTime = context.select<SettingsService, bool>(
      (s) => s.showExactTime,
    );
    final String formattedDate = TimeUtils.formatQuoteDateLocalized(
      context,
      quoteDate,
      dayPeriod: quote.dayPeriod,
      showExactTime: showExactTime,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: AppTheme.defaultShadow, // Use default shadow for consistency
        gradient: quote.colorHex != null && quote.colorHex!.isNotEmpty
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cardColor, cardColor.withValues(alpha: 0.95)],
              )
            : null,
        color: quote.colorHex == null || quote.colorHex!.isEmpty
            ? cardColor
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Date, Weather, Location, Deleted Info
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattedDate,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _MetaChip(
                              icon: Icons.delete_outline,
                              label: widget.deletedAtText,
                              foregroundColor: secondaryTextColor,
                            ),
                            _MetaChip(
                              icon: Icons.hourglass_bottom_outlined,
                              label: widget.remainingDaysText,
                              foregroundColor: secondaryTextColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (quote.hasLocation || quote.weather != null)
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (quote.hasLocation) ...[
                            Icon(Icons.location_on, size: 14, color: iconColor),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                (quote.location != null &&
                                        LocationService
                                            .formatLocationForDisplay(
                                          quote.location,
                                        ).isNotEmpty)
                                    ? LocationService.formatLocationForDisplay(
                                        quote.location,
                                      )
                                    : LocationService.formatCoordinates(
                                        quote.latitude,
                                        quote.longitude,
                                      ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: secondaryTextColor,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                          if (quote.hasLocation && quote.weather != null)
                            const SizedBox(width: 8),
                          if (quote.weather != null) ...[
                            Icon(
                              _getWeatherIcon(quote.weather!),
                              size: 14,
                              color: iconColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${WeatherService.getLocalizedWeatherDescription(l10n, quote.weather!)}${quote.temperature != null ? ' ${quote.temperature}' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondaryTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Quote Content
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: QuoteContent(
                quote: quote,
                showFullContent: true, // Always show full content in trash
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: primaryTextColor,
                  height: 1.5,
                ),
              ),
            ),

            // Source Information
            if ((quote.sourceAuthor != null &&
                    quote.sourceAuthor!.isNotEmpty) ||
                (quote.sourceWork != null && quote.sourceWork!.isNotEmpty)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(
                  StringUtils.formatSource(
                    quote.sourceAuthor,
                    quote.sourceWork,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondaryTextColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ] else if (quote.source != null && quote.source!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(
                  quote.source!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondaryTextColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],

            // Tags (mimicking QuoteItemWidget)
            if (quote.tagIds.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Row(
                  children: [
                    Icon(Icons.label_outline, size: 16, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (int index = 0;
                                index < quote.tagIds.length;
                                index++)
                              () {
                                final tagId = quote.tagIds[index];
                                final tag = widget.tagMap[tagId] ??
                                    NoteCategory(
                                      id: tagId,
                                      name: l10n.unknownTag,
                                    );

                                return Container(
                                  margin: EdgeInsets.only(
                                    right:
                                        index < quote.tagIds.length - 1 ? 8 : 0,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: baseContentColor.withValues(
                                          alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: baseContentColor.withValues(
                                            alpha: 0.15),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (tag.iconName?.isNotEmpty ==
                                            true) ...[
                                          if (IconUtils.isEmoji(
                                            tag.iconName!,
                                          )) ...[
                                            Text(
                                              IconUtils.getDisplayIcon(
                                                tag.iconName!,
                                              ),
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 3),
                                          ] else ...[
                                            Icon(
                                              IconUtils.getIconData(
                                                tag.iconName!,
                                              ),
                                              size: 12,
                                              color: secondaryTextColor,
                                            ),
                                            const SizedBox(width: 3),
                                          ],
                                        ],
                                        Text(
                                          tag.name,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: secondaryTextColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Actions: Restore and Permanently Delete (explicit buttons)
            if (widget.onActionSelected != null)
              Align(
                alignment: Alignment.bottomRight,
                child: AbsorbPointer(
                  absorbing: !widget.actionsEnabled,
                  child: Opacity(
                    opacity: widget.actionsEnabled ? 1.0 : 0.5,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => widget
                              .onActionSelected!(TrashQuoteCardAction.restore),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.primary,
                          ),
                          child: Text(l10n.restore),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => widget.onActionSelected!(
                              TrashQuoteCardAction.permanentlyDelete),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(color: colorScheme.error),
                          ),
                          child: Text(l10n.permanentlyDelete),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
