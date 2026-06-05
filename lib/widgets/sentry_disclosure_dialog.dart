import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/settings_service.dart';

class SentryDisclosureDialog {
  SentryDisclosureDialog._();

  /// 检查并显示 Sentry 隐私披露弹窗
  static Future<void> checkAndShow(BuildContext context) async {
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    if (!settingsService.sentryDisclosureShown) {
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l10n.sentryDisclosureTitle),
            content: Text(l10n.sentryDisclosureMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(l10n.sentryDisclosureGotIt),
              ),
            ],
          );
        },
      );
      await settingsService.setSentryDisclosureShown(true);
    }
  }
}
