import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../models/onboarding_models.dart';
import '../../config/onboarding_config.dart';
import '../../services/location_service.dart';

/// 偏好设置页面组件
class PreferencesPageView extends StatefulWidget {
  final OnboardingPageData pageData;
  final OnboardingState state;
  final Function(String key, dynamic value) onPreferenceChanged;

  const PreferencesPageView({
    super.key,
    required this.pageData,
    required this.state,
    required this.onPreferenceChanged,
  });

  @override
  State<PreferencesPageView> createState() => _PreferencesPageViewState();
}

class _PreferencesPageViewState extends State<PreferencesPageView>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Animation<double>> _itemAnimations;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Fixed count of 4 preferences (language, hitokoto types, location, start page)
    const preferencesCount = 4;
    _itemAnimations = List.generate(preferencesCount, (index) {
      // Calculate intervals that ensure end values don't exceed 1.0
      final startDelay = index * 0.1;
      const animationDuration = 0.4; // Fixed duration for each animation
      final endTime = (startDelay + animationDuration).clamp(0.0, 1.0);

      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(startDelay, endTime, curve: Curves.easeOutCubic),
        ),
      );
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 页面标题
          Text(
            widget.pageData.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.pageData.subtitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),

          if (widget.pageData.description != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.pageData.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // 偏好设置列表（使用动态国际化版本）
          ...OnboardingConfig.getPreferences(context).asMap().entries.map((
            entry,
          ) {
            final index = entry.key;
            final preference = entry.value;

            return AnimatedBuilder(
              animation: _itemAnimations[index],
              builder: (context, child) {
                // Clamp animation values to valid ranges
                final animationValue = _itemAnimations[index].value;
                final clampedOpacity = animationValue.clamp(0.0, 1.0);
                final clampedScale = animationValue.clamp(0.0, double.infinity);

                return Transform.scale(
                  scale: clampedScale,
                  child: Opacity(
                    opacity: clampedOpacity,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      child: _buildPreferenceItem(preference, theme),
                    ),
                  ),
                );
              },
            );
          }),

          const SizedBox(height: 24),

          // 说明信息
          _buildInfoCard(theme),

          // 新增：引导用户前往偏好设置查看更多
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Card(
              color: theme.colorScheme.surfaceContainerHighest,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).prefMoreOptionsHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceItem(
    OnboardingPreference<dynamic> preference,
    ThemeData theme,
  ) {
    switch (preference.type) {
      case OnboardingPreferenceType.toggle:
        return _buildTogglePreference(preference, theme);
      case OnboardingPreferenceType.radio:
        return _buildRadioPreference(preference, theme);
      case OnboardingPreferenceType.multiSelect:
        return _buildMultiSelectPreference(preference, theme);
    }
  }

  Widget _buildTogglePreference(
    OnboardingPreference<dynamic> preference,
    ThemeData theme,
  ) {
    final value =
        widget.state.getPreference<bool>(preference.key) ??
        preference.defaultValue as bool;

    return Card(
      elevation: 2,
      child: SwitchListTile(
        value: value,
        onChanged: (newValue) async {
          // 如果是位置服务，需要特殊处理权限申请
          if (preference.key == 'locationService' && newValue) {
            final locationService = Provider.of<LocationService>(
              context,
              listen: false,
            );

            // 请求位置权限
            final hasPermission = await locationService
                .requestLocationPermission();
            if (!hasPermission) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('位置权限被拒绝，无法启用位置服务'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
              return; // 不更新状态
            }

            // 检查位置服务是否启用
            final serviceEnabled = await Geolocator.isLocationServiceEnabled();
            if (!serviceEnabled) {
              if (mounted) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      AppLocalizations.of(context).locationServiceNotEnabled,
                    ),
                    content: Text(
                      AppLocalizations.of(
                        context,
                      ).pleaseEnableLocationInSettings,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(AppLocalizations.of(context).cancel),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Geolocator.openLocationSettings();
                        },
                        child: Text(AppLocalizations.of(context).goToSettings),
                      ),
                    ],
                  ),
                );
              }
              return; // 不更新状态
            }

            // 获取当前位置
            final position = await locationService.getCurrentLocation();
            if (position != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).locationServiceEnabledMsg,
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }

          widget.onPreferenceChanged(preference.key, newValue);
        },
        title: Text(
          preference.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            preference.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        activeThumbColor: theme.colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
    );
  }

  Widget _buildRadioPreference(
    OnboardingPreference<dynamic> preference,
    ThemeData theme,
  ) {
    final options = preference.options ?? [];

    // 根据默认值类型判断是 int 还是 String
    if (preference.defaultValue is int) {
      final value =
          widget.state.getPreference<int>(preference.key) ??
          preference.defaultValue as int;
      return _buildRadioPreferenceInt(preference, theme, value, options);
    } else {
      // String 类型的 radio（例如语言选择）
      final value =
          widget.state.getPreference<String>(preference.key) ??
          preference.defaultValue as String;
      return _buildRadioPreferenceString(preference, theme, value, options);
    }
  }

  Widget _buildRadioPreferenceInt(
    OnboardingPreference<dynamic> preference,
    ThemeData theme,
    int value,
    List<OnboardingPreferenceOption<dynamic>> options,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preference.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preference.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            RadioGroup<int>(
              groupValue: value,
              onChanged: (newValue) {
                if (newValue != null) {
                  widget.onPreferenceChanged(preference.key, newValue);
                }
              },
              child: Column(
                children: options.map((option) {
                  return RadioListTile<int>(
                    value: option.value as int,
                    title: Text(option.label),
                    subtitle: option.description != null
                        ? Text(
                            option.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    activeColor: theme.colorScheme.primary,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioPreferenceString(
    OnboardingPreference<dynamic> preference,
    ThemeData theme,
    String value,
    List<OnboardingPreferenceOption<dynamic>> options,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preference.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preference.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: value,
              onChanged: (newValue) {
                if (newValue != null) {
                  widget.onPreferenceChanged(preference.key, newValue);
                }
              },
              child: Column(
                children: options.map((option) {
                  return RadioListTile<String>(
                    value: option.value as String,
                    title: Text(option.label),
                    subtitle: option.description != null
                        ? Text(
                            option.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    activeColor: theme.colorScheme.primary,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiSelectPreference(
    OnboardingPreference<dynamic> preference,
    ThemeData theme,
  ) {
    final value =
        widget.state.getPreference<String>(preference.key) ??
        preference.defaultValue as String;
    final selectedValues = value.split(',').where((v) => v.isNotEmpty).toSet();
    final options = preference.options ?? [];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preference.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preference.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),

            // 快速操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final allValues = options
                          .map((o) => o.value as String)
                          .join(',');
                      widget.onPreferenceChanged(preference.key, allValues);
                    },
                    icon: const Icon(Icons.select_all, size: 16),
                    label: Text(AppLocalizations.of(context).prefSelectAll),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // 至少保留一个选项
                      final firstValue = options.isNotEmpty
                          ? options.first.value as String
                          : '';
                      widget.onPreferenceChanged(preference.key, firstValue);
                    },
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: Text(AppLocalizations.of(context).prefClearAll),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 选项网格
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((option) {
                final isSelected = selectedValues.contains(
                  option.value as String,
                );
                return FilterChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    final newSelectedValues = Set<String>.from(selectedValues);
                    if (selected) {
                      newSelectedValues.add(option.value as String);
                    } else {
                      newSelectedValues.remove(option.value as String);
                      // 确保至少有一个选项被选中
                      if (newSelectedValues.isEmpty && options.isNotEmpty) {
                        newSelectedValues.add(options.first.value as String);
                      }
                    }
                    widget.onPreferenceChanged(
                      preference.key,
                      newSelectedValues.join(','),
                    );
                  },
                  selectedColor: theme.colorScheme.primaryContainer,
                  checkmarkColor: theme.colorScheme.primary,
                  backgroundColor: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.8,
                        ),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.5),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  elevation: isSelected ? 2 : 1,
                  shadowColor: theme.shadowColor.withValues(alpha: 0.2),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).prefAboutSettings,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context).prefAboutSettingsInfo,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
