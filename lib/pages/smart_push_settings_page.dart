import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/smart_push_settings.dart';
import '../models/note_category.dart';
import '../services/smart_push_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../constants/app_constants.dart';

/// 智能推送设置页面
/// 重构版：简洁现代的UI设计，智能推送为默认模式
class SmartPushSettingsPage extends StatefulWidget {
  const SmartPushSettingsPage({super.key});

  @override
  State<SmartPushSettingsPage> createState() => _SmartPushSettingsPageState();
}

class _SmartPushSettingsPageState extends State<SmartPushSettingsPage>
    with SingleTickerProviderStateMixin {
  SmartPushSettings _settings = SmartPushSettings.defaultSettings();
  List<NoteCategory> _availableTags = [];
  bool _isLoading = true;
  bool _isTesting = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final smartPushService = context.read<SmartPushService>();
      final databaseService = context.read<DatabaseService>();

      final tags = await databaseService.getCategories();

      if (mounted) {
        setState(() {
          _settings = smartPushService.settings;
          _availableTags = tags;
          _isLoading = false;
        });
        if (_settings.showAdvancedOptions) {
          _animationController.forward();
        }

        // 检查是否有精确闹钟权限（如果已启用功能但缺少权限）
        // 延迟执行以确保页面已构建完成
        if ((_settings.enabled || _settings.dailyQuotePushEnabled) && mounted) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _checkPermissionAndShowDialog();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).loadFailed(e.toString())),
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).saveFailed(e.toString())),
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

      final hasPermission =
          await smartPushService.requestNotificationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).smartPushPermissionRequired),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
        return;
      }

      final previewNote = await smartPushService.previewPush();
      if (previewNote == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(AppLocalizations.of(context).smartPushNoMatchingNotes),
              duration: AppConstants.snackBarDurationNormal,
            ),
          );
        }
        return;
      }

      await smartPushService.triggerPush();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).smartPushTestSent),
            duration: AppConstants.snackBarDurationNormal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).testFailed(e.toString())),
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

  Future<void> _checkPermissionAndShowDialog() async {
    if (!mounted) return;
    try {
      final smartPushService = context.read<SmartPushService>();
      final hasExactAlarmPermission =
          await smartPushService.checkExactAlarmPermission();

      if (!hasExactAlarmPermission && mounted) {
        // 直接申请精确闹钟权限（无需询问）
        final granted = await smartPushService.requestExactAlarmPermission();
        if (!granted && mounted) {
          final l10n = AppLocalizations.of(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.exactAlarmDeniedHint),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        // 刷新页面状态以更新警告卡片
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      // 忽略检查错误
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.smartPushTitle),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.smartPushTitle),
        actions: [
          TextButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.check),
            label: Text(l10n.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 主开关卡片
          _buildMainSwitchCard(l10n, theme, colorScheme),

          if (_settings.enabled) ...[
            const SizedBox(height: 16),

            // 推送模式选择（只显示 智能/自定义 两个选项）
            _buildModeSelectionCard(l10n, theme, colorScheme),

            const SizedBox(height: 16),

            // 每日一言独立推送（始终显示，不依赖推送模式）
            _buildDailyQuoteCard(l10n, theme, colorScheme),

            // 权限状态卡片（检测所有必需权限）
            _buildPermissionStatusCard(l10n, theme, colorScheme),

            // 自定义模式：显示完整高级选项
            if (_settings.pushMode == PushMode.custom) ...[
              const SizedBox(height: 16),

              // 推送时间设置
              _buildTimeSettingsCard(l10n, theme, colorScheme),

              const SizedBox(height: 16),

              // 推送频率
              _buildFrequencyCard(l10n, theme, colorScheme),

              const SizedBox(height: 16),

              // 高级选项（回顾类型、天气筛选、标签筛选）
              _buildAdvancedOptionsCard(l10n, theme, colorScheme),
            ],

            const SizedBox(height: 24),

            // 测试推送按钮 - 仅在开发者模式显示
            Consumer<SettingsService>(
              builder: (context, settingsService, _) {
                if (!settingsService.appSettings.developerMode) {
                  return const SizedBox.shrink();
                }
                return _buildTestButton(l10n, theme, colorScheme);
              },
            ),

            const SizedBox(height: 16),

            // 说明卡片
            _buildNoticeCard(l10n, theme, colorScheme),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 主开关卡片
  Widget _buildMainSwitchCard(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _settings.enabled
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      color: _settings.enabled
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _settings.enabled
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _settings.enabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: _settings.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.smartPushEnable,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.smartPushEnableDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _settings.enabled,
              onChanged: (value) async {
                if (value) {
                  // 开启时请求权限
                  final smartPushService = context.read<SmartPushService>();

                  // 1. 请求通知权限
                  final hasNotificationPermission =
                      await smartPushService.requestNotificationPermission();
                  if (!hasNotificationPermission) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.smartPushPermissionRequired),
                        backgroundColor: colorScheme.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  // 2. 检查精确闹钟权限 (Android 12+)
                  final hasExactAlarmPermission =
                      await smartPushService.checkExactAlarmPermission();
                  if (!hasExactAlarmPermission) {
                    if (!context.mounted) return;
                    // 直接申请精确闹钟权限（无需询问）
                    final granted =
                        await smartPushService.requestExactAlarmPermission();
                    if (!granted && context.mounted) {
                      // 显示降级提示
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context)
                              .exactAlarmDeniedHint),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                }

                if (!context.mounted) return;
                setState(() {
                  _settings = _settings.copyWith(enabled: value);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 推送模式选择卡片 - 简化为智能/自定义两个选项
  Widget _buildModeSelectionCard(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
    // 将非 smart/custom 模式映射到 custom（兼容旧数据）
    final effectiveMode = (_settings.pushMode == PushMode.smart)
        ? PushMode.smart
        : PushMode.custom;

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
                Icon(Icons.category_outlined,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.smartPushContentType,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 智能推送选项
            _buildSimpleModeOption(
              theme,
              colorScheme,
              isSelected: effectiveMode == PushMode.smart,
              icon: Icons.auto_awesome,
              title: l10n.smartPushModeSmart,
              subtitle: l10n.smartPushModeSmartDesc,
              isRecommended: true,
              onTap: () {
                setState(() {
                  _settings = _settings.copyWith(
                    pushMode: PushMode.smart,
                    showAdvancedOptions: false,
                  );
                  _animationController.reverse();
                });
              },
            ),
            const SizedBox(height: 8),
            // 自定义推送选项
            _buildSimpleModeOption(
              theme,
              colorScheme,
              isSelected: effectiveMode == PushMode.custom,
              icon: Icons.tune,
              title: l10n.smartPushModeCustom,
              subtitle: l10n.smartPushModeCustomDesc,
              onTap: () {
                setState(() {
                  _settings = _settings.copyWith(pushMode: PushMode.custom);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 简化的模式选项组件
  Widget _buildSimpleModeOption(
    ThemeData theme,
    ColorScheme colorScheme, {
    required bool isSelected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              AppLocalizations.of(context).recommended,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 推送时间设置卡片
  Widget _buildTimeSettingsCard(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
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
                    fontWeight: FontWeight.w600,
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
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        title: Text(
          slot.formattedTime,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
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
                        Icon(Icons.delete_outline,
                            size: 20, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Text(l10n.delete,
                            style: TextStyle(color: colorScheme.error)),
                      ],
                    ),
                  ),
              ],
              onSelected: (value) {
                if (value == 'edit') {
                  _editTimeSlot(index, slot);
                } else if (value == 'delete') {
                  final slots =
                      List<PushTimeSlot>.from(_settings.pushTimeSlots);
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
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
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
                    fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }

  /// 高级选项卡片
  Widget _buildAdvancedOptionsCard(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
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
                      fontWeight: FontWeight.w600,
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PastNoteType.values.map((type) {
                        final isSelected =
                            _settings.enabledPastNoteTypes.contains(type);
                        return FilterChip(
                          avatar: Icon(
                            _getPastNoteTypeIcon(type),
                            size: 16,
                          ),
                          label: Text(_getPastNoteTypeLabel(l10n, type)),
                          selected: isSelected,
                          onSelected: (selected) {
                            final types = Set<PastNoteType>.from(
                                _settings.enabledPastNoteTypes);
                            if (selected) {
                              types.add(type);
                            } else {
                              types.remove(type);
                            }
                            setState(() {
                              _settings = _settings.copyWith(
                                  enabledPastNoteTypes: types);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 天气筛选
                  if (_settings.enabledPastNoteTypes
                      .contains(PastNoteType.sameWeather)) ...[
                    Text(
                      l10n.smartPushWeatherFilter,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
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
                                _settings.filterWeatherTypes);
                            if (selected) {
                              types.add(weather);
                            } else {
                              types.remove(weather);
                            }
                            setState(() {
                              _settings =
                                  _settings.copyWith(filterWeatherTypes: types);
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
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
                        final isSelected =
                            _settings.filterTagIds.contains(tag.id);
                        return FilterChip(
                          avatar: tag.icon != null && tag.icon!.isNotEmpty
                              ? Text(tag.icon!,
                                  style: const TextStyle(fontSize: 14))
                              : null,
                          label: Text(tag.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            final tagIds =
                                List<String>.from(_settings.filterTagIds);
                            if (selected) {
                              tagIds.add(tag.id);
                            } else {
                              tagIds.remove(tag.id);
                            }
                            setState(() {
                              _settings =
                                  _settings.copyWith(filterTagIds: tagIds);
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

  /// 测试按钮
  Widget _buildTestButton(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// 说明卡片
  Widget _buildNoticeCard(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.smartPushNotice,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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

  /// 每日一言独立推送卡片
  Widget _buildDailyQuoteCard(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
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
                Icon(Icons.format_quote_outlined,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.smartPushDailyQuote,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                Switch(
                  value: _settings.dailyQuotePushEnabled,
                  onChanged: (value) {
                    setState(() {
                      _settings =
                          _settings.copyWith(dailyQuotePushEnabled: value);
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.1)),
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
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.edit_outlined,
                              size: 16, color: colorScheme.primary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 权限状态卡片
  ///
  /// 显示所有推送相关权限的状态，并提供快捷修复入口
  Widget _buildPermissionStatusCard(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
    // 只有在启用了任何推送功能时才显示权限检查
    if (!_settings.enabled && !_settings.dailyQuotePushEnabled) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<PushPermissionStatus>(
      future: context.read<SmartPushService>().getPushPermissionStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final status = snapshot.data!;

        // 如果所有权限都已授予，则不显示警告卡片
        // 注意：allPermissionsGranted 已包含自启动权限的判断
        if (status.allPermissionsGranted) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Card(
            elevation: 0,
            color: colorScheme.errorContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: colorScheme.error, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.smartPushPermissionWarningTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.smartPushPermissionWarningDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          colorScheme.onErrorContainer.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 通知权限
                  _buildPermissionItem(
                    icon: Icons.notifications_outlined,
                    title: l10n.smartPushNotificationPermission,
                    isGranted: status.notificationEnabled,
                    onTap: status.notificationEnabled
                        ? null
                        : () async {
                            final smartPushService =
                                context.read<SmartPushService>();
                            await smartPushService
                                .requestNotificationPermission();
                            setState(() {});
                          },
                    theme: theme,
                    colorScheme: colorScheme,
                  ),

                  // 精确闹钟权限 (Android 12+)
                  if (status.sdkVersion >= 31)
                    _buildPermissionItem(
                      icon: Icons.alarm_outlined,
                      title: l10n.smartPushExactAlarmTitle,
                      isGranted: status.exactAlarmEnabled,
                      onTap: status.exactAlarmEnabled
                          ? null
                          : () async {
                              final smartPushService =
                                  context.read<SmartPushService>();
                              await smartPushService
                                  .requestExactAlarmPermission();
                              setState(() {});
                            },
                      theme: theme,
                      colorScheme: colorScheme,
                    ),

                  // 电池优化豁免
                  _buildPermissionItem(
                    icon: Icons.battery_saver_outlined,
                    title: l10n.smartPushBatteryOptimization,
                    isGranted: status.batteryOptimizationExempted,
                    onTap: status.batteryOptimizationExempted
                        ? null
                        : () async {
                            final smartPushService =
                                context.read<SmartPushService>();
                            await smartPushService
                                .requestBatteryOptimizationExemption();
                            setState(() {});
                          },
                    theme: theme,
                    colorScheme: colorScheme,
                  ),

                  // 自启动权限（如果是需要的厂商）
                  if (status.needsAutoStartPermission)
                    _buildAutoStartItem(
                      smartPushService: context.read<SmartPushService>(),
                      manufacturer: status.manufacturer,
                      isGranted: status.autoStartGranted,
                      l10n: l10n,
                      theme: theme,
                      colorScheme: colorScheme,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建单个权限项
  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required bool isGranted,
    required VoidCallback? onTap,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(
                isGranted ? Icons.check_circle : icon,
                size: 20,
                color: isGranted ? Colors.green : colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    decoration: isGranted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (!isGranted)
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colorScheme.error,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 自启动权限项（带厂商特定指引）
  Widget _buildAutoStartItem({
    required SmartPushService smartPushService,
    required String manufacturer,
    required bool isGranted,
    required AppLocalizations l10n,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final instructions =
        smartPushService.getAutoStartInstructions(manufacturer);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          _showAutoStartInstructionsDialog(
            manufacturer: manufacturer,
            instructions: instructions,
            l10n: l10n,
            theme: theme,
            colorScheme: colorScheme,
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(
                isGranted ? Icons.check_circle : Icons.rocket_launch_outlined,
                size: 20,
                color: isGranted ? Colors.green : colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.smartPushAutoStartPermission,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                        decoration:
                            isGranted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      l10n.smartPushAutoStartHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            colorScheme.onErrorContainer.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isGranted ? Icons.chevron_right : Icons.help_outline,
                size: 20,
                color: isGranted
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : colorScheme.error,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示自启动设置指引对话框
  void _showAutoStartInstructionsDialog({
    required String manufacturer,
    required String instructions,
    required AppLocalizations l10n,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final displayManufacturer = manufacturer.isNotEmpty
        ? manufacturer.toUpperCase()
        : l10n.smartPushUnknownManufacturer;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.rocket_launch_outlined, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.smartPushAutoStartTitle)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                displayManufacturer,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.smartPushAutoStartInstructions,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                instructions,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.smartPushAutoStartNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final smartPushService =
                  Provider.of<SmartPushService>(context, listen: false);
              await smartPushService.setAutoStartGranted(true);
              if (mounted) {
                Navigator.of(context).pop();
                // 刷新状态
                setState(() {});
              }
            },
            child: Text(l10n.iHaveConfigured),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _editDailyQuoteTime() async {
    final slot = _settings.dailyQuotePushTime;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
    );
    if (time != null) {
      setState(() {
        _settings = _settings.copyWith(
          dailyQuotePushTime:
              slot.copyWith(hour: time.hour, minute: time.minute),
        );
      });
    }
  }
}
