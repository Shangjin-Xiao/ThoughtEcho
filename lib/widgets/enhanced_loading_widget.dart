import 'package:flutter/material.dart';
import '../utils/lottie_animation_manager.dart';

/// 增强的加载组件
/// 使用Lottie动画提供更流畅的加载体验
class EnhancedLoadingWidget extends StatelessWidget {
  final String? message;
  final LottieAnimationType animationType;
  final double? size;
  final Color? textColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final bool showMessage;
  final Widget? customMessage;

  const EnhancedLoadingWidget({
    super.key,
    this.message,
    this.animationType = LottieAnimationType.pulseLoading,
    this.size,
    this.textColor,
    this.textStyle,
    this.padding,
    this.showMessage = true,
    this.customMessage,
  });

  /// 创建简单的加载动画（仅动画，无文本）
  const EnhancedLoadingWidget.simple({
    super.key,
    this.animationType = LottieAnimationType.customLoading,
    this.size = 60,
  }) : message = null,
       textColor = null,
       textStyle = null,
       padding = null,
       showMessage = false,
       customMessage = null;

  /// 创建全屏加载页面
  const EnhancedLoadingWidget.fullScreen({
    super.key,
    this.message = '正在加载...',
    this.animationType = LottieAnimationType.pulseLoading,
    this.textColor,
    this.textStyle,
  }) : size = 120,
       padding = const EdgeInsets.all(24),
       showMessage = true,
       customMessage = null;

  /// 创建对话框加载组件
  const EnhancedLoadingWidget.dialog({
    super.key,
    this.message = '请稍候...',
    this.animationType = LottieAnimationType.customLoading,
  }) : size = 80,
       textColor = null,
       textStyle = null,
       padding = const EdgeInsets.all(24),
       showMessage = true,
       customMessage = null;

  /// EnhancedLoadingWidget.thinking 改为原生思考动画
  const EnhancedLoadingWidget.thinking({super.key, this.message = 'AI正在思考...'})
    : animationType = LottieAnimationType.aiThinking,
      size = 80,
      textColor = null,
      textStyle = null,
      padding = const EdgeInsets.all(16),
      showMessage = true,
      customMessage = null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTextColor = textColor ?? theme.colorScheme.onSurface;
    final effectiveTextStyle =
        textStyle ??
        theme.textTheme.bodyMedium?.copyWith(color: effectiveTextColor);
    if (animationType == LottieAnimationType.aiThinking) {
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: size ?? 80,
              height: size ?? 80,
              child: const CircularProgressIndicator(strokeWidth: 4),
            ),
            if (showMessage && (message != null || customMessage != null)) ...[
              const SizedBox(height: 16),
              customMessage ??
                  Text(
                    message!,
                    style: effectiveTextStyle,
                    textAlign: TextAlign.center,
                  ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final s = (size ?? constraints.maxHeight * 0.5).clamp(
                80.0,
                220.0,
              );
              return EnhancedLottieAnimation(
                type: animationType,
                width: s,
                height: s,
                semanticLabel: _getSemanticLabel(),
              );
            },
          ),
          if (showMessage && (message != null || customMessage != null)) ...[
            const SizedBox(height: 16),
            customMessage ??
                Text(
                  message!,
                  style: effectiveTextStyle,
                  textAlign: TextAlign.center,
                ),
          ],
        ],
      ),
    );
  }

  String _getSemanticLabel() {
    if (message != null) return message!;
    switch (animationType) {
      case LottieAnimationType.aiThinking:
        return 'AI正在思考';
      case LottieAnimationType.loading:
      case LottieAnimationType.pulseLoading:
        return '正在加载';
      default:
        return '请稍候';
    }
  }
}

/// 状态动画组件（原生实现）
class StatusAnimationWidget extends StatefulWidget {
  final bool isSuccess;
  final String? message;
  final Duration? displayDuration;
  final VoidCallback? onCompleted;
  final double? size;
  final Color? textColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;

  const StatusAnimationWidget.success({
    super.key,
    this.message = '操作成功！',
    this.displayDuration = const Duration(seconds: 2),
    this.onCompleted,
    this.size = 100,
    this.textColor,
    this.textStyle,
    this.padding,
  }) : isSuccess = true;

  const StatusAnimationWidget.error({
    super.key,
    this.message = '操作失败',
    this.displayDuration = const Duration(seconds: 2),
    this.onCompleted,
    this.size = 100,
    this.textColor,
    this.textStyle,
    this.padding,
  }) : isSuccess = false;

  @override
  State<StatusAnimationWidget> createState() => _StatusAnimationWidgetState();
}

class _StatusAnimationWidgetState extends State<StatusAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
    if (widget.displayDuration != null) {
      Future.delayed(widget.displayDuration!, () {
        if (mounted) widget.onCompleted?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTextColor =
        widget.textColor ??
        (widget.isSuccess ? Colors.green : theme.colorScheme.error);
    final effectiveTextStyle =
        widget.textStyle ??
        theme.textTheme.bodyLarge?.copyWith(
          color: effectiveTextColor,
          fontWeight: FontWeight.w500,
        );
    final icon =
        widget.isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;
    return Padding(
      padding: widget.padding ?? const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _scaleAnim,
            child: Icon(
              icon,
              color: effectiveTextColor,
              size: widget.size ?? 100,
            ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 16),
            Text(
              widget.message!,
              style: effectiveTextStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// 空状态组件（原生实现）
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;

  const EmptyStateWidget({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.iconSize = 120,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_rounded,
            size: iconSize,
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

/// 加载对话框
class LoadingDialog extends StatelessWidget {
  final String? message;
  final LottieAnimationType animationType;
  final bool barrierDismissible;

  const LoadingDialog({
    super.key,
    this.message,
    this.animationType = LottieAnimationType.customLoading,
    this.barrierDismissible = false,
  });

  static Future<void> show(
    BuildContext context, {
    String? message,
    LottieAnimationType animationType = LottieAnimationType.customLoading,
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder:
          (context) => LoadingDialog(
            message: message,
            animationType: animationType,
            barrierDismissible: barrierDismissible,
          ),
    );
  }

  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: EnhancedLoadingWidget.dialog(
          message: message,
          animationType: animationType,
        ),
      ),
    );
  }
}
