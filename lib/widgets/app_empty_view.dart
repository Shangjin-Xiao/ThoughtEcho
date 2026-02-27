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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (animation != null)
              animation!
            else if (svgAsset != null)
              Semantics(
                image: true,
                label: text,
                child: SvgPicture.asset(
                  svgAsset!,
                  width: 200,
                  height: 200,
                  placeholderBuilder:
                      (context) => Icon(
                        Icons.inbox,
                        size: 72,
                        color: theme.colorScheme.outline.withOpacity(0.5),
                      ),
                ),
              )
            else
              Icon(
                Icons.inbox,
                size: 72,
                color: theme.colorScheme.outline.withOpacity(0.5),
              ),
            const SizedBox(height: 24),
            Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRefresh != null) ...[
              const SizedBox(height: 24),
              // Use standard FilledButton.icon with tonal style override or just FilledButton.icon
              // Actually, Flutter 3.x has FilledButton.tonal and FilledButton.icon, but FilledButton.tonal.icon isn't standard.
              // To get a tonal button with an icon, we use FilledButton.tonal(child: Row(...)) or use styleFrom.
              // A better alternative that matches standard patterns:
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.refresh),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
