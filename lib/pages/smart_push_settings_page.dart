import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/smart_push_settings.dart';
import '../models/note_category.dart';
import '../services/smart_push_service.dart';
import '../services/database_service.dart';
import '../constants/app_constants.dart';

/// 智能推送设置页面 (Preview)
class SmartPushSettingsPage extends StatefulWidget {
  const SmartPushSettingsPage({super.key});

  @override
  State<SmartPushSettingsPage> createState() => _SmartPushSettingsPageState();
}

class _SmartPushSettingsPageState extends State<SmartPushSettingsPage> {
  SmartPushSettings _settings = SmartPushSettings.defaultSettings();
  List<NoteCategory> _availableTags = [];
  bool _isLoading = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final smartPushService = context.read<SmartPushService>();
      final databaseService = context.read<DatabaseService>();

      // 加载标签列表
      final tags = await databaseService.getCategories();

      if (mounted) {
        setState(() {
          _settings = smartPushService.settings;
          _availableTags = tags;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).loadFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final smartPushService = context.read<SmartPushService>();
      await smartPushService.saveSettings(_settings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).settingsSaved),
            duration: AppConstants.snackBarDurationNormal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).saveFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  Future<void> _testPush() async {
    setState(() => _isTesting = true);
    try {
      final smartPushService = context.read<SmartPushService>();
      
      // 请求通知权限
      final hasPermission = await smartPushService.requestNotificationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).storagePermissionRequired),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
        return;
      }

      // 预览推送
      final previewNote = await smartPushService.previewPush();
      if (previewNote == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.smartPushNoMatchingNotes),
              duration: AppConstants.snackBarDurationNormal,
            ),
          );
        }
        return;
      }

      // 发送测试通知
      await smartPushService.triggerPush();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.smartPushTestSent),
            duration: AppConstants.snackBarDurationNormal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).testFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.smartPushTitle),
              const SizedBox(width: 8),
              _buildPreviewBadge(context),
            ],
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.smartPushTitle),
            const SizedBox(width: 8),
            _buildPreviewBadge(context),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: l10n.save,
          ),
        ],
      ),
      body: ListView(
        children: [
          // 启用开关
          SwitchListTile(
            title: Text(l10n.smartPushEnable),
            subtitle: Text(l10n.smartPushEnableDesc),
            value: _settings.enabled,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(enabled: value);
              });
            },
          ),

          if (_settings.enabled) ...[
            const Divider(),

            // 推送内容类型
            _buildSectionTitle(l10n.smartPushContentType),
            CheckboxListTile(
              title: Text(l10n.smartPushDailyQuote),
              subtitle: Text(l10n.smartPushDailyQuoteDesc),
              value: _settings.enabledContentTypes.contains(PushContentType.dailyQuote),
              onChanged: (value) {
                final types = Set<PushContentType>.from(_settings.enabledContentTypes);
                if (value == true) {
                  types.add(PushContentType.dailyQuote);
                } else {
                  types.remove(PushContentType.dailyQuote);
                }
                setState(() {
                  _settings = _settings.copyWith(enabledContentTypes: types);
                });
              },
            ),
            CheckboxListTile(
              title: Text(l10n.smartPushPastNotes),
              subtitle: Text(l10n.smartPushPastNotesDesc),
              value: _settings.enabledContentTypes.contains(PushContentType.pastNotes),
              onChanged: (value) {
                final types = Set<PushContentType>.from(_settings.enabledContentTypes);
                if (value == true) {
                  types.add(PushContentType.pastNotes);
                } else {
                  types.remove(PushContentType.pastNotes);
                }
                setState(() {
                  _settings = _settings.copyWith(enabledContentTypes: types);
                });
              },
            ),

            // 过去笔记类型
            if (_settings.enabledContentTypes.contains(PushContentType.pastNotes)) ...[
              const Divider(),
              _buildSectionTitle(l10n.smartPushPastNoteTypes),
              CheckboxListTile(
                title: Text(l10n.smartPushYearAgoToday),
                subtitle: Text(l10n.smartPushYearAgoTodayDesc),
                value: _settings.enabledPastNoteTypes.contains(PastNoteType.yearAgoToday),
                onChanged: (value) => _togglePastNoteType(PastNoteType.yearAgoToday, value),
              ),
              CheckboxListTile(
                title: Text(l10n.smartPushMonthAgoToday),
                subtitle: Text(l10n.smartPushMonthAgoTodayDesc),
                value: _settings.enabledPastNoteTypes.contains(PastNoteType.monthAgoToday),
                onChanged: (value) => _togglePastNoteType(PastNoteType.monthAgoToday, value),
              ),
              CheckboxListTile(
                title: Text(l10n.smartPushSameLocation),
                subtitle: Text(l10n.smartPushSameLocationDesc),
                value: _settings.enabledPastNoteTypes.contains(PastNoteType.sameLocation),
                onChanged: (value) => _togglePastNoteType(PastNoteType.sameLocation, value),
              ),
              CheckboxListTile(
                title: Text(l10n.smartPushSameWeather),
                subtitle: Text(l10n.smartPushSameWeatherDesc),
                value: _settings.enabledPastNoteTypes.contains(PastNoteType.sameWeather),
                onChanged: (value) => _togglePastNoteType(PastNoteType.sameWeather, value),
              ),
            ],

            // 天气筛选
            if (_settings.enabledPastNoteTypes.contains(PastNoteType.sameWeather)) ...[
              const Divider(),
              _buildSectionTitle(l10n.smartPushWeatherFilter),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WeatherFilterType.values.map((weather) {
                  final isSelected = _settings.filterWeatherTypes.contains(weather);
                  return FilterChip(
                    label: Text(_getWeatherLabel(l10n, weather)),
                    selected: isSelected,
                    onSelected: (selected) {
                      final types = Set<WeatherFilterType>.from(_settings.filterWeatherTypes);
                      if (selected) {
                        types.add(weather);
                      } else {
                        types.remove(weather);
                      }
                      setState(() {
                        _settings = _settings.copyWith(filterWeatherTypes: types);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 标签筛选
            const Divider(),
            _buildSectionTitle(l10n.smartPushTagFilter),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                l10n.smartPushTagFilterDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_availableTags.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  l10n.noTagsAvailable,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableTags.map((tag) {
                    final isSelected = _settings.filterTagIds.contains(tag.id);
                    return FilterChip(
                      avatar: tag.icon != null && tag.icon!.isNotEmpty
                          ? Text(tag.icon!, style: const TextStyle(fontSize: 14))
                          : null,
                      label: Text(tag.name),
                      selected: isSelected,
                      onSelected: (selected) {
                        final tagIds = List<String>.from(_settings.filterTagIds);
                        if (selected) {
                          tagIds.add(tag.id);
                        } else {
                          tagIds.remove(tag.id);
                        }
                        setState(() {
                          _settings = _settings.copyWith(filterTagIds: tagIds);
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 16),

            // 推送时间
            const Divider(),
            _buildSectionTitle(l10n.smartPushTimeSettings),
            ..._settings.pushTimeSlots.asMap().entries.map((entry) {
              final index = entry.key;
              final slot = entry.value;
              return ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(slot.formattedTime),
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
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _editTimeSlot(index, slot),
                    ),
                    if (_settings.pushTimeSlots.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          final slots = List<PushTimeSlot>.from(_settings.pushTimeSlots);
                          slots.removeAt(index);
                          setState(() {
                            _settings = _settings.copyWith(pushTimeSlots: slots);
                          });
                        },
                      ),
                  ],
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: OutlinedButton.icon(
                onPressed: _addTimeSlot,
                icon: const Icon(Icons.add),
                label: Text(l10n.smartPushAddTime),
              ),
            ),
            const SizedBox(height: 16),

            // AI智能推送（预留）
            const Divider(),
            _buildSectionTitle(l10n.smartPushAiSection),
            SwitchListTile(
              title: Row(
                children: [
                  Text(l10n.smartPushAiEnable),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.smartPushComingSoon,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(l10n.smartPushAiEnableDesc),
              value: _settings.aiPushEnabled,
              onChanged: null, // 暂时禁用
            ),

            const SizedBox(height: 24),

            // 测试按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton.icon(
                onPressed: _isTesting ? null : _testPush,
                icon: _isTesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active),
                label: Text(_isTesting ? l10n.pleaseWait : l10n.smartPushTest),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],

          // 说明
          Card(
            margin: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.smartPushNotice,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.smartPushNoticeDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBadge(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.tertiary.withOpacity(0.5)),
      ),
      child: Text(
        'Preview',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.tertiary,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  void _togglePastNoteType(PastNoteType type, bool? value) {
    final types = Set<PastNoteType>.from(_settings.enabledPastNoteTypes);
    if (value == true) {
      types.add(type);
    } else {
      types.remove(type);
    }
    setState(() {
      _settings = _settings.copyWith(enabledPastNoteTypes: types);
    });
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
      final slots = List<PushTimeSlot>.from(_settings.pushTimeSlots);
      slots.add(PushTimeSlot(hour: time.hour, minute: time.minute));
      setState(() {
        _settings = _settings.copyWith(pushTimeSlots: slots);
      });
    }
  }
}
