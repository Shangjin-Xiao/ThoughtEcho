import 'package:flutter/material.dart';

/// 具备按压缩放微动效与选中状态插值过渡的 FilterChip 交互包裹组件
class InteractiveAnimatedFilterChip extends StatefulWidget {
  /// 被包裹的 Chip 组件（通常为 FilterChip）
  final Widget child;

  /// 当前选中状态，变更时触发轻微弹出过渡动画
  final bool isSelected;

  /// 按下时的目标缩放比例，默认 0.94
  final double pressedScale;

  /// 选中状态变更时的弹出缩放峰值比例，默认 1.04
  final double selectedScale;

  /// 按下与释放缩放动画时长，默认 120 毫秒
  final Duration pressDuration;

  /// 选中状态切换插值动画时长，默认 180 毫秒
  final Duration selectionDuration;

  /// 按压微动效过渡曲线
  final Curve pressCurve;

  /// 选中微动效过渡曲线
  final Curve selectionCurve;

  const InteractiveAnimatedFilterChip({
    super.key,
    required this.child,
    this.isSelected = false,
    this.pressedScale = 0.94,
    this.selectedScale = 1.04,
    this.pressDuration = const Duration(milliseconds: 120),
    this.selectionDuration = const Duration(milliseconds: 180),
    this.pressCurve = Curves.easeOutCubic,
    this.selectionCurve = Curves.easeOut,
  });

  @override
  State<InteractiveAnimatedFilterChip> createState() =>
      _InteractiveAnimatedFilterChipState();
}

class _InteractiveAnimatedFilterChipState
    extends State<InteractiveAnimatedFilterChip> with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _pressAnimation;

  late final AnimationController _selectionController;
  late final Animation<double> _selectionAnimation;

  @override
  void initState() {
    super.initState();

    // 按压微动效控制器与动画
    _pressController = AnimationController(
      vsync: this,
      duration: widget.pressDuration,
    );
    _pressAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: widget.pressCurve,
        reverseCurve: widget.pressCurve,
      ),
    );

    // 选中状态变更插值微动效控制器与动画
    _selectionController = AnimationController(
      vsync: this,
      duration: widget.selectionDuration,
    );
    _selectionAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: widget.selectedScale).chain(
          CurveTween(curve: widget.selectionCurve),
        ),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: widget.selectedScale, end: 1.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 50,
      ),
    ]).animate(_selectionController);
  }

  @override
  void didUpdateWidget(InteractiveAnimatedFilterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      _selectionController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (mounted) {
      _pressController.forward();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (mounted) {
      _pressController.reverse();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (mounted) {
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: RepaintBoundary(
        child: ScaleTransition(
          scale: _pressAnimation,
          child: ScaleTransition(
            scale: _selectionAnimation,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
