import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/lottie_animation_manager.dart';
import 'package:thoughtecho/widgets/common/lottie_animation_widget.dart';
import 'package:thoughtecho/widgets/lottie_loading_widget.dart';

void main() {
  testWidgets('EnhancedLottieAnimation is wrapped in RepaintBoundary',
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

    expect(
      find.descendant(
        of: find.byType(EnhancedLottieAnimation),
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('LottieAnimationWidget is wrapped in RepaintBoundary',
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

    expect(
      find.descendant(
        of: find.byType(LottieAnimationWidget),
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('LottieLoadingWidget is wrapped in RepaintBoundary',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LottieLoadingWidget(
            showText: false,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(LottieLoadingWidget),
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('LottieLoadingButton is wrapped in RepaintBoundary',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LottieLoadingButton(),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(LottieLoadingButton),
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(1),
    );
  });
}
