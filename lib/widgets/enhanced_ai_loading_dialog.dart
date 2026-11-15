import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';
import '../theme/theme_style.dart';
import 'app_loading_animation.dart';

/// 增强的AI加载对话框
/// 使用心迹自绘加载动画提供更好的用户体验
class EnhancedAILoadingDialog extends StatelessWidget {
  final String? message;
  final AppLoadingStyle style;
  final bool barrierDismissible;

  const EnhancedAILoadingDialog({
    super.key,
    this.message,
    this.style = AppLoadingStyle.inkWriting,
    this.barrierDismissible = false,
  });

  /// 显示AI思考对话框
  static Future<void> showThinking(
    BuildContext context, {
    String? message,
    bool barrierDismissible = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAILoadingDialog(
        message: message ?? l10n.aiThinkingProgress,
        style: AppLoadingStyle.inkWriting,
        barrierDismissible: barrierDismissible,
      ),
    );
  }

  /// 显示数据处理对话框
  static Future<void> showProcessing(
    BuildContext context, {
    String? message,
    bool barrierDismissible = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAILoadingDialog(
        message: message ?? l10n.processingData,
        style: AppLoadingStyle.bookFlip,
        barrierDismissible: barrierDismissible,
      ),
    );
  }

  /// 显示分析对话框
  static Future<void> showAnalyzing(
    BuildContext context, {
    String? message,
    bool barrierDismissible = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAILoadingDialog(
        message: message ?? l10n.analyzingContent,
        style: AppLoadingStyle.inkWriting,
        barrierDismissible: barrierDismissible,
      ),
    );
  }

  /// 隐藏对话框
  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(
            AppShapeTokens.of(context).dialogRadius,
          ),
          boxShadow: AppShapeTokens.of(context).raisedShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 220.0;
                final s = (constraints.maxHeight * 0.5).clamp(120.0, 220.0);
                final effectiveWidth = s > availableWidth ? availableWidth : s;
                return AppLoadingAnimation(
                  style: style,
                  width: effectiveWidth,
                  semanticLabel: message,
                );
              },
            ),
            if (message != null) ...[
              const SizedBox(height: 20),
              Text(
                message!,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 带有进度指示的增强AI对话框
class EnhancedAIProgressDialog extends StatelessWidget {
  final String? message;
  final double? progress;
  final AppLoadingStyle style;
  final bool barrierDismissible;

  const EnhancedAIProgressDialog({
    super.key,
    this.message,
    this.progress,
    this.style = AppLoadingStyle.bookFlip,
    this.barrierDismissible = false,
  });

  /// 显示带进度的对话框
  static Future<void> showWithProgress(
    BuildContext context, {
    String? message,
    double? progress,
    AppLoadingStyle style = AppLoadingStyle.bookFlip,
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAIProgressDialog(
        message: message,
        progress: progress,
        style: style,
        barrierDismissible: barrierDismissible,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(
            AppShapeTokens.of(context).dialogRadius,
          ),
          boxShadow: AppShapeTokens.of(context).raisedShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLoadingAnimation(
              style: style,
              width: 80,
              semanticLabel: message,
            ),

            if (message != null) ...[
              const SizedBox(height: 20),
              Text(
                message!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 20),

            // 进度条
            SizedBox(
              width: 200,
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${(progress! * 100).toInt()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
