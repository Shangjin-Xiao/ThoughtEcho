import 'package:flutter/material.dart';
import '../models/feature_guide.dart';

/// 气泡箭头方向
enum PopoverArrowDirection {
  top,    // 箭头在顶部，气泡在下方
  bottom, // 箭头在底部，气泡在上方
  left,   // 箭头在左侧，气泡在右方
  right,  // 箭头在右侧，气泡在左方
}

/// 功能引导 Popover 气泡组件
/// 轻量级提示，带箭头指向目标元素
class FeatureGuidePopover extends StatefulWidget {
  final FeatureGuide guide;
  final VoidCallback onDismiss;
  final Duration autoDismissDuration;

  const FeatureGuidePopover({
    super.key,
    required this.guide,
    required this.onDismiss,
    this.autoDismissDuration = const Duration(seconds: 5),
  });

  @override
  State<FeatureGuidePopover> createState() => _FeatureGuidePopoverState();
}

class _FeatureGuidePopoverState extends State<FeatureGuidePopover>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200), // 加快动画速度
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward();

    // 自动消失
    Future.delayed(widget.autoDismissDuration, () {
      if (mounted) {
        _handleDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() async {
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
        onTap: _handleDismiss,
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildPopoverCard(context, PopoverArrowDirection.top),
          ),
        ),
      ),
    );
  }

  /// 构建定位的气泡（带箭头）
  Widget _buildPositionedPopover(BuildContext context, RenderBox targetBox) {
    final targetSize = targetBox.size;
    final targetPosition = targetBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // 计算最佳显示位置和箭头方向
    final positioning = _calculateBestPosition(
      targetPosition: targetPosition,
      targetSize: targetSize,
      screenSize: screenSize,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 透明可点击遮罩层（点击关闭）
          GestureDetector(
            onTap: _handleDismiss,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

        // 气泡卡片
        Positioned(
          left: positioning['left'],
          top: positioning['top'],
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
  }) {
    const popoverWidth = 220.0; // 缩小宽度
    const popoverMaxHeight = 120.0; // 缩小高度
    const arrowSize = 8.0; // 缩小箭头
    const margin = 12.0;

    final targetCenterX = targetPosition.dx + targetSize.width / 2;
    final targetCenterY = targetPosition.dy + targetSize.height / 2;

    // 优先显示在下方
    if (targetPosition.dy + targetSize.height + arrowSize + popoverMaxHeight + margin < screenSize.height) {
      return {
        'left': (targetCenterX - popoverWidth / 2).clamp(margin, screenSize.width - popoverWidth - margin),
        'top': targetPosition.dy + targetSize.height + arrowSize,
        'arrowDirection': PopoverArrowDirection.top,
        'arrowOffset': targetCenterX,
      };
    }

    // 其次尝试上方
    if (targetPosition.dy - arrowSize - popoverMaxHeight > margin) {
      return {
        'left': (targetCenterX - popoverWidth / 2).clamp(margin, screenSize.width - popoverWidth - margin),
        'top': targetPosition.dy - arrowSize - popoverMaxHeight,
        'arrowDirection': PopoverArrowDirection.bottom,
        'arrowOffset': targetCenterX,
      };
    }

    // 尝试右侧
    if (targetPosition.dx + targetSize.width + arrowSize + popoverWidth + margin < screenSize.width) {
      return {
        'left': targetPosition.dx + targetSize.width + arrowSize,
        'top': (targetCenterY - popoverMaxHeight / 2).clamp(margin, screenSize.height - popoverMaxHeight - margin),
        'arrowDirection': PopoverArrowDirection.left,
        'arrowOffset': targetCenterY,
      };
    }

    // 最后尝试左侧
    return {
      'left': targetPosition.dx - popoverWidth - arrowSize,
      'top': (targetCenterY - popoverMaxHeight / 2).clamp(margin, screenSize.height - popoverMaxHeight - margin),
      'arrowDirection': PopoverArrowDirection.right,
      'arrowOffset': targetCenterY,
    };
  }

  /// 构建气泡卡片
  Widget _buildPopoverCard(
    BuildContext context,
    PopoverArrowDirection arrowDirection, {
    double arrowOffset = 0,
  }) {
    const arrowSize = 8.0;

    Widget popoverContent = Container(
      constraints: const BoxConstraints(
        maxWidth: 220,
        minWidth: 180,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                color: Theme.of(context).primaryColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.guide.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Theme.of(context).primaryColor,
                      ),
                ),
              ),
              // 关闭按钮
              GestureDetector(
                onTap: _handleDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 描述内容
          Text(
            widget.guide.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );

    // 根据箭头方向组合卡片和箭头
    switch (arrowDirection) {
      case PopoverArrowDirection.top:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              painter: _ArrowPainter(
                color: Theme.of(context).cardColor,
                direction: arrowDirection,
              ),
              size: const Size(arrowSize * 2, arrowSize),
            ),
            popoverContent,
          ],
        );

      case PopoverArrowDirection.bottom:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            popoverContent,
            CustomPaint(
              painter: _ArrowPainter(
                color: Theme.of(context).cardColor,
                direction: arrowDirection,
              ),
              size: const Size(arrowSize * 2, arrowSize),
            ),
          ],
        );

      case PopoverArrowDirection.left:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              painter: _ArrowPainter(
                color: Theme.of(context).cardColor,
                direction: arrowDirection,
              ),
              size: const Size(arrowSize, arrowSize * 2),
            ),
            popoverContent,
          ],
        );

      case PopoverArrowDirection.right:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            popoverContent,
            CustomPaint(
              painter: _ArrowPainter(
                color: Theme.of(context).cardColor,
                direction: arrowDirection,
              ),
              size: const Size(arrowSize, arrowSize * 2),
            ),
          ],
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
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.direction != direction;
  }
}
