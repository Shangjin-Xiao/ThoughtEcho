import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class AnniversaryAnimationOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const AnniversaryAnimationOverlay({super.key, required this.onDismiss});

  @override
  State<AnniversaryAnimationOverlay> createState() =>
      _AnniversaryAnimationOverlayState();
}

class _AnniversaryAnimationOverlayState
    extends State<AnniversaryAnimationOverlay> with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _confettiController;
  late final AnimationController _buttonController;
  late final Animation<Offset> _buttonSlide;
  bool _isVisible = false;
  final List<_ConfettiPiece> _confettiPieces = [];

  static const _immersiveOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _buttonSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _buttonController,
      curve: Curves.easeOutCubic,
    ));

    _setupConfetti();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_immersiveOverlayStyle);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isVisible = true;
      });
      _entryController.forward();

      // 蛋糕直接显示（SVG无需加载回调），1.5s后出现按钮
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _buttonController.forward();
      });
    });
  }

  void _setupConfetti() {
    final random = math.Random();
    for (int i = 0; i < 50; i++) {
      final shapeRoll = random.nextDouble();
      final _ConfettiShape shape;
      if (shapeRoll < 0.35) {
        shape = _ConfettiShape.ribbon;
      } else if (shapeRoll < 0.60) {
        shape = _ConfettiShape.square;
      } else if (shapeRoll < 0.80) {
        shape = _ConfettiShape.circle;
      } else {
        shape = _ConfettiShape.star;
      }
      _confettiPieces.add(
        _ConfettiPiece(
          color: _getConfettiColor(random),
          size: random.nextDouble() * 8 + 5,
          leftPercent: random.nextDouble(),
          startDelay: random.nextDouble(),
          duration: 5.0 + random.nextDouble() * 2.5,
          sway: 15 + random.nextDouble() * 35,
          shape: shape,
          flipSpeed: 2.0 + random.nextDouble() * 4.0,
          tumbleSpeed: 1.5 + random.nextDouble() * 3.0,
        ),
      );
    }
  }

  Color _getConfettiColor(math.Random random) {
    const colors = [
      Color(0xFFFFD700), // 金
      Color(0xFFFF6B9D), // 粉红
      Color(0xFF4ECDC4), // 青
      Color(0xFF45B7D1), // 天蓝
      Color(0xFF96CEB4), // 薄荷绿
      Color(0xFFB48EE0), // 浅紫
      Color(0xFFFF8C42), // 橙
    ];
    return colors[random.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _entryController.dispose();
    _confettiController.dispose();
    _buttonController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final l10n = AppLocalizations.of(context);
    final glassCardWidth = math.min(size.width * 0.85, 380.0);
    final cakeSize = (size.height * 0.22).clamp(100.0, 200.0);

    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _immersiveOverlayStyle,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 背景层：毛玻璃模糊 + 轻度深色遮罩，保留程序内容可见
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.38),
                  ),
                ),
              ),
              // 顶部微弱光晕
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.6),
                        radius: 0.9,
                        colors: [
                          const Color(0xFF0061FF).withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 彩带层
              ..._confettiPieces.map((p) => _buildConfettiWidget(p, size)),
              // 中央毛玻璃卡片
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      width: glassCardWidth,
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // SVG 蛋糕
                          SizedBox(
                            width: cakeSize,
                            height: cakeSize,
                            child: SvgPicture.asset(
                              'assets/svg/anniversary_cake.svg',
                              fit: BoxFit.contain,
                              placeholderBuilder: (context) => const Icon(
                                Icons.cake,
                                size: 88,
                                color: Color(0xFFFFD36B),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.anniversaryTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.3,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  offset: Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.anniversarySubtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              letterSpacing: 0.5,
                              color: Colors.white.withValues(alpha: 0.88),
                              shadows: const [
                                Shadow(
                                  color: Colors.black26,
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF0061FF).withValues(
                                  alpha: 0.50,
                                ),
                              ),
                            ),
                            child: Text(
                              l10n.anniversaryBannerSubtitle,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFA0C4FF),
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SlideTransition(
                            position: _buttonSlide,
                            child: FadeTransition(
                              opacity: _buttonController,
                              child: AnimatedBuilder(
                                animation: _buttonController,
                                builder: (context, child) => FilledButton.icon(
                                  onPressed: _buttonController.isCompleted
                                      ? widget.onDismiss
                                      : null,
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  label: Text(
                                    l10n.anniversaryEnterApp,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0061FF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 14,
                                    ),
                                  ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfettiWidget(_ConfettiPiece piece, Size screenSize) {
    return AnimatedBuilder(
      animation: _confettiController,
      builder: (context, child) {
        final cycleProgress =
            (_confettiController.value + piece.startDelay) % 1.0;
        final progress = math.min(1.0, cycleProgress * (6 / piece.duration));
        final yPos = (progress * (screenSize.height + 100)) - 50;
        final xOffset = math.sin(progress * math.pi * 4) * piece.sway;
        final rotation = progress * math.pi * piece.tumbleSpeed * 2;
        final opacity = progress < 0.1
            ? progress / 0.1
            : progress > 0.85
                ? (1 - progress) / 0.15
                : 1.0;
        // 3D 翻转效果：用 scaleX 模拟纸片正反面翻转
        final flipScaleX = math.cos(progress * math.pi * piece.flipSpeed).abs();
        // 轻微纵向拉伸，模拟空气阻力下的飘动
        final stretchY = 1.0 + math.sin(progress * math.pi * 3) * 0.15;

        return Positioned(
          top: yPos,
          left: (piece.leftPercent * screenSize.width) + xOffset,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationZ(rotation)
              ..multiply(Matrix4.diagonal3Values(
                flipScaleX.clamp(0.15, 1.0),
                stretchY,
                1.0,
              )),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: _buildConfettiShape(piece),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfettiShape(_ConfettiPiece piece) {
    final s = piece.size;
    switch (piece.shape) {
      case _ConfettiShape.ribbon:
        return Container(
          width: s * 1.8,
          height: s * 0.4,
          decoration: BoxDecoration(
            color: piece.color,
            borderRadius: BorderRadius.circular(s * 0.2),
          ),
        );
      case _ConfettiShape.square:
        return Container(
          width: s * 0.8,
          height: s * 0.8,
          decoration: BoxDecoration(
            color: piece.color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      case _ConfettiShape.circle:
        return Container(
          width: s * 0.7,
          height: s * 0.7,
          decoration: BoxDecoration(
            color: piece.color,
            shape: BoxShape.circle,
          ),
        );
      case _ConfettiShape.star:
        return CustomPaint(
          size: Size(s, s),
          painter: _StarPainter(color: piece.color),
        );
    }
  }
}

enum _ConfettiShape { ribbon, square, circle, star }

class _ConfettiPiece {
  final Color color;
  final double size;
  final double leftPercent;
  final double startDelay;
  final double duration;
  final double sway;
  final _ConfettiShape shape;
  final double flipSpeed;
  final double tumbleSpeed;

  _ConfettiPiece({
    required this.color,
    required this.size,
    required this.leftPercent,
    required this.startDelay,
    required this.duration,
    required this.sway,
    required this.shape,
    required this.flipSpeed,
    required this.tumbleSpeed,
  });
}

class _StarPainter extends CustomPainter {
  final Color color;
  const _StarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width / 2;
    final innerR = outerR * 0.4;
    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 72 - 90) * math.pi / 180;
      final innerAngle = ((i * 72) + 36 - 90) * math.pi / 180;
      final ox = cx + outerR * math.cos(outerAngle);
      final oy = cy + outerR * math.sin(outerAngle);
      final ix = cx + innerR * math.cos(innerAngle);
      final iy = cy + innerR * math.sin(innerAngle);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => old.color != color;
}
