import 'package:flutter/material.dart';
import '../models/note_category.dart';
import '../utils/icon_utils.dart'; // Import IconUtils
import '../services/weather_service.dart'; // Import WeatherService
import '../utils/time_utils.dart'; // Import TimeUtils

class NoteFilterSortSheet extends StatefulWidget {
  final List<NoteCategory> allTags;
  final List<String> selectedTagIds;
  final String sortType;
  final bool sortAscending;
  final List<String>? selectedWeathers;
  final List<String>? selectedDayPeriods;
  final void Function(
    List<String> tagIds,
    String sortType,
    bool sortAscending,
    List<String> selectedWeathers,
    List<String> selectedDayPeriods,
  )
  onApply;

  const NoteFilterSortSheet({
    super.key,
    required this.allTags,
    required this.selectedTagIds,
    required this.sortType,
    required this.sortAscending,
    this.selectedWeathers,
    this.selectedDayPeriods,
    required this.onApply,
  });

  @override
  State<NoteFilterSortSheet> createState() => _NoteFilterSortSheetState();
}

class _NoteFilterSortSheetState extends State<NoteFilterSortSheet> {
  static const Map<String, String> _sortTypeKeyToLabel = {
    'time': '按时间排序',
    'name': '按名称排序',
  };

  late List<String> _tempSelectedTagIds;
  late String _tempSortType;
  late bool _tempSortAscending;
  late List<String> _tempSelectedWeathers;
  late List<String> _tempSelectedDayPeriods;

  @override
  void initState() {
    super.initState();
    _tempSelectedTagIds = List.from(widget.selectedTagIds);
    _tempSortType = widget.sortType;
    _tempSortAscending = widget.sortAscending;
    _tempSelectedWeathers =
        widget.selectedWeathers != null
            ? List.from(widget.selectedWeathers!)
            : <String>[];
    _tempSelectedDayPeriods =
        widget.selectedDayPeriods != null
            ? List.from(widget.selectedDayPeriods!)
            : <String>[];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    return Padding(
      padding: MediaQuery.of(context).viewInsets.add(const EdgeInsets.all(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '筛选与排序',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text('标签筛选', style: theme.textTheme.bodyLarge),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children:
                    widget.allTags.map((tag) {
                      final isSelected = _tempSelectedTagIds.contains(tag.id);
                      // Use IconUtils to get the icon
                      final bool isEmoji = IconUtils.isEmoji(tag.iconName);
                      final dynamic tagIcon = IconUtils.getIconData(
                        tag.iconName,
                      ); // getIconData handles null/empty and returns default

                      return FilterChip(
                        selected: isSelected,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (tag.iconName != null &&
                                tag.iconName!.isNotEmpty)
                              isEmoji
                                  ? Text(
                                    tag.iconName!,
                                    style: const TextStyle(fontSize: 16),
                                  )
                                  // Use the IconData from IconUtils
                                  : (tagIcon
                                      is IconData) // Check if it's IconData
                                  ? Icon(tagIcon, size: 16)
                                  : const SizedBox.shrink(), // Fallback if not IconData (though getIconData should return a default)
                            if (tag.iconName != null &&
                                tag.iconName!.isNotEmpty)
                              const SizedBox(width: 4),
                            Text(tag.name, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _tempSelectedTagIds.add(tag.id);
                            } else {
                              _tempSelectedTagIds.remove(tag.id);
                            }
                          });
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 20),
              Text('天气筛选', style: theme.textTheme.bodyLarge),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  ...WeatherService.weatherKeyToLabel.keys
                      .where((key) => key != 'unknown')
                      .map((weatherKey) {
                        final isSelected = _tempSelectedWeathers.contains(
                          weatherKey,
                        );
                        final icon = WeatherService.getWeatherIconDataByKey(
                          weatherKey,
                        );
                        return FilterChip(
                          selected: isSelected,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                WeatherService.getWeatherDescription(
                                  weatherKey,
                                ),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _tempSelectedWeathers.add(weatherKey);
                              } else {
                                _tempSelectedWeathers.remove(weatherKey);
                              }
                            });
                          },
                        );
                      }),
                ],
              ),
              const SizedBox(height: 20),
              Text('时间段筛选', style: theme.textTheme.bodyLarge),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  ...TimeUtils.dayPeriodKeyToLabel.keys.map((periodKey) {
                    final isSelected = _tempSelectedDayPeriods.contains(
                      periodKey,
                    );
                    final icon = TimeUtils.getDayPeriodIconByKey(periodKey);
                    return FilterChip(
                      selected: isSelected,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            TimeUtils.getDayPeriodLabel(periodKey),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _tempSelectedDayPeriods.add(periodKey);
                          } else {
                            _tempSelectedDayPeriods.remove(periodKey);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
              const SizedBox(height: 24),
              Text('排序方式', style: theme.textTheme.bodyLarge),
              ..._sortTypeKeyToLabel.entries.map(
                (entry) => RadioListTile<String>(
                  title: Text(entry.value),
                  value: entry.key,
                  groupValue: _tempSortType,
                  onChanged: (value) {
                    setState(() {
                      _tempSortType = value!;
                    });
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('升序'),
                value: _tempSortAscending,
                onChanged: (value) {
                  setState(() {
                    _tempSortAscending = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        _tempSelectedTagIds.clear();
                        _tempSortType = 'time';
                        _tempSortAscending = false;
                        _tempSelectedWeathers.clear();
                        _tempSelectedDayPeriods.clear();
                      });
                    },
                    child: const Text('重置'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      widget.onApply(
                        _tempSelectedTagIds,
                        _tempSortType,
                        _tempSortAscending,
                        _tempSelectedWeathers,
                        _tempSelectedDayPeriods,
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('应用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
