import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Lottie 加载动画组件
class LottieLoadingWidget extends StatelessWidget {
  final double size;
  final String? text;
  final Color? textColor;
  final bool showText;

  const LottieLoadingWidget({
    super.key,
    this.size = 80,
    this.text,
    this.textColor,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Lottie.asset(
            'assets/lottie/custom_loading.json', // 使用自定义加载动画
            fit: BoxFit.contain,
            repeat: true,
            animate: true,
          ),
        ),
        if (showText && text != null) ...[
          SizedBox(height: size * 0.2),
          Text(
            text!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  textColor ??
                  theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// 小尺寸的Lottie加载动画（用于按钮等）
class LottieLoadingButton extends StatelessWidget {
  final double size;
  final Color? color;

  const LottieLoadingButton({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/lottie/custom_loading.json', // 使用自定义加载动画
        fit: BoxFit.contain,
        repeat: true,
        animate: true,
      ),
    );
  }
}

/// 全屏Lottie加载动画
class LottieLoadingOverlay extends StatelessWidget {
  final String? text;
  final Color? backgroundColor;
  final bool blurBackground;

  const LottieLoadingOverlay({
    super.key,
    this.text,
    this.backgroundColor,
    this.blurBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color:
          backgroundColor ??
          theme.colorScheme.surface.withValues(
            alpha: blurBackground ? 0.8 : 1.0,
          ),
      child: Center(
        child: LottieLoadingWidget(
          size: 120,
          text: text ?? '加载中...',
          showText: true,
        ),
      ),
    );
  }
}
