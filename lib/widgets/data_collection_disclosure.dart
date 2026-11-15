import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/app_snackbar.dart';

/// 渐进式披露组件：默认收起，点按后平滑展开纯白话的详细隐私说明。
///
/// 反馈与联系页、更新说明页以及首次引导页共同复用，避免用户一进来就被大段技术说明吓到。
class ExpandablePrivacyDetail extends StatefulWidget {
  const ExpandablePrivacyDetail({
    super.key,
    required this.detailText,
    this.padding = EdgeInsets.zero,
  });

  final String detailText;
  final EdgeInsetsGeometry padding;

  @override
  State<ExpandablePrivacyDetail> createState() =>
      _ExpandablePrivacyDetailState();
}

class _ExpandablePrivacyDetailState extends State<ExpandablePrivacyDetail> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shapeTokens = AppShapeTokens.of(context);

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded
                        ? l10n.dataCollectionCollapseDetails
                        : l10n.dataCollectionExpandDetails,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(
                        shapeTokens.inputRadius,
                      ),
                    ),
                    child: Text(
                      widget.detailText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 面向普通用户的隐私保护与数据说明弹窗。
///
/// 反馈与联系页和更新说明页共用这一份，用平实易懂的语言说明用途与隐私边界。
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
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
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
