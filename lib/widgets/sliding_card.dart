import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SlidingCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSlideComplete;

  const SlidingCard({super.key, required this.child, this.onSlideComplete});

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
        List<BoxShadow> currentShadow;
        if (_isPressed) {
          currentShadow = AppTheme.lightShadow;
        } else if (_isHovered) {
          currentShadow = AppTheme.hoverShadow;
        } else {
          currentShadow = AppTheme.defaultShadow;
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
                onHorizontalDragEnd: (details) {
                  // 检测左滑动作
                  if (details.primaryVelocity != null &&
                      details.primaryVelocity! < 0 &&
                      widget.onSlideComplete != null) {
                    widget.onSlideComplete!();
                  }                },
                child: Container(
                  padding: EdgeInsets.all(cardPadding), // 使用动态padding
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    ),
                    shadowColor: Colors.transparent,
                    child: AnimatedContainer(                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.all(cardPadding), // 使用动态padding
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppTheme.cardRadius,
                        ),
                        boxShadow: currentShadow,
                        color: theme.brightness == Brightness.light
                            ? Colors.white
                            : theme.colorScheme.surface,
                        // 微妙的边框效果（Material Design）
                        border: Border.all(
                          color: _isHovered
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                )
                              : theme.colorScheme.outline.withValues(
                                  alpha: 0.08,
                                ),
                          width: 1,
                        ),
                      ),
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
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.08,
                                      )
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
                            if (widget.onSlideComplete != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: _isHovered ? 0.8 : 0.5,
                                  child: Text(
                                    '← 左滑添加到笔记',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5),
                                      fontStyle: FontStyle.italic,
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
            ),
          ),
        );
      },
    );
  }
}
