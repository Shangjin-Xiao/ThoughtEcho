import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/app_snackbar.dart';

/// 数据收集说明弹窗：Sentry 错误诊断与 Aptabase 匿名统计共用同一份说明。
///
/// 反馈与联系页和更新说明页都用它，保证两处看到的内容一致。
Future<void> showDataCollectionDisclosureDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final shapeTokens = AppShapeTokens.of(context);

  return showDialog<void>(
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
                  onPressed: () => _launchDisclosureUrl(
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
                  onPressed: () => _launchDisclosureUrl(
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
                  onPressed: () => _launchDisclosureUrl(
                    dialogContext,
                    AppConstants.privacyPolicyUrl,
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

Future<void> _launchDisclosureUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    AppSnackBar.error(context, l10n.cannotOpenLink(url));
  }
}
