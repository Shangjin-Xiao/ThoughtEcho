import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
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
  late final AnimationController _fireworksController;
  AnimationController? _lottieController;
  bool _showButton = false;
  bool _isVisible = false;
  bool _cakeLoaded = false;
  final List<_ConfettiPiece> _confettiPieces = [];
  final List<_FireworkBurst> _fireworkBursts = [];

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
      duration: const Duration(milliseconds: 300),
    );

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _fireworksController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _setupConfetti();
    _setupFireworks();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_immersiveOverlayStyle);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isVisible = true;
      });
      _entryController.forward();
    });
  }

  void _setupConfetti() {
    final random = math.Random();
    for (int i = 0; i < 28; i++) {
      _confettiPieces.add(_ConfettiPiece(
        color: _getConfettiColor(random),
        size: random.nextDouble() * 10 + 6,
        leftPercent: random.nextDouble(),
        startDelay: random.nextDouble(),
        duration: 4.0 + random.nextDouble() * 2.0,
        sway: 10 + random.nextDouble() * 26,
        isCircle: random.nextBool(),
      ));
    }
  }

  void _setupFireworks() {
    final random = math.Random();
    for (int i = 0; i < 5; i++) {
      _fireworkBursts.add(
        _FireworkBurst(
          xPercent: 0.16 + random.nextDouble() * 0.68,
          yPercent: 0.12 + random.nextDouble() * 0.3,
          radius: 46 + random.nextDouble() * 28,
          startDelay: i / 5,
          color: _getConfettiColor(random),
          particleCount: 10 + random.nextInt(6),
        ),
      );
    }
  }

  Color _getConfettiColor(math.Random random) {
    const colors = [
      Color(0xFFFFD700), // Gold
      Color(0xFFFF6B6B), // Red
      Color(0xFF4ECDC4), // Teal
      Color(0xFF45B7D1), // Sky
      Color(0xFF96CEB4), // Green
      Color(0xFFFFEEAD), // Yellow
    ];
    return colors[random.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _entryController.dispose();
    _confettiController.dispose();
    _fireworksController.dispose();
    _lottieController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _handleLottieLoaded(LottieComposition composition) {
    _lottieController?.dispose();
    setState(() {
      _cakeLoaded = true;
      _lottieController = AnimationController(
        vsync: this,
        duration: composition.duration,
      );
    });
    _lottieController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_showButton) {
        setState(() {
          _showButton = true;
        });
      }
    });
    _lottieController!.forward();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final l10n = AppLocalizations.of(context);
    final glassCardWidth = math.min(size.width * 0.85, 380.0);

    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _immersiveOverlayStyle,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF1B1036),
                        Color(0xFF24123B),
                        Color(0xFF09070F),
                      ],
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.28),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.55),
                        radius: 1.05,
                        colors: [
                          const Color(0xFFFFD36B).withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: _buildFireworksLayer()),
              ..._confettiPieces
                  .map((piece) => _buildConfettiWidget(piece, size)),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      width: glassCardWidth,
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.24),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        const Color(0xFFFFF0BF)
                                            .withValues(alpha: 0.34),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                  child: const SizedBox(
                                    width: 176,
                                    height: 176,
                                  ),
                                ),
                                AnimatedOpacity(
                                  opacity: _cakeLoaded ? 0.0 : 1.0,
                                  duration: const Duration(milliseconds: 240),
                                  child: const Icon(
                                    Icons.cake,
                                    size: 88,
                                    color: Color(0xFFFFD36B),
                                  ),
                                ),
                                RepaintBoundary(
                                  child: Lottie.asset(
                                    'assets/lottie/anniversary_cake.json',
                                    controller: _lottieController,
                                    repeat: false,
                                    animate: false,
                                    fit: BoxFit.contain,
                                    onLoaded: _handleLottieLoaded,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
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
                              color: Colors.white.withValues(alpha: 0.85),
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
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                            child: const Text(
                              'ThoughtEcho · 1st Anniversary',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFFFD700),
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
                                const SizedBox(height: 24),
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

  Widget _buildFireworksLayer() {
    return AnimatedBuilder(
      animation: _fireworksController,
      builder: (context, child) {
        return CustomPaint(
          painter: _FireworksPainter(
            progress: _fireworksController.value,
            bursts: _fireworkBursts,
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
        final progress = math.min(1.0, cycleProgress * (5 / piece.duration));
        double yPos = (progress * (screenSize.height + 100)) - 50;
        double xOffset = math.sin(progress * math.pi * 4) * piece.sway;
        double rotation = progress * math.pi * 6;
        final opacity = progress < 0.12
            ? progress / 0.12
            : progress > 0.82
                ? (1 - progress) / 0.18
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
                height: piece.size,
                decoration: BoxDecoration(
                  color: piece.color,
                  shape: piece.isCircle ? BoxShape.circle : BoxShape.rectangle,
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

class _FireworkBurst {
  final double xPercent;
  final double yPercent;
  final double radius;
  final double startDelay;
  final Color color;
  final int particleCount;

  _FireworkBurst({
    required this.xPercent,
    required this.yPercent,
    required this.radius,
    required this.startDelay,
    required this.color,
    required this.particleCount,
  });
}

class _FireworksPainter extends CustomPainter {
  final double progress;
  final List<_FireworkBurst> bursts;

  const _FireworksPainter({required this.progress, required this.bursts});

  @override
  void paint(Canvas canvas, Size size) {
    for (final burst in bursts) {
      final localProgress = (progress + burst.startDelay) % 1.0;
      final wave = Curves.easeOut.transform(localProgress);
      final center = Offset(
        size.width * burst.xPercent,
        size.height * burst.yPercent,
      );
      final alpha = localProgress < 0.78
          ? (1 - (localProgress / 0.78)).clamp(0.0, 1.0)
          : 0.0;
      if (alpha <= 0) {
        continue;
      }

      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
        ..color = burst.color.withValues(alpha: alpha * 0.22);
      canvas.drawCircle(center, burst.radius * (0.24 + wave * 0.72), glowPaint);

      for (int i = 0; i < burst.particleCount; i++) {
        final angle = (math.pi * 2 * i) / burst.particleCount;
        final distance = burst.radius * (0.18 + wave * 0.82);
        final end = Offset(
          center.dx + math.cos(angle) * distance,
          center.dy + math.sin(angle) * distance,
        );
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.2
          ..color = burst.color.withValues(alpha: alpha * 0.92);
        canvas.drawLine(center, end, strokePaint);

        final sparkPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: alpha * 0.95);
        canvas.drawCircle(end, 2.2, sparkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.bursts != bursts;
  }
}
