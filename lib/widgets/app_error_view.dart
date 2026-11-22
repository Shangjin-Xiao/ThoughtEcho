import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';

class AppErrorView extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  final String? retryText;

  const AppErrorView({
    required this.text,
    this.onRetry,
    this.retryText,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedRetryText = retryText ??
        Localizations.of<AppLocalizations>(context, AppLocalizations)?.retry ??
        'Retry';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 72,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(resolvedRetryText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
