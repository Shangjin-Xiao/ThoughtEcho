import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../gen_l10n/app_localizations.dart';

class AppErrorView extends StatelessWidget {
  final String text;
  final String? message;
  final VoidCallback? onRetry;
  final String? svgAsset;

  const AppErrorView({
    required this.text,
    this.message,
    this.onRetry,
    this.svgAsset,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (svgAsset != null)
            SvgPicture.asset(
              svgAsset!,
              width: 120,
              height: 120,
            )
          else
            const Icon(
              Icons.error,
              size: 72,
              color: Colors.red,
            ),
          const SizedBox(height: 16),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.8),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context)?.refresh ?? 'Refresh'),
            ),
          ],
        ],
      ),
    );
  }
}
