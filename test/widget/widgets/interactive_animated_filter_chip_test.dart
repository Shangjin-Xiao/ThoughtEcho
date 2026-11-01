library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/interactive_animated_filter_chip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InteractiveAnimatedFilterChip Unit & Widget Tests', () {
    testWidgets(
        'renders child wrapped in Listener, RepaintBoundary and ScaleTransition',
        (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InteractiveAnimatedFilterChip(
              child: Text('Test Chip'),
            ),
          ),
        ),
      );

      expect(find.text('Test Chip'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InteractiveAnimatedFilterChip),
          matching: find.byType(Listener),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(InteractiveAnimatedFilterChip),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
      // Both press scale and selection scale use ScaleTransition
      expect(
        find.descendant(
          of: find.byType(InteractiveAnimatedFilterChip),
          matching: find.byType(ScaleTransition),
        ),
        findsAtLeastNWidgets(2),
      );
    });

    testWidgets('performs smooth press scale transition on pointer down and up',
        (
      tester,
    ) async {
      bool selected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: InteractiveAnimatedFilterChip(
                pressedScale: 0.94,
                pressDuration: const Duration(milliseconds: 120),
                child: FilterChip(
                  label: const Text('Chip'),
                  selected: selected,
                  onSelected: (val) {
                    selected = val;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final chipFinder = find.byType(InteractiveAnimatedFilterChip);
      final center = tester.getCenter(chipFinder);

      // Helper to extract the ScaleTransition widgets inside InteractiveAnimatedFilterChip
      double getPressScale() {
        final scaleTransitions = tester
            .widgetList<ScaleTransition>(
              find.descendant(
                of: chipFinder,
                matching: find.byType(ScaleTransition),
              ),
            )
            .toList();
        return scaleTransitions.first.scale.value;
      }

      // Initially at rest, scale should be 1.0
      expect(getPressScale(), equals(1.0));

      // Pointer down event
      final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
      await gesture.down(center);
      await tester.pump();

      // Mid-way through press animation (60ms)
      await tester.pump(const Duration(milliseconds: 60));
      final midScale = getPressScale();
      expect(midScale, lessThan(1.0));
      expect(midScale, greaterThanOrEqualTo(0.94));

      // End of press duration (120ms)
      await tester.pump(const Duration(milliseconds: 60));
      expect(getPressScale(), closeTo(0.94, 0.01));

      // Pointer up event
      await gesture.up();
      await tester.pump();

      // Release transition back towards 1.0
      await tester.pump(const Duration(milliseconds: 120));
      expect(getPressScale(), closeTo(1.0, 0.01));

      // Verify child FilterChip received the onSelected event
      expect(selected, isTrue);
    });

    testWidgets('cancels press scale transition gracefully on pointer cancel', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: InteractiveAnimatedFilterChip(
                pressedScale: 0.94,
                pressDuration: Duration(milliseconds: 120),
                child: Text('Cancelable Chip'),
              ),
            ),
          ),
        ),
      );

      final chipFinder = find.byType(InteractiveAnimatedFilterChip);
      final center = tester.getCenter(chipFinder);

      double getPressScale() {
        final scaleTransitions = tester
            .widgetList<ScaleTransition>(
              find.descendant(
                of: chipFinder,
                matching: find.byType(ScaleTransition),
              ),
            )
            .toList();
        return scaleTransitions.first.scale.value;
      }

      final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
      await gesture.down(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(getPressScale(), closeTo(0.94, 0.01));

      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(getPressScale(), closeTo(1.0, 0.01));
    });

    testWidgets(
        'triggers selection transition interpolation when isSelected changes', (
      tester,
    ) async {
      Widget buildTest(bool isSelected) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: InteractiveAnimatedFilterChip(
                isSelected: isSelected,
                selectedScale: 1.04,
                selectionDuration: const Duration(milliseconds: 180),
                child: const Text('Selection Chip'),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTest(false));

      final chipFinder = find.byType(InteractiveAnimatedFilterChip);
      double getSelectionScale() {
        final scaleTransitions = tester
            .widgetList<ScaleTransition>(
              find.descendant(
                of: chipFinder,
                matching: find.byType(ScaleTransition),
              ),
            )
            .toList();
        // The second ScaleTransition is the selection transition
        return scaleTransitions[1].scale.value;
      }

      expect(getSelectionScale(), equals(1.0));

      // Toggle isSelected to true
      await tester.pumpWidget(buildTest(true));
      await tester.pump();

      // Peak of selection animation at 50% (90ms)
      await tester.pump(const Duration(milliseconds: 90));
      expect(getSelectionScale(), closeTo(1.04, 0.02));

      // Settle back to 1.0 at 100% (180ms)
      await tester.pump(const Duration(milliseconds: 90));
      expect(getSelectionScale(), closeTo(1.0, 0.01));
    });
  });
}
