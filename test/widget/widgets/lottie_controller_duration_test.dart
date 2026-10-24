import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:thoughtecho/utils/lottie_animation_manager.dart';
import 'package:thoughtecho/widgets/common/lottie_animation_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnhancedLottieAnimation Duration & Lifecycle Tests', () {
    testWidgets(
        'Sets controller duration from composition when widget.duration is null',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnhancedLottieAnimation(
              type: LottieAnimationType.loading,
              autoPlay: true,
              repeat: false,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      expect(controller, isNotNull);
      expect(controller!.duration, isNotNull);
      expect(controller.duration! > Duration.zero, isTrue);
    });

    testWidgets('Preserves explicit widget.duration when provided',
        (WidgetTester tester) async {
      const customDuration = Duration(milliseconds: 1500);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnhancedLottieAnimation(
              type: LottieAnimationType.loading,
              duration: customDuration,
              autoPlay: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      expect(controller!.duration, equals(customDuration));
    });

    testWidgets(
        'Triggers onComplete callback when non-repeating animation completes',
        (WidgetTester tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedLottieAnimation(
              type: LottieAnimationType.loading,
              autoPlay: true,
              repeat: false,
              onComplete: () {
                completed = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      final duration = controller!.duration!;

      // Advance time past the total duration
      await tester.pump(duration + const Duration(milliseconds: 100));

      expect(completed, isTrue);
    });
  });

  group('LottieAnimationWidget Speed & Duration Tests', () {
    testWidgets('Calculates duration accurately with default speed (1.0)',
        (WidgetTester tester) async {
      bool loaded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              speed: 1.0,
              autoPlay: true,
              repeat: false,
              onLoaded: () {
                loaded = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(loaded, isTrue);
      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      expect(controller, isNotNull);
      expect(controller!.duration, isNotNull);
      expect(controller.duration! > Duration.zero, isTrue);
    });

    testWidgets(
        'Scales duration based on speed parameter (2.0x speed -> 0.5x duration)',
        (WidgetTester tester) async {
      Duration? normalDuration;
      Duration? fastDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              speed: 1.0,
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      normalDuration = (tester.widget<Lottie>(find.byType(Lottie)).controller
              as AnimationController?)
          ?.duration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              speed: 2.0,
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      fastDuration = (tester.widget<Lottie>(find.byType(Lottie)).controller
              as AnimationController?)
          ?.duration;

      expect(normalDuration, isNotNull);
      expect(fastDuration, isNotNull);
      expect(
        fastDuration!.inMilliseconds,
        equals((normalDuration!.inMilliseconds / 2.0).round()),
      );
    });

    testWidgets('Handles speed <= 0 safely without division by zero',
        (WidgetTester tester) async {
      Duration? normalDuration;
      Duration? zeroSpeedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              speed: 1.0,
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      normalDuration = (tester.widget<Lottie>(find.byType(Lottie)).controller
              as AnimationController?)
          ?.duration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              speed: 0.0,
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      zeroSpeedDuration = (tester.widget<Lottie>(find.byType(Lottie)).controller
              as AnimationController?)
          ?.duration;

      expect(zeroSpeedDuration, equals(normalDuration));
    });

    testWidgets(
        'Triggers onCompleted callback when non-repeating animation finishes',
        (WidgetTester tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              autoPlay: true,
              repeat: false,
              onCompleted: () {
                completed = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      final duration = controller!.duration!;

      await tester.pump(duration + const Duration(milliseconds: 100));

      expect(completed, isTrue);
    });

    testWidgets(
        'Preserves external controller and safely populates duration if null',
        (WidgetTester tester) async {
      final externalController = AnimationController(vsync: const TestVSync());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              controller: externalController,
              autoPlay: false,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(externalController.duration, isNotNull);
      expect(externalController.duration! > Duration.zero, isTrue);

      externalController.dispose();
    });

    testWidgets(
        'Updates speed dynamically and re-triggers repeating animation in didUpdateWidget',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              speed: 1.0,
              repeat: true,
              autoPlay: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      expect(controller, isNotNull);
      final initialDuration = controller!.duration!;
      expect(controller.isAnimating, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              speed: 2.0,
              repeat: true,
              autoPlay: true,
            ),
          ),
        ),
      );

      expect(
        controller.duration!.inMilliseconds,
        equals((initialDuration.inMilliseconds / 2.0).round()),
      );
      expect(controller.isAnimating, isTrue);
    });

    testWidgets(
        'Does not clobber external controller duration when speed changes in didUpdateWidget',
        (WidgetTester tester) async {
      final customDuration = const Duration(milliseconds: 3000);
      final externalController = AnimationController(
        vsync: const TestVSync(),
        duration: customDuration,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              controller: externalController,
              speed: 1.0,
              autoPlay: false,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(externalController.duration, equals(customDuration));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LottieAnimationWidget(
              animationPath: 'assets/lottie/custom_loading.json',
              controller: externalController,
              speed: 2.0,
              autoPlay: false,
            ),
          ),
        ),
      );

      expect(externalController.duration, equals(customDuration));

      externalController.dispose();
    });
  });

  group('EnhancedLottieAnimation didUpdateWidget Tests', () {
    testWidgets(
        'Updates duration dynamically and re-triggers repeating animation in didUpdateWidget',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnhancedLottieAnimation(
              type: LottieAnimationType.loading,
              duration: Duration(milliseconds: 1000),
              repeat: true,
              autoPlay: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      expect(controller, isNotNull);
      expect(controller!.duration, equals(const Duration(milliseconds: 1000)));
      expect(controller.isAnimating, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnhancedLottieAnimation(
              type: LottieAnimationType.loading,
              duration: Duration(milliseconds: 500),
              repeat: true,
              autoPlay: true,
            ),
          ),
        ),
      );

      expect(controller.duration, equals(const Duration(milliseconds: 500)));
      expect(controller.isAnimating, isTrue);
    });

    testWidgets(
        'Updates duration dynamically and re-triggers forward animation in didUpdateWidget',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnhancedLottieAnimation(
              type: LottieAnimationType.loading,
              duration: Duration(milliseconds: 1000),
              repeat: false,
              autoPlay: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final lottieWidget = tester.widget<Lottie>(find.byType(Lottie));
      final controller = lottieWidget.controller as AnimationController?;
      expect(controller, isNotNull);
      expect(controller!.duration, equals(const Duration(milliseconds: 1000)));
      expect(controller.isAnimating, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnhancedLottieAnimation(
              type: LottieAnimationType.loading,
              duration: Duration(milliseconds: 500),
              repeat: false,
              autoPlay: true,
            ),
          ),
        ),
      );

      expect(controller.duration, equals(const Duration(milliseconds: 500)));
      expect(controller.isAnimating, isTrue);
    });
  });
}
