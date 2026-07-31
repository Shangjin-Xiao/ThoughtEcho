import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../gen_l10n/app_localizations.dart';

class AppEmptyView extends StatelessWidget {
  final String? svgAsset;
  final String text;
  final String? message;
  final Widget? animation;
  final VoidCallback? onRefresh;

  const AppEmptyView({
    this.svgAsset,
    required this.text,
    this.message,
    this.animation,
    this.onRefresh,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (animation != null)
              animation!
            else if (svgAsset != null)
              SvgPicture.asset(
                svgAsset!,
                width: 120,
                height: 120,
              )
            else
              Icon(
                Icons.inbox,
                size: 72,
                color: Theme.of(context).colorScheme.outline,
              ),
            const SizedBox(height: 16),
            Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRefresh != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context).refresh),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
