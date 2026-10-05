import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:thoughtecho/utils/lottie_animation_manager.dart';
import 'package:thoughtecho/widgets/common/lottie_animation_widget.dart';
import 'package:thoughtecho/widgets/lottie_loading_widget.dart';

void main() {
  testWidgets(
      'EnhancedLottieAnimation uses a single internal RepaintBoundary without redundant outer boundary',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EnhancedLottieAnimation(
            type: LottieAnimationType.loading,
          ),
        ),
      ),
    );

    final boundaries = find.descendant(
      of: find.byType(EnhancedLottieAnimation),
      matching: find.byType(RepaintBoundary),
    );
    expect(boundaries, findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(Lottie),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'LottieAnimationWidget uses a single internal RepaintBoundary without redundant outer boundary',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LottieAnimationWidget(
            animationPath: 'assets/lottie/custom_loading.json',
          ),
        ),
      ),
    );

    final boundaries = find.descendant(
      of: find.byType(LottieAnimationWidget),
      matching: find.byType(RepaintBoundary),
    );
    expect(boundaries, findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(Lottie),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'LottieLoadingWidget relies on Lottie internal RepaintBoundary and keeps Text outside RepaintBoundary',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LottieLoadingWidget(
            text: 'Loading...',
            showText: true,
          ),
        ),
      ),
    );

    final boundaries = find.descendant(
      of: find.byType(LottieLoadingWidget),
      matching: find.byType(RepaintBoundary),
    );
    expect(boundaries, findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(Lottie),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );

    final textInsideBoundary = find.descendant(
      of: boundaries,
      matching: find.byType(Text),
    );
    expect(textInsideBoundary, findsNothing);
  });

  testWidgets(
      'LottieLoadingButton uses a single internal RepaintBoundary without redundant outer boundary',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LottieLoadingButton(),
        ),
      ),
    );

    final boundaries = find.descendant(
      of: find.byType(LottieLoadingButton),
      matching: find.byType(RepaintBoundary),
    );
    expect(boundaries, findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(Lottie),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
  });
}
