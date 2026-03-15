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
  late final AnimationController _cannonController;
  bool _showButton = false;
  bool _isVisible = false;
  final List<_ConfettiPiece> _confettiPieces = [];
  final List<_CannonBurst> _cannonBursts = [];

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

    // 礼花炮：每 3s 一轮
    _cannonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _setupConfetti();
    _setupCannonBursts();
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
        setState(() {
          _showButton = true;
        });
      });
    });
  }

  void _setupConfetti() {
    final random = math.Random();
    for (int i = 0; i < 36; i++) {
      _confettiPieces.add(
        _ConfettiPiece(
          color: _getConfettiColor(random),
          size: random.nextDouble() * 9 + 5,
          leftPercent: random.nextDouble(),
          startDelay: random.nextDouble(),
          duration: 4.5 + random.nextDouble() * 2.0,
          sway: 12 + random.nextDouble() * 28,
          isCircle: random.nextBool(),
        ),
      );
    }
  }

  void _setupCannonBursts() {
    final random = math.Random();
    // 左右各一门礼花炮，各3波粒子
    final positions = [
      // 左侧炮口
      _CannonBurst(
        originXPercent: 0.04,
        originYPercent: 0.72,
        spreadAngle: -math.pi / 5, // 向右上方喷射
        color: _getConfettiColor(random),
        particleCount: 18,
        startDelay: 0.0,
      ),
      _CannonBurst(
        originXPercent: 0.04,
        originYPercent: 0.72,
        spreadAngle: -math.pi / 5,
        color: _getConfettiColor(random),
        particleCount: 18,
        startDelay: 0.33,
      ),
      _CannonBurst(
        originXPercent: 0.04,
        originYPercent: 0.72,
        spreadAngle: -math.pi / 5,
        color: _getConfettiColor(random),
        particleCount: 18,
        startDelay: 0.66,
      ),
      // 右侧炮口
      _CannonBurst(
        originXPercent: 0.96,
        originYPercent: 0.72,
        spreadAngle: -math.pi * 4 / 5, // 向左上方喷射
        color: _getConfettiColor(random),
        particleCount: 18,
        startDelay: 0.16,
      ),
      _CannonBurst(
        originXPercent: 0.96,
        originYPercent: 0.72,
        spreadAngle: -math.pi * 4 / 5,
        color: _getConfettiColor(random),
        particleCount: 18,
        startDelay: 0.49,
      ),
      _CannonBurst(
        originXPercent: 0.96,
        originYPercent: 0.72,
        spreadAngle: -math.pi * 4 / 5,
        color: _getConfettiColor(random),
        particleCount: 18,
        startDelay: 0.82,
      ),
    ];
    _cannonBursts.addAll(positions);
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
    _cannonController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final l10n = AppLocalizations.of(context);
    final glassCardWidth = math.min(size.width * 0.85, 380.0);

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
                          const Color(0xFFB48EE0).withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 礼花炮粒子层
              Positioned.fill(child: _buildCannonLayer()),
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
                            width: 200,
                            height: 200,
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
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFB48EE0).withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                            child: const Text(
                              'ThoughtEcho · 1st Anniversary',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD4AAFF),
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: _showButton ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 600),
                            child: Column(
                              children: [
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed:
                                      _showButton ? widget.onDismiss : null,
                                  icon: const Icon(
                                    Icons.celebration,
                                    color: Colors.black,
                                  ),
                                  label: Text(
                                    l10n.anniversaryEnterApp,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFD700),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ],
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

  Widget _buildCannonLayer() {
    return AnimatedBuilder(
      animation: _cannonController,
      builder: (context, child) {
        return CustomPaint(
          painter: _CannonPainter(
            progress: _cannonController.value,
            bursts: _cannonBursts,
          ),
          child: const SizedBox.expand(),
        );
      },
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
        final rotation = progress * math.pi * 6;
        final opacity = progress < 0.1
            ? progress / 0.1
            : progress > 0.85
                ? (1 - progress) / 0.15
                : 1.0;

        return Positioned(
          top: yPos,
          left: (piece.leftPercent * screenSize.width) + xOffset,
          child: Transform.rotate(
            angle: rotation,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                width: piece.size,
                height: piece.isCircle ? piece.size : piece.size * 0.45,
                decoration: BoxDecoration(
                  color: piece.color,
                  shape: piece.isCircle ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius:
                      piece.isCircle ? null : BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConfettiPiece {
  final Color color;
  final double size;
  final double leftPercent;
  final double startDelay;
  final double duration;
  final double sway;
  final bool isCircle;

  _ConfettiPiece({
    required this.color,
    required this.size,
    required this.leftPercent,
    required this.startDelay,
    required this.duration,
    required this.sway,
    required this.isCircle,
  });
}

/// 礼花炮爆发数据
class _CannonBurst {
  final double originXPercent; // 炮口 x 位置（屏幕比例）
  final double originYPercent; // 炮口 y 位置（屏幕比例）
  final double spreadAngle; // 喷射中心角（弧度，0=向右，-pi/2=向上）
  final Color color;
  final int particleCount;
  final double startDelay; // 0.0-1.0，相对于炮管周期的延迟

  const _CannonBurst({
    required this.originXPercent,
    required this.originYPercent,
    required this.spreadAngle,
    required this.color,
    required this.particleCount,
    required this.startDelay,
  });
}

/// 礼花炮绘制器：每个 burst 向扇形方向喷出粒子流，粒子受重力下落
class _CannonPainter extends CustomPainter {
  final double progress;
  final List<_CannonBurst> bursts;

  const _CannonPainter({required this.progress, required this.bursts});

  static const double _spreadHalfAngle = math.pi / 5.5; // 喷射扇角半宽
  static const double _gravity = 0.35; // 模拟重力（px/unit²）

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // 固定 seed，保证粒子路径一致

    for (final burst in bursts) {
      final localProgress = (progress + burst.startDelay) % 1.0;
      // 每波持续约 0.5 个周期，超出后隐藏
      if (localProgress > 0.52) continue;

      final t = localProgress / 0.52; // 0→1 内的进度
      final fadeOut = t > 0.72 ? (1 - t) / 0.28 : 1.0; // 最后 28% 淡出
      if (fadeOut <= 0) continue;

      final originX = size.width * burst.originXPercent;
      final originY = size.height * burst.originYPercent;

      for (int i = 0; i < burst.particleCount; i++) {
        // 每颗粒子有随机偏角和速度
        final seedOffset = i * 7919; // 大质数散列
        final rng = math.Random(random.nextInt(0xFFFFFF) + seedOffset);
        final angleOffset = (rng.nextDouble() - 0.5) * 2 * _spreadHalfAngle;
        final angle = burst.spreadAngle + angleOffset;
        final speed = 220 + rng.nextDouble() * 160; // 像素速度

        // 位置 = origin + v * t + 0.5 * g * t²（y 轴向下为正）
        final vx = math.cos(angle) * speed;
        final vy = math.sin(angle) * speed;
        final px = originX + vx * t;
        final py = originY + vy * t + 0.5 * _gravity * size.height * t * t;

        // 跳过飞出屏幕的粒子
        if (px < -10 || px > size.width + 10 || py > size.height + 10) {
          continue;
        }

        final alpha = (fadeOut * 0.95).clamp(0.0, 1.0);
        final particleSize = 5.5 + rng.nextDouble() * 3.5;
        final rotation = t * math.pi * 8 + i * 0.43;

        final paint = Paint()
          ..color = burst.color.withValues(alpha: alpha)
          ..style = PaintingStyle.fill;

        canvas.save();
        canvas.translate(px, py);
        canvas.rotate(rotation);

        // 礼花纸片：细长矩形或圆形混合
        if (i % 3 == 0) {
          // 圆形小球
          canvas.drawCircle(Offset.zero, particleSize * 0.45, paint);
        } else {
          // 彩带纸片
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: particleSize,
              height: particleSize * 0.38,
            ),
            paint,
          );
        }

        // 为每颗粒子叠加一个白色小高光
        final highlightPaint = Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.45)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(-particleSize * 0.15, -particleSize * 0.15),
          particleSize * 0.18,
          highlightPaint,
        );

        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CannonPainter old) =>
      old.progress != progress || old.bursts != bursts;
}
