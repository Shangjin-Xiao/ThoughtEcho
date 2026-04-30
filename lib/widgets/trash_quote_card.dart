import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/string_utils.dart';
import '../utils/time_utils.dart';
import 'quote_card_helpers.dart';
import 'quote_content_widget.dart';

enum TrashQuoteCardAction { restore, permanentlyDelete }

class TrashQuoteCard extends StatelessWidget {
  final Quote quote;
  final String deletedAtText;
  final String remainingDaysText;
  final bool actionsEnabled;
  final ValueChanged<TrashQuoteCardAction>? onActionSelected;
  final Map<String, NoteCategory> tagMap;

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final colors = QuoteCardColors.fromHex(quote.colorHex, colorScheme);
    // Subtle desaturated background
    final isCustomColor = quote.colorHex != null && quote.colorHex!.isNotEmpty;
    final cardColor = isCustomColor 
        ? colors.cardColor.withValues(alpha: 0.15)
        : colorScheme.surfaceContainerLow;

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCustomColor 
            ? colors.cardColor.withValues(alpha: 0.3)
            : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Allow a subtle ink splash, but no navigation since it's in trash
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Trash Metadata Row ---
              Row(
                children: [
                  Icon(
                    Icons.auto_delete_outlined,
                    size: 16,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    remainingDaysText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    deletedAtText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // --- Original Metadata Row ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      formattedDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryTextColor,
                      ),
                    ),
                  ),
                  if (quote.hasLocation || quote.weather != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (quote.hasLocation) ...[
                          Icon(Icons.location_on_outlined, size: 14, color: colors.iconColor),
                          const SizedBox(width: 2),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 90),
                            child: Text(
                              (quote.location != null && LocationService.formatLocationForDisplay(quote.location).isNotEmpty)
                                  ? LocationService.formatLocationForDisplay(quote.location)
                                  : LocationService.formatCoordinates(quote.latitude, quote.longitude),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.secondaryTextColor,
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
                            WeatherService.getWeatherIconDataByKey(quote.weather!),
                            size: 14,
                            color: colors.iconColor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${WeatherService.getLocalizedWeatherDescription(l10n, quote.weather!)}${quote.temperature != null ? ' ${quote.temperature}' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              
              // --- Content ---
              Opacity(
                opacity: 0.9,
                child: QuoteContent(
                  quote: quote,
                  showFullContent: true,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.primaryTextColor,
                    height: 1.5,
                  ),
                ),
              ),
              
              // --- Source ---
              if ((quote.sourceAuthor != null && quote.sourceAuthor!.isNotEmpty) ||
                  (quote.sourceWork != null && quote.sourceWork!.isNotEmpty)) ...[
                const SizedBox(height: 8),
                Opacity(
                  opacity: 0.9,
                  child: Text(
                    StringUtils.formatSource(quote.sourceAuthor, quote.sourceWork),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryTextColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ] else if (quote.source != null && quote.source!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Opacity(
                  opacity: 0.9,
                  child: Text(
                    quote.source!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryTextColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],

              // --- Tags ---
              if (quote.tagIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: quote.tagIds.map((tagId) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: QuoteTagChip(
                          tag: tagMap[tagId] ?? NoteCategory(id: tagId, name: l10n.unknownTag),
                          secondaryTextColor: colors.secondaryTextColor,
                          baseContentColor: colors.baseContentColor,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              
              // --- Actions ---
              if (onActionSelected != null) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: actionsEnabled ? () => onActionSelected!(TrashQuoteCardAction.permanentlyDelete) : null,
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text(l10n.permanentlyDelete),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: actionsEnabled ? () => onActionSelected!(TrashQuoteCardAction.restore) : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.secondaryContainer,
                        foregroundColor: colorScheme.onSecondaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text(l10n.restore),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}