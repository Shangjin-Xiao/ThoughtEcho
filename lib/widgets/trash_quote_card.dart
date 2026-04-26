import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
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
    final cardColor = colors.cardColor;

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
        boxShadow: AppTheme.defaultShadow,
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
                            color: colors.secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _MetaChip(
                              icon: Icons.delete_outline,
                              label: deletedAtText,
                              foregroundColor: colors.secondaryTextColor,
                            ),
                            _MetaChip(
                              icon: Icons.hourglass_bottom_outlined,
                              label: remainingDaysText,
                              foregroundColor: colors.secondaryTextColor,
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
                            Icon(Icons.location_on,
                                size: 14, color: colors.iconColor),
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
                              WeatherService.getWeatherIconDataByKey(
                                  quote.weather!),
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
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: QuoteContent(
                quote: quote,
                showFullContent: true,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.primaryTextColor,
                  height: 1.5,
                ),
              ),
            ),
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
                    color: colors.secondaryTextColor,
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
                    color: colors.secondaryTextColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (quote.tagIds.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Row(
                  children: [
                    Icon(Icons.label_outline,
                        size: 16, color: colors.iconColor),
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
                              Container(
                                margin: EdgeInsets.only(
                                  right:
                                      index < quote.tagIds.length - 1 ? 8 : 0,
                                ),
                                child: QuoteTagChip(
                                  tag: tagMap[quote.tagIds[index]] ??
                                      NoteCategory(
                                        id: quote.tagIds[index],
                                        name: l10n.unknownTag,
                                      ),
                                  secondaryTextColor: colors.secondaryTextColor,
                                  baseContentColor: colors.baseContentColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (onActionSelected != null)
              Align(
                alignment: Alignment.bottomRight,
                child: AbsorbPointer(
                  absorbing: !actionsEnabled,
                  child: Opacity(
                    opacity: actionsEnabled ? 1.0 : 0.5,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () =>
                              onActionSelected!(TrashQuoteCardAction.restore),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.primary,
                          ),
                          child: Text(l10n.restore),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => onActionSelected!(
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
