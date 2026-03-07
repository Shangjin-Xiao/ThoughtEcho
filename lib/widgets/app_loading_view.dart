import 'package:flutter/material.dart';
import '../utils/lottie_animation_manager.dart';

class AppLoadingView extends StatelessWidget {
  final double size;
  final String? message;
  final LottieAnimationType animationType;

  const AppLoadingView({
    this.size = 80,
    this.message,
    this.animationType = LottieAnimationType.pulseLoading,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final s = (size.isFinite ? size : constraints.maxHeight * 0.5)
                  .clamp(80.0, 220.0);
              return EnhancedLottieAnimation(
                type: animationType,
                width: s,
                height: s,
                semanticLabel: message ?? '加载中',
              );
            },
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
