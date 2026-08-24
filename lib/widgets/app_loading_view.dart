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
    this.size = 14,
    this.strokeWidth = 1.8,
    this.color,
  });

  /// 圈的直径。默认 14，配的是 16 的行内图标。
  ///
  /// 不是 16——那是"外框同宽"，不是"看着一样大"。Material 图标的字形自带
  /// 内边距，`Icons.check` 画到 16 的盒子里，实际那一笔只占 12 出头；同一个
  /// 盒子里画一个满 16 的圆环，换状态时这一列就会胖一圈。14 的圆环和 16 的
  /// 勾是同一个视觉重量，转圈变成勾时那一行不跳。
  final double size;

  /// 线宽。默认 1.8，取的是 16 号图标字形的笔画粗细——2 在 14 的圆环上
  /// 已经比勾重了。
  final double strokeWidth;

  /// 默认 `onSurfaceVariant`——状态文字用的就是这支墨，圈和字同色才是一行东西。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(resolved),
        // 下面四个都是在退掉 M3「表现力」版转圈的默认造型（主题里
        // year2023: false）。那套默认值是给 40 点的独立转圈设计的，缩到
        // 16 点、挤在一行状态文字前面时全都变成噪声：
        //
        // - backgroundColor：默认会画一圈 primary 淡色轨道。这颗圈的前景是
        //   onSurfaceVariant（跟着状态文字走），轨道却是主题色——一行里两支
        //   墨，读起来像个彩色小甜甜圈，而不是"正在进行"。
        // - trackGap：轨道和圆弧之间还留一道缺口，16 点上那道缺口和线宽同级。
        // - padding：M3 默认在转圈外面再垫 4 点。塞进 16 的盒子里只剩 8 点的
        //   圆弧——旁边完成态的 Icons.check 是 16 的字形，两者一换就跳一下，
        //   这正是"转圈和 √ 不匹配"的来源。
        // - strokeCap：圆头，和图标字形的收笔是一路的。
        backgroundColor: Colors.transparent,
        trackGap: 0,
        padding: EdgeInsets.zero,
        strokeCap: StrokeCap.round,
      ),
    );
  }
}
