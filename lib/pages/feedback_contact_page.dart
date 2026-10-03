import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/custom_feedback_page.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/widgets/app_snackbar.dart';

class FeedbackContactPage extends StatelessWidget {
  const FeedbackContactPage({super.key});

  static const String _feedbackUrl =
      'https://github.com/Shangjin-Xiao/ThoughtEcho/issues/new/choose';
  static const String _projectUrl =
      'https://github.com/Shangjin-Xiao/ThoughtEcho';
  static const String _discussionUrl =
      'https://github.com/Shangjin-Xiao/ThoughtEcho/discussions';
  static const String _emailUrl = 'mailto:shangjinyun@proton.me';

  Future<void> _launchUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      AppSnackBar.error(context, l10n.cannotOpenLink(url));
    }
  }

  void _showDataCollectionDisclosureDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shapeTokens = AppShapeTokens.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeTokens.dialogRadius),
        ),
        title: Text(l10n.dataCollectionDisclosureTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dataCollectionDisclosureContent,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(shapeTokens.buttonRadius),
                      ),
                    ),
                    icon: const Icon(Icons.bug_report_outlined, size: 16),
                    label: Text(l10n.viewSentrySourceCode),
                    onPressed: () => _launchUrl(
                      dialogContext,
                      'https://github.com/Shangjin-Xiao/ThoughtEcho/blob/main/lib/utils/sentry_helper.dart',
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(shapeTokens.buttonRadius),
                      ),
                    ),
                    icon: const Icon(Icons.insights_outlined, size: 16),
                    label: Text(l10n.viewAptabaseSourceCode),
                    onPressed: () => _launchUrl(
                      dialogContext,
                      'https://github.com/Shangjin-Xiao/ThoughtEcho/blob/main/lib/utils/aptabase_helper.dart',
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(shapeTokens.buttonRadius),
                      ),
                    ),
                    icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                    label: Text(l10n.viewPrivacyPolicy),
                    onPressed: () => _launchUrl(
                      dialogContext,
                      'https://note.shangjinyun.cn/privacy',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.sentryDisclosureGotIt),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedbackAndContact),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.feedbackSentryTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                Consumer<SettingsService>(
                  builder: (context, settingsService, _) {
                    final isEnabled = settingsService.sentryEnabled;
                    return ListTile(
                      enabled: isEnabled,
                      leading: Icon(
                        Icons.rate_review_outlined,
                        color: isEnabled ? colorScheme.primary : null,
                      ),
                      title: Text(l10n.feedbackSentryDesc),
                      subtitle: isEnabled
                          ? null
                          : Text(
                              l10n.feedbackSentryDisabledHint,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.error,
                                  ),
                            ),
                      onTap: isEnabled
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CustomFeedbackPage(),
                                ),
                              )
                          : null,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.feedbackAndContactDesc,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.bug_report_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackGithubTitle),
                  subtitle: Text(l10n.feedbackGithubDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _feedbackUrl),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.forum_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackDiscussionTitle),
                  subtitle: Text(l10n.feedbackDiscussionDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _discussionUrl),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.code_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackGithubRepoTitle),
                  subtitle: Text(l10n.feedbackGithubRepoDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _projectUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.contactDeveloperSectionTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.email_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackEmailTitle),
                  subtitle: Text(l10n.feedbackEmailDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _emailUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Consumer<SettingsService>(
              builder: (context, settingsService, _) {
                final theme = Theme.of(context);
                final shapeTokens = AppShapeTokens.of(context);
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
                      onChanged: (enabled) async {
                        try {
                          await settingsService.setSentryEnabled(enabled);
                          if (context.mounted) {
                            AppSnackBar.info(context, l10n.sentryRestartHint);
                          }
                        } catch (e, stack) {
                          logError(
                            'FeedbackContactPage.setSentryEnabled failed',
                            error: e,
                            stackTrace: stack,
                            source: 'FeedbackContact',
                          );
                          if (context.mounted) {
                            AppSnackBar.error(
                              context,
                              l10n.saveFailed(e.toString()),
                            );
                          }
                        }
                      },
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
                                _showDataCollectionDisclosureDialog(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Consumer<SettingsService>(
              builder: (context, settingsService, _) {
                final theme = Theme.of(context);
                final shapeTokens = AppShapeTokens.of(context);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      onChanged: (enabled) async {
                        try {
                          await settingsService.setTelemetryEnabled(enabled);
                        } catch (e, stack) {
                          logError(
                            'FeedbackContactPage.setTelemetryEnabled failed',
                            error: e,
                            stackTrace: stack,
                            source: 'FeedbackContact',
                          );
                          if (context.mounted) {
                            AppSnackBar.error(
                              context,
                              l10n.saveFailed(e.toString()),
                            );
                          }
                        }
                      },
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
                                _showDataCollectionDisclosureDialog(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
