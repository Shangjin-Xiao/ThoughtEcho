import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/pulse_animation.dart';

void main() {
  testWidgets(
      'PulseAnimation renders child widget correctly and animates opacity',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PulseAnimation(
            minOpacity: 0.2,
            maxOpacity: 0.8,
            duration: Duration(seconds: 1),
            child: Text('Test Pulse Child'),
          ),
        ),
      ),
    );

    expect(find.text('Test Pulse Child'), findsOneWidget);

    final opacityFinder = find.ancestor(
      of: find.text('Test Pulse Child'),
      matching: find.byType(Opacity),
    );
    expect(opacityFinder, findsOneWidget);

    // Initial opacity at begin (0.2)
    Opacity opacityWidget = tester.widget<Opacity>(opacityFinder);
    expect(opacityWidget.opacity, equals(0.2));

    // Advance 500ms (halfway)
    await tester.pump(const Duration(milliseconds: 500));
    opacityWidget = tester.widget<Opacity>(opacityFinder);
    expect(opacityWidget.opacity, closeTo(0.5, 0.1));

    // Advance another 500ms to end (1.0s)
    await tester.pump(const Duration(milliseconds: 500));
    opacityWidget = tester.widget<Opacity>(opacityFinder);
    expect(opacityWidget.opacity, closeTo(0.8, 0.05));
  });

  testWidgets(
      'PulseAnimation reuses child widget subtree without rebuilding child during animation ticks',
      (WidgetTester tester) async {
    int childBuildCount = 0;

    Widget buildTrackerChild() {
      return Builder(
        builder: (context) {
          childBuildCount++;
          return const Text('Tracked Child');
        },
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseAnimation(
            duration: const Duration(seconds: 1),
            child: buildTrackerChild(),
          ),
        ),
      ),
    );

    expect(childBuildCount, equals(1));

    // Advance through multiple animation frames
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Child should NOT rebuild on animation ticks due to AnimatedBuilder child reuse
    expect(childBuildCount, equals(1));
  });
}
