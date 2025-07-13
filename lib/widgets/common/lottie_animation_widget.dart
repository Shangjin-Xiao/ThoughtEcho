import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../config/lottie_config.dart';

/// 通用Lottie动画组件
///
/// 支持多种动画场景和自定义配置
class LottieAnimationWidget extends StatefulWidget {
  final String? animationPath;
  final LottieScene? scene;
  final double? width;
  final double? height;
  final bool? repeat;
  final BoxFit fit;
  final AnimationController? controller;
  final VoidCallback? onLoaded;
  final VoidCallback? onCompleted;
  final Color? color;
  final double? speed;
  final bool autoPlay;

  const LottieAnimationWidget({
    super.key,
    this.animationPath,
    this.scene,
    this.width,
    this.height,
    this.repeat,
    this.fit = BoxFit.contain,
    this.controller,
    this.onLoaded,
    this.onCompleted,
    this.color,
    this.speed = 1.0,
    this.autoPlay = true,
  }) : assert(
         animationPath != null || scene != null,
         '必须提供animationPath或scene参数',
       );

  /// 快捷构造函数 - 使用预设场景
  const LottieAnimationWidget.scene(
    LottieScene scene, {
    Key? key,
    double? width,
    double? height,
    bool? repeat,
    BoxFit fit = BoxFit.contain,
    AnimationController? controller,
    VoidCallback? onLoaded,
    VoidCallback? onCompleted,
    Color? color,
    double speed = 1.0,
    bool autoPlay = true,
  }) : this(
         key: key,
         scene: scene,
         width: width,
         height: height,
         repeat: repeat,
         fit: fit,
         controller: controller,
         onLoaded: onLoaded,
         onCompleted: onCompleted,
         color: color,
         speed: speed,
         autoPlay: autoPlay,
       );

  @override
  State<LottieAnimationWidget> createState() => _LottieAnimationWidgetState();
}

class _LottieAnimationWidgetState extends State<LottieAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationPreset _preset;
  late String _animationPath;
  late bool _shouldRepeat;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _setupController();
  }

  void _initializeAnimation() {
    if (widget.scene != null) {
      _preset = LottieConfig.getAnimationForScene(widget.scene!);
      _animationPath = _preset.path;
      _shouldRepeat = widget.repeat ?? _preset.repeat;
    } else {
      _animationPath = widget.animationPath!;
      _shouldRepeat = widget.repeat ?? true;
    }
  }

  void _setupController() {
    _controller =
        widget.controller ??
        AnimationController(vsync: this, duration: const Duration(seconds: 2));

    // 设置播放速度
    if (widget.speed != null && widget.speed != 1.0) {
      _controller.duration = Duration(
        milliseconds:
            (_controller.duration!.inMilliseconds / widget.speed!).round(),
      );
    }

    if (widget.autoPlay) {
      if (_shouldRepeat) {
        _controller.repeat();
      } else {
        _controller.forward().then((_) {
          widget.onCompleted?.call();
        });
      }
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width ?? (widget.scene != null ? _preset.size : null),
      height: widget.height ?? (widget.scene != null ? _preset.size : null),
      child: Lottie.asset(
        _animationPath,
        fit: widget.fit,
        controller: _controller,
        repeat: _shouldRepeat,
        onLoaded: (composition) {
          _controller.duration = composition.duration;
          widget.onLoaded?.call();
        },
        options:
            widget.color != null ? LottieOptions(enableMergePaths: true) : null,
      ),
    );
  }
}

/// 带有文本的Lottie动画组件
class LottieAnimationWithText extends StatelessWidget {
  final LottieScene scene;
  final String? text;
  final TextStyle? textStyle;
  final double spacing;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  const LottieAnimationWithText({
    super.key,
    required this.scene,
    this.text,
    this.textStyle,
    this.spacing = 16.0,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final preset = LottieConfig.getAnimationForScene(scene);
    final displayText = text ?? preset.description;

    return Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        LottieAnimationWidget.scene(scene),
        SizedBox(height: spacing),
        Text(
          displayText,
          style: textStyle ?? Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
