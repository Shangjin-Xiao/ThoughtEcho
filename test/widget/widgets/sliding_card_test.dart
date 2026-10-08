import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/sliding_card.dart';

void main() {
  Widget buildTestWidget({
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    Size size = const Size(800, 600),
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: SlidingCard(
                onTap: onTap,
                onDoubleTap: onDoubleTap,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'SlidingCard renders child correctly without Opacity in static state',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        child: const Text('Test Card Content'),
      ),
    );

    expect(find.text('Test Card Content'), findsOneWidget);
    expect(find.byType(AnimatedScale), findsOneWidget);

    // In static state (unpressed, opacity == 1.0), Opacity / AnimatedOpacity must NOT be rendered.
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('SlidingCard wraps card with AnimatedOpacity during press',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        child: const Text('Test Card Content'),
      ),
    );

    final gestureFinder = find.byType(GestureDetector);
    expect(gestureFinder, findsOneWidget);

    // Press down
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(gestureFinder));
    await tester.pump();

    // Now AnimatedOpacity should be present
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    final animatedOpacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedOpacity.opacity, 0.85);

    // Release tap
    await gesture.up();
    await tester.pumpAndSettle();

    // Static state again: AnimatedOpacity should disappear
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('SlidingCard triggers onTap callback',
      (WidgetTester tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      buildTestWidget(
        child: const Text('Interactive Content'),
        onTap: () => tapped = true,
      ),
    );

    await tester.tap(find.text('Interactive Content'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('SlidingCard triggers onDoubleTap callback',
      (WidgetTester tester) async {
    bool doubleTapped = false;

    await tester.pumpWidget(
      buildTestWidget(
        child: const Text('Interactive Content'),
        onDoubleTap: () => doubleTapped = true,
      ),
    );

    await tester.tap(find.text('Interactive Content'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Interactive Content'));
    await tester.pumpAndSettle();
    expect(doubleTapped, isTrue);
  });

  testWidgets('SlidingCard responds smoothly to hover gestures',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        child: const Text('Hover Content'),
      ),
    );

    final slidingCardFinder = find.byType(SlidingCard);
    expect(slidingCardFinder, findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();

    // Move pointer inside card
    await gesture.moveTo(tester.getCenter(slidingCardFinder));
    await tester.pumpAndSettle();

    final animatedScale =
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(animatedScale.scale, 1.02);

    // Move pointer outside
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    final animatedScaleAfter =
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(animatedScaleAfter.scale, 1.0);
  });
}
