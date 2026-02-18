import 'dart:async';

import 'package:flutter/material.dart';
import '../models/feature_guide.dart';

/// 气泡箭头方向
enum PopoverArrowDirection {
  top, // 箭头在顶部，气泡在下方
  bottom, // 箭头在底部，气泡在上方
  left, // 箭头在左侧，气泡在右方
  right, // 箭头在右侧，气泡在左方
}

/// 功能引导 Popover 气泡组件
/// 轻量级提示，带箭头指向目标元素
class FeatureGuidePopover extends StatefulWidget {
  final FeatureGuide guide;
  final VoidCallback onDismiss;
  final Duration autoDismissDuration;
  final bool Function()? visibilityPredicate;

  const FeatureGuidePopover({
    super.key,
    required this.guide,
    required this.onDismiss,
    this.autoDismissDuration = const Duration(seconds: 3),
    this.visibilityPredicate,
  });

  @override
  State<FeatureGuidePopover> createState() => _FeatureGuidePopoverState();
}

class _FeatureGuidePopoverState extends State<FeatureGuidePopover>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  Timer? _visibilityTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100), // 极简快速动画
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();

    _startVisibilityWatchdog();

    // 自动消失
    Future.delayed(widget.autoDismissDuration, () {
      if (mounted) {
        _handleDismiss();
      }
    });
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startVisibilityWatchdog() {
    if (widget.visibilityPredicate == null && widget.guide.targetKey == null) {
      return;
    }

    _visibilityTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) {
        _visibilityTimer?.cancel();
        return;
      }

      if (widget.visibilityPredicate != null &&
          !widget.visibilityPredicate!()) {
        _handleDismiss();
        return;
      }

      if (widget.guide.targetKey != null) {
        final targetContext = widget.guide.targetKey.currentContext;
        final renderBox = targetContext?.findRenderObject() as RenderBox?;
        final visible =
            renderBox != null && renderBox.attached && renderBox.hasSize;
        if (!visible) {
          _handleDismiss();
        }
      }
    });
  }

  Future<void> _handleDismiss() async {
    if (_isDismissing) {
      return;
    }
    _isDismissing = true;
    _visibilityTimer?.cancel();
    await _controller.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final guide = widget.guide;

    // 如果没有 targetKey，显示在屏幕中心
    if (guide.targetKey == null) {
      return _buildCenteredPopover(context);
    }

    // 获取目标元素的位置
    final RenderBox? renderBox =
        guide.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return _buildCenteredPopover(context);
    }

    return _buildPositionedPopover(context, renderBox);
  }

  /// 构建居中的气泡（无箭头）
  Widget _buildCenteredPopover(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.3),
      child: GestureDetector(
        onTap: () => _handleDismiss(),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildPopoverCard(
              context,
              PopoverArrowDirection.top,
              arrowOffset: 110,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建定位的气泡（带箭头）
  Widget _buildPositionedPopover(BuildContext context, RenderBox targetBox) {
    final targetSize = targetBox.size;
    final targetPosition = targetBox.localToGlobal(Offset.zero);
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;

    // 计算最佳显示位置和箭头方向
    final positioning = _calculateBestPosition(
      targetPosition: targetPosition,
      targetSize: targetSize,
      screenSize: screenSize,
      viewPadding: mediaQuery.padding,
      preferredPlacement: widget.guide.preferredPlacement,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 透明可点击遮罩层（点击关闭）
          GestureDetector(
            onTap: () => _handleDismiss(),
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // 气泡卡片
          Positioned(
            left: positioning['left'] as double,
            top: positioning['top'] as double,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _buildPopoverCard(
                context,
                positioning['arrowDirection'] as PopoverArrowDirection,
                arrowOffset: positioning['arrowOffset'] as double,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 计算最佳显示位置
  Map<String, dynamic> _calculateBestPosition({
    required Offset targetPosition,
    required Size targetSize,
    required Size screenSize,
    required EdgeInsets viewPadding,
    required FeatureGuidePlacement preferredPlacement,
  }) {
    const popoverWidth = 220.0;
    const popoverMaxHeight = 120.0;
    const arrowSize = 14.0;
    const margin = 12.0;

    // 应用用户自定义的偏移
    final userOffset = widget.guide.offset ?? Offset.zero;
    final adjustedTargetPosition = Offset(
      targetPosition.dx + userOffset.dx,
      targetPosition.dy + userOffset.dy,
    );

    final targetCenterX = adjustedTargetPosition.dx + targetSize.width / 2;
    final targetCenterY = adjustedTargetPosition.dy + targetSize.height / 2;
    final safeTop = viewPadding.top + margin;
    final safeBottom = screenSize.height - viewPadding.bottom - margin;
    const double safeLeft = margin;
    final safeRight = screenSize.width - margin;

    Map<String, dynamic>? fallback;

    for (final attempt in _buildPlacementAttempts(preferredPlacement)) {
      final result = _computePlacement(
        direction: attempt.direction,
        targetPosition: adjustedTargetPosition,
        targetSize: targetSize,
        targetCenterX: targetCenterX,
        targetCenterY: targetCenterY,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeLeft: safeLeft,
        safeRight: safeRight,
        popoverWidth: popoverWidth,
        popoverMaxHeight: popoverMaxHeight,
        arrowSize: arrowSize,
        requireInBounds: !attempt.allowClamp,
      );

      if (result != null) {
        return result;
      }

      if (attempt.allowClamp && fallback == null) {
        fallback = _computePlacement(
          direction: attempt.direction,
          targetPosition: adjustedTargetPosition,
          targetSize: targetSize,
          targetCenterX: targetCenterX,
          targetCenterY: targetCenterY,
          safeTop: safeTop,
          safeBottom: safeBottom,
          safeLeft: safeLeft,
          safeRight: safeRight,
          popoverWidth: popoverWidth,
          popoverMaxHeight: popoverMaxHeight,
          arrowSize: arrowSize,
          requireInBounds: false,
        );
      }
    }

    return fallback ??
        _computePlacement(
          direction: PopoverArrowDirection.top,
          targetPosition: adjustedTargetPosition,
          targetSize: targetSize,
          targetCenterX: targetCenterX,
          targetCenterY: targetCenterY,
          safeTop: safeTop,
          safeBottom: safeBottom,
          safeLeft: safeLeft,
          safeRight: safeRight,
          popoverWidth: popoverWidth,
          popoverMaxHeight: popoverMaxHeight,
          arrowSize: arrowSize,
          requireInBounds: false,
        )!;
  }

  List<({PopoverArrowDirection direction, bool allowClamp})>
  _buildPlacementAttempts(FeatureGuidePlacement placement) {
    switch (placement) {
      case FeatureGuidePlacement.above:
        return const [
          (direction: PopoverArrowDirection.bottom, allowClamp: true),
          (direction: PopoverArrowDirection.top, allowClamp: false),
          (direction: PopoverArrowDirection.left, allowClamp: false),
          (direction: PopoverArrowDirection.right, allowClamp: false),
        ];
      case FeatureGuidePlacement.below:
        return const [
          (direction: PopoverArrowDirection.top, allowClamp: true),
          (direction: PopoverArrowDirection.bottom, allowClamp: false),
          (direction: PopoverArrowDirection.left, allowClamp: false),
          (direction: PopoverArrowDirection.right, allowClamp: false),
        ];
      case FeatureGuidePlacement.left:
        return const [
          (direction: PopoverArrowDirection.right, allowClamp: true),
          (direction: PopoverArrowDirection.left, allowClamp: false),
          (direction: PopoverArrowDirection.bottom, allowClamp: false),
          (direction: PopoverArrowDirection.top, allowClamp: false),
        ];
      case FeatureGuidePlacement.right:
        return const [
          (direction: PopoverArrowDirection.left, allowClamp: true),
          (direction: PopoverArrowDirection.right, allowClamp: false),
          (direction: PopoverArrowDirection.bottom, allowClamp: false),
          (direction: PopoverArrowDirection.top, allowClamp: false),
        ];
      case FeatureGuidePlacement.auto:
        return const [
          (direction: PopoverArrowDirection.bottom, allowClamp: false),
          (direction: PopoverArrowDirection.top, allowClamp: false),
          (direction: PopoverArrowDirection.left, allowClamp: false),
          (direction: PopoverArrowDirection.right, allowClamp: false),
        ];
    }
  }

  Map<String, dynamic>? _computePlacement({
    required PopoverArrowDirection direction,
    required Offset targetPosition,
    required Size targetSize,
    required double targetCenterX,
    required double targetCenterY,
    required double safeTop,
    required double safeBottom,
    required double safeLeft,
    required double safeRight,
    required double popoverWidth,
    required double popoverMaxHeight,
    required double arrowSize,
    required bool requireInBounds,
  }) {
    double left;
    double top;
    double arrowOffset;

    switch (direction) {
      case PopoverArrowDirection.bottom:
        final desiredTop = targetPosition.dy - arrowSize - popoverMaxHeight;
        if (requireInBounds &&
            (desiredTop < safeTop ||
                targetCenterX - popoverWidth / 2 < safeLeft ||
                targetCenterX + popoverWidth / 2 > safeRight)) {
          return null;
        }

        left = (targetCenterX - popoverWidth / 2).clamp(
          safeLeft,
          safeRight - popoverWidth,
        );
        top = desiredTop.clamp(safeTop, safeBottom - popoverMaxHeight);
        arrowOffset = targetCenterX - left;
        break;
      case PopoverArrowDirection.top:
        final desiredTop = targetPosition.dy + targetSize.height + arrowSize;
        if (requireInBounds &&
            (desiredTop + popoverMaxHeight > safeBottom ||
                targetCenterX - popoverWidth / 2 < safeLeft ||
                targetCenterX + popoverWidth / 2 > safeRight)) {
          return null;
        }

        left = (targetCenterX - popoverWidth / 2).clamp(
          safeLeft,
          safeRight - popoverWidth,
        );
        top = desiredTop.clamp(safeTop, safeBottom - popoverMaxHeight);
        arrowOffset = targetCenterX - left;
        break;
      case PopoverArrowDirection.left:
        final desiredLeft = targetPosition.dx + targetSize.width + arrowSize;
        if (requireInBounds && desiredLeft + popoverWidth > safeRight) {
          return null;
        }

        left = desiredLeft.clamp(safeLeft, safeRight - popoverWidth);
        top = (targetCenterY - popoverMaxHeight / 2).clamp(
          safeTop,
          safeBottom - popoverMaxHeight,
        );
        arrowOffset = targetCenterY - top;
        break;
      case PopoverArrowDirection.right:
        final desiredLeft = targetPosition.dx - popoverWidth - arrowSize;
        if (requireInBounds && desiredLeft < safeLeft) {
          return null;
        }

        left = desiredLeft.clamp(safeLeft, safeRight - popoverWidth);
        top = (targetCenterY - popoverMaxHeight / 2).clamp(
          safeTop,
          safeBottom - popoverMaxHeight,
        );
        arrowOffset = targetCenterY - top;
        break;
    }

    return {
      'left': left,
      'top': top,
      'arrowDirection': direction,
      'arrowOffset': arrowOffset,
    };
  }

  /// 构建气泡卡片
  Widget _buildPopoverCard(
    BuildContext context,
    PopoverArrowDirection arrowDirection, {
    double arrowOffset = 0,
  }) {
    const arrowSize = 14.0;
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;

    final popoverContent = Container(
      constraints: const BoxConstraints(maxWidth: 220, minWidth: 180),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                color: theme.colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.guide.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _handleDismiss(),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.guide.description,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );

    Widget buildHorizontalArrow(bool isTop) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 220.0;
          final offset = arrowOffset
              .clamp(arrowSize, width - arrowSize)
              .toDouble();
          return Padding(
            padding: EdgeInsets.only(left: offset - arrowSize),
            child: CustomPaint(
              painter: _ArrowPainter(
                color: cardColor,
                direction: isTop
                    ? PopoverArrowDirection.top
                    : PopoverArrowDirection.bottom,
              ),
              size: const Size(arrowSize * 2, arrowSize),
            ),
          );
        },
      );
    }

    Widget buildVerticalArrow(bool isLeft) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 120.0;
          final offset = arrowOffset
              .clamp(arrowSize, height - arrowSize)
              .toDouble();
          return Padding(
            padding: EdgeInsets.only(top: offset - arrowSize),
            child: CustomPaint(
              painter: _ArrowPainter(
                color: cardColor,
                direction: isLeft
                    ? PopoverArrowDirection.left
                    : PopoverArrowDirection.right,
              ),
              size: const Size(arrowSize, arrowSize * 2),
            ),
          );
        },
      );
    }

    switch (arrowDirection) {
      case PopoverArrowDirection.top:
        return IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [buildHorizontalArrow(true), popoverContent],
          ),
        );
      case PopoverArrowDirection.bottom:
        return IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [popoverContent, buildHorizontalArrow(false)],
          ),
        );
      case PopoverArrowDirection.left:
        return IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [buildVerticalArrow(true), popoverContent],
          ),
        );
      case PopoverArrowDirection.right:
        return IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [popoverContent, buildVerticalArrow(false)],
          ),
        );
    }
  }
}

/// 箭头绘制器
class _ArrowPainter extends CustomPainter {
  final Color color;
  final PopoverArrowDirection direction;

  _ArrowPainter({required this.color, required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();

    switch (direction) {
      case PopoverArrowDirection.top:
        // 箭头向上
        path.moveTo(0, size.height);
        path.lineTo(size.width / 2, 0);
        path.lineTo(size.width, size.height);
        break;

      case PopoverArrowDirection.bottom:
        // 箭头向下
        path.moveTo(0, 0);
        path.lineTo(size.width / 2, size.height);
        path.lineTo(size.width, 0);
        break;

      case PopoverArrowDirection.left:
        // 箭头向左
        path.moveTo(size.width, 0);
        path.lineTo(0, size.height / 2);
        path.lineTo(size.width, size.height);
        break;

      case PopoverArrowDirection.right:
        // 箭头向右
        path.moveTo(0, 0);
        path.lineTo(size.width, size.height / 2);
        path.lineTo(0, size.height);
        break;
    }

    path.close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.18), 4, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.direction != direction;
  }
}
