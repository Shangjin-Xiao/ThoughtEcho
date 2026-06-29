// ignore_for_file: invalid_use_of_protected_member
part of 'smart_push_settings_page.dart';

extension _SmartPushSettingsPageMiscSections on _SmartPushSettingsPageState {
  Widget _buildTestButton(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return FilledButton.icon(
      onPressed: _isTesting ? null : _testPush,
      icon: _isTesting
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimary,
              ),
            )
          : const Icon(Icons.send),
      label: Text(_isTesting ? l10n.pleaseWait : l10n.smartPushTest),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildNoticeCard(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.smartPushNotice, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    l10n.smartPushNoticeDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods
  String _getFrequencyLabel(AppLocalizations l10n, PushFrequency freq) {
    switch (freq) {
      case PushFrequency.daily:
        return l10n.smartPushFrequencyDaily;
      case PushFrequency.weekdays:
        return l10n.smartPushFrequencyWeekdays;
      case PushFrequency.weekends:
        return l10n.smartPushFrequencyWeekends;
      case PushFrequency.custom:
        return l10n.smartPushFrequencyCustom;
    }
  }

  String _getWeekdayLabel(AppLocalizations l10n, int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return l10n.monday;
      case DateTime.tuesday:
        return l10n.tuesday;
      case DateTime.wednesday:
        return l10n.wednesday;
      case DateTime.thursday:
        return l10n.thursday;
      case DateTime.friday:
        return l10n.friday;
      case DateTime.saturday:
        return l10n.saturday;
      case DateTime.sunday:
        return l10n.sunday;
      default:
        return weekday.toString();
    }
  }

  IconData _getPastNoteTypeIcon(PastNoteType type) {
    switch (type) {
      case PastNoteType.yearAgoToday:
        return Icons.calendar_today;
      case PastNoteType.monthAgoToday:
        return Icons.date_range;
      case PastNoteType.weekAgoToday:
        return Icons.view_week;
      case PastNoteType.randomMemory:
        return Icons.shuffle;
      case PastNoteType.sameLocation:
        return Icons.place;
      case PastNoteType.sameWeather:
        return Icons.wb_sunny;
    }
  }

  String _getPastNoteTypeLabel(AppLocalizations l10n, PastNoteType type) {
    switch (type) {
      case PastNoteType.yearAgoToday:
        return l10n.smartPushYearAgoToday;
      case PastNoteType.monthAgoToday:
        return l10n.smartPushMonthAgoToday;
      case PastNoteType.weekAgoToday:
        return l10n.smartPushWeekAgoToday;
      case PastNoteType.randomMemory:
        return l10n.smartPushRandomMemory;
      case PastNoteType.sameLocation:
        return l10n.smartPushSameLocation;
      case PastNoteType.sameWeather:
        return l10n.smartPushSameWeather;
    }
  }

  String _getWeatherEmoji(WeatherFilterType weather) {
    switch (weather) {
      case WeatherFilterType.clear:
        return '☀️';
      case WeatherFilterType.cloudy:
        return '☁️';
      case WeatherFilterType.rain:
        return '🌧️';
      case WeatherFilterType.snow:
        return '❄️';
      case WeatherFilterType.fog:
        return '🌫️';
    }
  }

  String _getWeatherLabel(AppLocalizations l10n, WeatherFilterType weather) {
    switch (weather) {
      case WeatherFilterType.clear:
        return l10n.weatherClear;
      case WeatherFilterType.cloudy:
        return l10n.weatherCloudy;
      case WeatherFilterType.rain:
        return l10n.weatherRain;
      case WeatherFilterType.snow:
        return l10n.weatherSnow;
      case WeatherFilterType.fog:
        return l10n.weatherFog;
    }
  }

  Future<void> _editTimeSlot(int index, PushTimeSlot slot) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
    );
    if (time != null) {
      if (!mounted) return;
      final slots = List<PushTimeSlot>.from(_settings.pushTimeSlots);
      slots[index] = slot.copyWith(hour: time.hour, minute: time.minute);
      setState(() {
        _settings = _settings.copyWith(pushTimeSlots: slots);
      });
    }
  }

  Future<void> _addTimeSlot() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (time != null) {
      if (!mounted) return;
      final slots = List<PushTimeSlot>.from(_settings.pushTimeSlots);
      slots.add(PushTimeSlot(hour: time.hour, minute: time.minute));
      setState(() {
        _settings = _settings.copyWith(pushTimeSlots: slots);
      });
    }
  }

  Widget _buildDailyQuoteCard(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_quote_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.smartPushDailyQuote,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                Switch(
                  value: _settings.dailyQuotePushEnabled,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(
                        dailyQuotePushEnabled: value,
                      );
                    });
                  },
                ),
              ],
            ),
            if (_settings.dailyQuotePushEnabled) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: _editDailyQuoteTime,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.smartPushTimeSettings,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Row(
                        children: [
                          Text(
                            _settings.dailyQuotePushTime.formattedTime,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.smartPushDailyQuoteIndependentNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
