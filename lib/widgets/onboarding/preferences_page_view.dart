import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/onboarding_config.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../models/onboarding_models.dart';
import '../../services/location_service.dart';
import '../app_snackbar.dart';
import '../../theme/theme_style.dart';
import 'onboarding_section.dart';

/// 第 3 屏：使用习惯、隐私开关，以及 AI 的说明。
///
/// 这一屏只放「必须由用户本人决定」的事：启动页是习惯，位置和诊断上报是隐私，
/// 两者都不适合替用户默认。AI 只做说明加一个可选跳转——首次启动就要求填 API Key
/// 会把没有 Key 的人直接堵在门口。
class PreferencesPageView extends StatelessWidget {
  const PreferencesPageView({
    super.key,
    required this.pageData,
    required this.state,
    required this.onPreferenceChanged,
  });

  final OnboardingPageData pageData;
  final OnboardingState state;
  final void Function(String key, dynamic value) onPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    return OnboardingPageScaffold(
      title: pageData.title,
      subtitle: pageData.subtitle,
      description: pageData.description,
      children: [
        _StartPageSection(
          state: state,
          onPreferenceChanged: onPreferenceChanged,
        ),
        _LocationSection(
          state: state,
          onPreferenceChanged: onPreferenceChanged,
        ),
        _SentrySection(
          state: state,
          onPreferenceChanged: onPreferenceChanged,
        ),
        _AiSection(
          state: state,
          onPreferenceChanged: onPreferenceChanged,
        ),
      ],
    );
  }
}

/// 默认启动页。
class _StartPageSection extends StatelessWidget {
  const _StartPageSection({
    required this.state,
    required this.onPreferenceChanged,
  });

  final OnboardingState state;
  final void Function(String key, dynamic value) onPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final preference =
        OnboardingConfig.preferenceByKey(context, 'defaultStartPage');
    if (preference == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final value = state.getPreference<int>('defaultStartPage') ??
        preference.defaultValue as int;

    return OnboardingSection(
      icon: Icons.home_outlined,
      title: preference.title,
      description: preference.description,
      child: RadioGroup<int>(
        groupValue: value,
        onChanged: (newValue) {
          if (newValue != null) {
            onPreferenceChanged('defaultStartPage', newValue);
          }
        },
        child: Column(
          children: [
            for (final option in preference.options ?? [])
              RadioListTile<int>(
                value: option.value as int,
                title: Text(option.label),
                subtitle: option.description != null
                    ? Text(
                        option.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

/// 位置服务。开启要走系统权限，任何一步没通过都不能把开关拨到「开」——
/// 否则设置里显示已开启、实际拿不到位置，用户无从排查。
class _LocationSection extends StatelessWidget {
  const _LocationSection({
    required this.state,
    required this.onPreferenceChanged,
  });

  final OnboardingState state;
  final void Function(String key, dynamic value) onPreferenceChanged;

  Future<void> _enableLocation(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final locationService = context.read<LocationService>();

    final hasPermission = await locationService.requestLocationPermission();
    if (!context.mounted) return;
    if (!hasPermission) {
      AppSnackBar.warning(context, l10n.locationPermissionDenied);
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.locationServiceNotEnabled),
          content: Text(l10n.pleaseEnableLocationInSettings),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Geolocator.openLocationSettings();
              },
              child: Text(l10n.goToSettings),
            ),
          ],
        ),
      );
      return;
    }

    final position = await locationService.getCurrentLocation();
    if (!context.mounted) return;
    if (position != null) {
      AppSnackBar.success(context, l10n.locationServiceEnabledMsg);
    }

    onPreferenceChanged('locationService', true);
  }

  @override
  Widget build(BuildContext context) {
    final preference =
        OnboardingConfig.preferenceByKey(context, 'locationService');
    if (preference == null) return const SizedBox.shrink();

    final value = state.getPreference<bool>('locationService') ??
        preference.defaultValue as bool;

    return OnboardingSection(
      icon: Icons.place_outlined,
      title: preference.title,
      description: preference.description,
      trailing: Switch(
        value: value,
        onChanged: (newValue) {
          if (newValue) {
            _enableLocation(context);
          } else {
            onPreferenceChanged('locationService', false);
          }
        },
      ),
    );
  }
}

/// 诊断数据上报。
class _SentrySection extends StatelessWidget {
  const _SentrySection({
    required this.state,
    required this.onPreferenceChanged,
  });

  final OnboardingState state;
  final void Function(String key, dynamic value) onPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final preference =
        OnboardingConfig.preferenceByKey(context, 'sentryEnabled');
    if (preference == null) return const SizedBox.shrink();

    final value = state.getPreference<bool>('sentryEnabled') ??
        preference.defaultValue as bool;

    return OnboardingSection(
      icon: Icons.bug_report_outlined,
      title: preference.title,
      description: preference.description,
      trailing: Switch(
        value: value,
        onChanged: (newValue) => onPreferenceChanged('sentryEnabled', newValue),
      ),
    );
  }
}

/// AI 说明卡。只解释 AI 能做什么、需要自备服务，并提供一个「完成后带我去配置」的开关；
/// 引导过程中不跳出去，跳出去就回不到这一屏了。
class _AiSection extends StatelessWidget {
  const _AiSection({
    required this.state,
    required this.onPreferenceChanged,
  });

  final OnboardingState state;
  final void Function(String key, dynamic value) onPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final checked = state.getPreference<bool>('openAiSettingsAfter') ?? false;

    return OnboardingSection(
      icon: Icons.auto_awesome_outlined,
      title: l10n.onboardingAiTitle,
      description: l10n.onboardingAiDesc,
      child: Material(
        color: checked
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(shape.buttonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
          onTap: () => onPreferenceChanged('openAiSettingsAfter', !checked),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Checkbox(
                  value: checked,
                  onChanged: (value) => onPreferenceChanged(
                      'openAiSettingsAfter', value ?? false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.onboardingAiOpenAfter,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
