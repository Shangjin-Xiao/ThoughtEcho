import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/widgets/app_snackbar.dart';
import 'package:thoughtecho/widgets/data_collection_disclosure.dart';

/// 数据收集开关合集卡：诊断数据与体验改进计划两个开关 + 一个共用的说明按钮。
///
/// 反馈与联系页和更新说明页共用这一份，避免两处各放一个「查看收集详情」按钮。
class DataCollectionConsentCard extends StatelessWidget {
  const DataCollectionConsentCard({super.key});

  Future<void> _updateSetting(
    BuildContext context, {
    required Future<void> Function() action,
    required String logAction,
    String? successMessage,
  }) async {
    final l10n = AppLocalizations.of(context);
    try {
      await action();
      if (successMessage != null && context.mounted) {
        AppSnackBar.info(context, successMessage);
      }
    } catch (e, stack) {
      logError(
        '$logAction failed',
        error: e,
        stackTrace: stack,
        source: 'DataCollectionConsent',
      );
      if (context.mounted) {
        AppSnackBar.error(context, l10n.saveFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shapeTokens = AppShapeTokens.of(context);

    return Card(
      child: Consumer<SettingsService>(
        builder: (context, settingsService, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(l10n.settingsSentryTitle),
                subtitle: Text(
                  l10n.settingsSentryDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                secondary: Icon(
                  Icons.bug_report_outlined,
                  color: colorScheme.primary,
                ),
                value: settingsService.sentryEnabled,
                onChanged: (enabled) => _updateSetting(
                  context,
                  action: () => settingsService.setSentryEnabled(enabled),
                  logAction: 'DataCollectionConsent.setSentryEnabled',
                  successMessage: l10n.sentryRestartHint,
                ),
              ),
              const Divider(indent: 16, endIndent: 16, height: 1),
              SwitchListTile(
                title: Text(l10n.settingsTelemetryTitle),
                subtitle: Text(
                  l10n.settingsTelemetryDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                secondary: Icon(
                  Icons.insights_outlined,
                  color: colorScheme.primary,
                ),
                value: settingsService.telemetryEnabled,
                onChanged: (enabled) => _updateSetting(
                  context,
                  action: () => settingsService.setTelemetryEnabled(enabled),
                  logAction: 'DataCollectionConsent.setTelemetryEnabled',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: Text(l10n.learnMoreDataCollection),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            shapeTokens.buttonRadius,
                          ),
                        ),
                      ),
                      onPressed: () =>
                          showDataCollectionDisclosureDialog(context),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
