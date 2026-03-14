import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
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
  AnimationController? _lottieController;
  bool _showButton = false;
  bool _isVisible = false;
  final List<_ConfettiPiece> _confettiPieces = [];

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

    _setupConfetti();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isVisible = true;
      });
      _entryController.forward();
    });
  }

  void _setupConfetti() {
    final random = math.Random();
    for (int i = 0; i < 20; i++) {
      _confettiPieces.add(_ConfettiPiece(
        color: _getConfettiColor(random),
        size: random.nextDouble() * 10 + 6,
        leftPercent: random.nextDouble(),
        startDelay: random.nextDouble(),
        duration: 4.0 + random.nextDouble() * 2.0,
        isCircle: random.nextBool(),
      ));
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
    _lottieController?.dispose();
    super.dispose();
  }

  void _handleLottieLoaded(LottieComposition composition) {
    setState(() {
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Backdrop Blur
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ),

            // Confetti
            ..._confettiPieces
                .map((piece) => _buildConfettiWidget(piece, size)),

            // Glass Card
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    width: glassCardWidth,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Lottie Cake
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: Lottie.asset(
                            'assets/lottie/anniversary_cake.json',
                            controller: _lottieController,
                            repeat: false,
                            animate:
                                false, // Will be controlled by _lottieController
                            onLoaded: _handleLottieLoaded,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Title
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
                        // Subtitle
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
                        const SizedBox(height: 8),
                        // Anniversary Label
                        const Text(
                          'ThoughtEcho · 1st Anniversary',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFFFD700), // Golden
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // Animated Button
                        AnimatedOpacity(
                          opacity: _showButton ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 600),
                          child: Column(
                            children: [
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed:
                                    _showButton ? widget.onDismiss : null,
                                icon: const Icon(Icons.celebration,
                                    color: Colors.black),
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
    );
  }

  Widget _buildConfettiWidget(_ConfettiPiece piece, Size screenSize) {
    return AnimatedBuilder(
      animation: _confettiController,
      builder: (context, child) {
        double progress = (_confettiController.value + piece.startDelay) % 1.0;
        double yPos = (progress * (screenSize.height + 100)) - 50;
        double xOffset = math.sin(progress * math.pi * 4) * 20;
        double rotation = progress * math.pi * 6;

        return Positioned(
          top: yPos,
          left: (piece.leftPercent * screenSize.width) + xOffset,
          child: Transform.rotate(
            angle: rotation,
            child: Container(
              width: piece.size,
              height: piece.size,
              decoration: BoxDecoration(
                color: piece.color,
                shape: piece.isCircle ? BoxShape.circle : BoxShape.rectangle,
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
  final bool isCircle;

  _ConfettiPiece({
    required this.color,
    required this.size,
    required this.leftPercent,
    required this.startDelay,
    required this.duration,
    required this.isCircle,
  });
}
