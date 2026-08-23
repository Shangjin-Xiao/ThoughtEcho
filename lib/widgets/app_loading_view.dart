import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';
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
                semanticLabel: message ?? AppLocalizations.of(context).loading,
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

/// 行内的小转圈：一行状态文字前面那一颗。
///
/// **它不是 [AppLoadingView] 的替代，两者管的是不同的东西。** [AppLoadingView]
/// 是「这一整块区域还没内容」的占位——居中的 Lottie，尺寸下限 80，还能挂一行说明；
/// 把它塞进对话流里那行「正在思考」，就是在一行字前面放一个 80 的动画。
/// 这里管的是另一件事：和正文同行、和图标同径的状态指示。
///
/// 抽出来是因为这种小转圈在 AI 那几个面板里已经各写各的了——12/14/16 三种直径、
/// 1.8/2 两种线宽、前景色有的乘透明度有的不乘，同一个"正在进行"在相邻两处
/// 粗细不一。尺寸和线宽的默认值取「和 16 的图标同径」，换状态时那一列不跳。
class AppInlineLoadingIndicator extends StatelessWidget {
  const AppInlineLoadingIndicator({
    super.key,
    this.size = 16,
    this.strokeWidth = 2,
    this.color,
  });

  /// 圈的直径。默认和行内图标（16）同径。
  final double size;

  final double strokeWidth;

  /// 默认 `onSurfaceVariant`——状态文字用的就是这支墨，圈和字同色才是一行东西。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
