import 'package:flutter/material.dart';

class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minOpacity;
  final double maxOpacity;

  const PulseAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 2),
    this.minOpacity = 0.8,
    this.maxOpacity = 1.0,
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
  }

  void _initializeAnimation() {
    try {
      _controller = AnimationController(duration: widget.duration, vsync: this);
      _animation = Tween<double>(
        begin: widget.minOpacity,
        end: widget.maxOpacity,
      ).animate(CurvedAnimation(parent: _controller!, curve: Curves.easeInOut));

      _controller!.repeat(reverse: true);
    } catch (e) {
      // 如果动画初始化失败，提供默认值
      print('PulseAnimation动画初始化失败: $e');
      _animation = Tween<double>(
        begin: widget.minOpacity,
        end: widget.maxOpacity,
      ).animate(const AlwaysStoppedAnimation<double>(1.0));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(opacity: _animation.value, child: widget.child);
      },
    );
  }
}
