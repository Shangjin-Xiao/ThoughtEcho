import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import '../../utils/app_logger.dart';

/// 实验性功能标签 Component
///
/// 用于在入口、AppBar、卡片等微组件上标记“实验性”/“Beta”状态。
class ExperimentalBadge extends StatelessWidget {
  final bool compact;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;
  final VoidCallback? onTap;
  final bool enableTapNotice;

  const ExperimentalBadge({
    super.key,
    this.compact = false,
    this.padding,
    this.fontSize,
    this.onTap,
    this.enableTapNotice = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;

    final badgeBg = colorScheme.tertiaryContainer.withValues(alpha: 0.85);
    final badgeFg = colorScheme.onTertiaryContainer;

    final borderRadius = BorderRadius.circular(compact ? 6 : 8);

    final Widget badgeContent = Container(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 2 : 3,
          ),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: borderRadius,
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.science_outlined,
            size: fontSize != null ? (fontSize! + 2) : (compact ? 11 : 13),
            color: badgeFg,
          ),
          const SizedBox(width: 3),
          Text(
            l10n.experimentalTag,
            style: theme.textTheme.labelSmall?.copyWith(
              color: badgeFg,
              fontSize: fontSize ?? (compact ? 10 : 11),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    final effectiveOnTap = onTap ??
        (enableTapNotice
            ? () => unawaited(showExperimentalNoticeDialog(context))
            : null);

    if (effectiveOnTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: effectiveOnTap,
          borderRadius: borderRadius,
          child: badgeContent,
        ),
      );
    }

    return badgeContent;
  }
}

/// 实验性功能免责与注意事项提示弹窗
Future<void> showExperimentalNoticeDialog(BuildContext context) async {
  final theme = Theme.of(context);
  final l10n = AppLocalizations.of(context);
  final colorScheme = theme.colorScheme;
  bool dontShowAgain = false;

  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          void handleDismiss() {
            if (dontShowAgain) {
              try {
                final settingsService = context.read<SettingsService>();
                unawaited(
                  settingsService.setDontShowAgentExperimentalNotice(true),
                );
              } catch (e) {
                // 失败时不弹窗提示用户，但必须记录日志以便排查偏好写入失败
                logWarning(
                  '写入「不再提示」偏好失败: $e',
                  source: 'ExperimentalNoticeDialog',
                );
              }
            }
            Navigator.of(dialogContext).pop();
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 6,
            backgroundColor: colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 头部图标与标题 + 右上角关闭按钮
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.science_rounded,
                          color: colorScheme.onTertiaryContainer,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    l10n.agentExperimentalNoticeTitle,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const ExperimentalBadge(
                              compact: true,
                              enableTapNotice: false,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: l10n.close,
                        visualDensity: VisualDensity.compact,
                        onPressed: handleDismiss,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.agentExperimentalNoticeIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 注意事项卡片列表
                  _NoticePointTile(
                    icon: Icons.error_outline_rounded,
                    iconColor: colorScheme.error,
                    content: l10n.agentExperimentalNoticePoint1,
                  ),
                  const SizedBox(height: 12),
                  _NoticePointTile(
                    icon: Icons.security_rounded,
                    iconColor: colorScheme.primary,
                    content: l10n.agentExperimentalNoticePoint2,
                  ),
                  const SizedBox(height: 12),
                  _NoticePointTile(
                    icon: Icons.build_circle_outlined,
                    iconColor: colorScheme.tertiary,
                    content: l10n.agentExperimentalNoticePoint3,
                  ),
                  const SizedBox(height: 16),

                  // 不再自动提示勾选框
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        dontShowAgain = !dontShowAgain;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: dontShowAgain,
                              onChanged: (val) {
                                setDialogState(() {
                                  dontShowAgain = val ?? false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.dontShowAgain,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 底部确认按钮
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: handleDismiss,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        l10n.agentExperimentalNoticeGotIt,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _NoticePointTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String content;

  const _NoticePointTile({
    required this.icon,
    required this.iconColor,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              content,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
