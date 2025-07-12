import 'package:flutter/material.dart';
import '../utils/lottie_animation_manager.dart';

/// 增强的AI加载对话框
/// 使用高质量的Lottie动画提供更好的用户体验
class EnhancedAILoadingDialog extends StatelessWidget {
  final String? message;
  final LottieAnimationType animationType;
  final bool barrierDismissible;

  const EnhancedAILoadingDialog({
    super.key,
    this.message,
    this.animationType = LottieAnimationType.aiThinking,
    this.barrierDismissible = false,
  });

  /// 显示AI思考对话框
  static Future<void> showThinking(
    BuildContext context, {
    String message = 'AI正在思考...',
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAILoadingDialog(
        message: message,
        animationType: LottieAnimationType.aiThinking,
        barrierDismissible: barrierDismissible,
      ),
    );
  }

  /// 显示数据处理对话框
  static Future<void> showProcessing(
    BuildContext context, {
    String message = '正在处理数据...',
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAILoadingDialog(
        message: message,
        animationType: LottieAnimationType.modernLoading,
        barrierDismissible: barrierDismissible,
      ),
    );
  }

  /// 显示分析对话框
  static Future<void> showAnalyzing(
    BuildContext context, {
    String message = '正在分析内容...',
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAILoadingDialog(
        message: message,
        animationType: LottieAnimationType.aiThinking,
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
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final s = (constraints.maxHeight * 0.5).clamp(120.0, 220.0);
                if (animationType == LottieAnimationType.aiThinking) {
                  return SizedBox(
                    width: s,
                    height: s,
                    child: const CircularProgressIndicator(strokeWidth: 4),
                  );
                } else {
                  return EnhancedLottieAnimation(
                    type: animationType,
                    width: s,
                    height: s,
                  );
                }
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
  final LottieAnimationType animationType;
  final bool barrierDismissible;

  const EnhancedAIProgressDialog({
    super.key,
    this.message,
    this.progress,
    this.animationType = LottieAnimationType.modernLoading,
    this.barrierDismissible = false,
  });

  /// 显示带进度的对话框
  static Future<void> showWithProgress(
    BuildContext context, {
    String? message,
    double? progress,
    LottieAnimationType animationType = LottieAnimationType.modernLoading,
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => EnhancedAIProgressDialog(
        message: message,
        progress: progress,
        animationType: animationType,
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
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lottie动画
            EnhancedLottieAnimation(
              type: animationType,
              width: 80,
              height: 80,
            ),
            
            if (message != null) ...[
              const SizedBox(height: 20),
              Text(
                message!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
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
