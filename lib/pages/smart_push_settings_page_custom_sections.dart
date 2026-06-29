// ignore_for_file: invalid_use_of_protected_member
part of 'smart_push_settings_page.dart';

extension _SmartPushSettingsPageCustomSections on _SmartPushSettingsPageState {
  /// 推送时间设置卡片
  Widget _buildTimeSettingsCard(
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
                Icon(Icons.schedule, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.smartPushTimeSettings,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._settings.pushTimeSlots.asMap().entries.map((entry) {
              final index = entry.key;
              final slot = entry.value;
              return _buildTimeSlotTile(l10n, theme, colorScheme, index, slot);
            }),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _addTimeSlot,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.smartPushAddTime),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSlotTile(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    int index,
    PushTimeSlot slot,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: slot.enabled
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: slot.enabled
                ? colorScheme.primary.withValues(alpha: 0.15)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              slot.periodDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: slot.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(
          slot.formattedTime,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        subtitle: slot.label != null
            ? Text(slot.label!, style: theme.textTheme.bodySmall)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: slot.enabled,
              onChanged: (value) {
                final slots = List<PushTimeSlot>.from(_settings.pushTimeSlots);
                slots[index] = slot.copyWith(enabled: value);
                setState(() {
                  _settings = _settings.copyWith(pushTimeSlots: slots);
                });
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.edit),
                    ],
                  ),
                ),
                if (_settings.pushTimeSlots.length > 1)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.delete,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ),
                  ),
              ],
              onSelected: (value) {
                if (value == 'edit') {
                  _editTimeSlot(index, slot);
                } else if (value == 'delete') {
                  final slots = List<PushTimeSlot>.from(
                    _settings.pushTimeSlots,
                  );
                  slots.removeAt(index);
                  setState(() {
                    _settings = _settings.copyWith(pushTimeSlots: slots);
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 推送频率卡片
  Widget _buildFrequencyCard(
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
                Icon(Icons.repeat, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.smartPushFrequency,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PushFrequency.values.map((freq) {
                final isSelected = _settings.frequency == freq;
                return ChoiceChip(
                  label: Text(_getFrequencyLabel(l10n, freq)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _settings = _settings.copyWith(frequency: freq);
                      });
                    }
                  },
                );
              }).toList(),
            ),
            if (_settings.frequency == PushFrequency.custom) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (index) {
                  final weekday = index + 1;
                  final isSelected = _settings.selectedWeekdays.contains(
                    weekday,
                  );
                  return FilterChip(
                    label: Text(_getWeekdayLabel(l10n, weekday)),
                    selected: isSelected,
                    onSelected: (selected) {
                      final weekdays = Set<int>.from(
                        _settings.selectedWeekdays,
                      );
                      if (selected) {
                        weekdays.add(weekday);
                      } else if (weekdays.length > 1) {
                        weekdays.remove(weekday);
                      }
                      setState(() {
                        _settings = _settings.copyWith(
                          selectedWeekdays: weekdays,
                        );
                      });
                    },
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 高级选项卡片
  Widget _buildAdvancedOptionsCard(
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
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () {
              setState(() {
                _settings = _settings.copyWith(
                  showAdvancedOptions: !_settings.showAdvancedOptions,
                );
              });
              if (_settings.showAdvancedOptions) {
                _animationController.forward();
              } else {
                _animationController.reverse();
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.tune, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.smartPushAdvancedOptions,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _settings.showAdvancedOptions ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),

                  // 回顾类型（仅在过去笔记模式下显示）
                  if (_settings.pushMode != PushMode.dailyQuote) ...[
                    Text(
                      l10n.smartPushPastNoteTypes,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PastNoteType.values.map((type) {
                        final isSelected =
                            _settings.enabledPastNoteTypes.contains(type);
                        return FilterChip(
                          avatar: Icon(_getPastNoteTypeIcon(type), size: 16),
                          label: Text(_getPastNoteTypeLabel(l10n, type)),
                          selected: isSelected,
                          onSelected: (selected) {
                            final types = Set<PastNoteType>.from(
                              _settings.enabledPastNoteTypes,
                            );
                            if (selected) {
                              types.add(type);
                            } else {
                              types.remove(type);
                            }
                            setState(() {
                              _settings = _settings.copyWith(
                                enabledPastNoteTypes: types,
                              );
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 天气筛选
                  if (_settings.enabledPastNoteTypes.contains(
                    PastNoteType.sameWeather,
                  )) ...[
                    Text(
                      l10n.smartPushWeatherFilter,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: WeatherFilterType.values.map((weather) {
                        final isSelected =
                            _settings.filterWeatherTypes.contains(weather);
                        return FilterChip(
                          avatar: Text(_getWeatherEmoji(weather)),
                          label: Text(_getWeatherLabel(l10n, weather)),
                          selected: isSelected,
                          onSelected: (selected) {
                            final types = Set<WeatherFilterType>.from(
                              _settings.filterWeatherTypes,
                            );
                            if (selected) {
                              types.add(weather);
                            } else {
                              types.remove(weather);
                            }
                            setState(() {
                              _settings = _settings.copyWith(
                                filterWeatherTypes: types,
                              );
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 标签筛选
                  Text(
                    l10n.smartPushTagFilter,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.smartPushTagFilterDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_availableTags.isEmpty)
                    Text(
                      l10n.noTagsAvailable,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableTags.map((tag) {
                        final isSelected = _settings.filterTagIds.contains(
                          tag.id,
                        );
                        return FilterChip(
                          avatar: tag.icon != null && tag.icon!.isNotEmpty
                              ? Text(
                                  tag.icon!,
                                  style: const TextStyle(fontSize: 14),
                                )
                              : null,
                          label: Text(tag.localizedName(l10n)),
                          selected: isSelected,
                          onSelected: (selected) {
                            final tagIds = List<String>.from(
                              _settings.filterTagIds,
                            );
                            if (selected) {
                              tagIds.add(tag.id);
                            } else {
                              tagIds.remove(tag.id);
                            }
                            setState(() {
                              _settings = _settings.copyWith(
                                filterTagIds: tagIds,
                              );
                            });
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
