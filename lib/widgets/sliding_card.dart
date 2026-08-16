import 'package:flutter/material.dart';
import '../theme/theme_style.dart';
import 'common/paper_rule_background.dart';

class SlidingCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const SlidingCard({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  State<SlidingCard> createState() => _SlidingCardState();
}

class _SlidingCardState extends State<SlidingCard>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _hoverController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _hoverScaleAnimation;
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 悬停动画（Material Design 微交互）
    _hoverScaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() {
      _isPressed = true;
    });
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() {
      _isPressed = false;
    });
    _controller.reverse();
  }

  void _onTapCancel() {
    setState(() {
      _isPressed = false;
    });
    _controller.reverse();
  }

  void _onHoverEnter() {
    if (!_isPressed) {
      setState(() {
        _isHovered = true;
      });
      _hoverController.forward();
    }
  }

  void _onHoverExit() {
    setState(() {
      _isHovered = false;
    });
    _hoverController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    // 根据屏幕高度动态调整内边距
    double getResponsivePadding() {
      if (screenHeight < 550) {
        return 12.0; // 极小屏设备
      } else if (screenHeight < 600) {
        return 16.0; // 小屏设备
      } else if (screenHeight < 700) {
        return 20.0; // 中屏设备
      } else {
        return 24.0; // 大屏设备
      }
    }

    final cardPadding = getResponsivePadding();

    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _hoverController]),
      builder: (context, child) {
        // 组合点击和悬停的缩放效果
        final combinedScale =
            _scaleAnimation.value * _hoverScaleAnimation.value;

        // 根据状态选择阴影
        final shapeTokens = AppShapeTokens.of(context);
        List<BoxShadow> currentShadow;
        if (_isPressed) {
          currentShadow = shapeTokens.lowShadow;
        } else if (_isHovered) {
          currentShadow = shapeTokens.raisedShadow;
        } else {
          currentShadow = shapeTokens.restShadow;
        }

        return Transform.scale(
          scale: combinedScale,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: MouseRegion(
              onEnter: (_) => _onHoverEnter(),
              onExit: (_) => _onHoverExit(),
              child: GestureDetector(
                onTapDown: _onTapDown,
                onTapUp: _onTapUp,
                onTapCancel: _onTapCancel,
                onTap: widget.onTap,
                onDoubleTap: widget.onDoubleTap,
                child: Container(
                  padding: EdgeInsets.all(cardPadding), // 使用动态padding
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          AppShapeTokens.of(context).cardRadius),
                    ),
                    shadowColor: Colors.transparent,
                    // 三层叠放，顺序就是绘制顺序：底色 → 纸张横线 → 正文。
                    //
                    // 以前是 `PaperRuleBackground(child: AnimatedContainer(color: ...))`。
                    // `CustomPaint` 的 painter 画在 **child 之下**，而那个 child 带
                    // 不透明底色——横线被整个盖住，纸与墨的签名元素在这张卡上从来
                    // 没显示过（2026-08-16 扫描卡片内部像素确认：除了文字没有任何
                    // 周期性暗行）。笔记卡那边没踩到，是因为它包的是正文本身，
                    // 正文没有底色。
                    //
                    // 横线必须满卡片宽，所以 padding 挪到横线层**里面**，
                    // 不能再让它把纹理缩进去。
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppShapeTokens.of(context).cardRadius,
                            ),
                            boxShadow: currentShadow,
                            color: AppSurfaceTokens.of(context).card,
                            // 边框：material 保持原来那道几乎看不见的 8% 描边（它靠投影
                            // 分层），手工风格用发丝边框实打实描一道——纸的层次本来就
                            // 由描边承担，投影已经被令牌压到最低。判据是 borderWidth
                            // 这个**取值**，不是风格身份：颜色和宽度都从它来，
                            // 令牌把描边调粗时这里要跟着粗，写死 1 就等于令牌只管了一半。
                            border: Border.all(
                              color: _isHovered
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.12,
                                    )
                                  : (shapeTokens.borderWidth > 0
                                      ? theme.colorScheme.outlineVariant
                                      : theme.colorScheme.outline.withValues(
                                          alpha: 0.08,
                                        )),
                              width: shapeTokens.borderWidth > 0
                                  ? shapeTokens.borderWidth
                                  : 1,
                            ),
                          ),
                        ),
                        PaperRuleBackground(
                          borderRadius: BorderRadius.circular(
                            AppShapeTokens.of(context).cardRadius,
                          ),
                          // 令牌关掉纹理时这一层退化成一个空盒子，不产生绘制。
                          child: const SizedBox.expand(),
                        ),
                        Padding(
                          padding: EdgeInsets.all(cardPadding), // 使用动态padding
                          // 正文在卡片里垂直居中。原来由 AnimatedContainer 的
                          // alignment 承担，拆层之后交给 Center。
                          child: Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 引用图标增强效果
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: EdgeInsets.all(_isHovered ? 4 : 0),
                                    decoration: BoxDecoration(
                                      color: _isHovered
                                          ? theme.colorScheme.primary
                                              .withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Icon(
                                      Icons.format_quote,
                                      size: 40,
                                      color: _isHovered
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  widget.child,
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
