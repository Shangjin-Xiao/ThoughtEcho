/// Basic widget tests for HomePage
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/pages/home_page.dart';

void main() {
  group('HomePage Widget Tests', () {
    testWidgets('should create basic widget', (WidgetTester tester) async {
      // Create a simple test widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Test')),
            body: const Text('Hello World'),
          ),
        ),
      );

      // Verify that the text appears
      expect(find.text('Hello World'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('should handle basic interactions', (
      WidgetTester tester,
    ) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () {
                pressed = true;
              },
              child: const Text('Press Me'),
            ),
          ),
        ),
      );

      // Find and tap the button
      await tester.tap(find.text('Press Me'));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('short location chip keeps its natural visual width', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: HomeLocationWeatherDisplay(
                  locationText: 'Beijing',
                  weatherText: 'Sunny 18°C',
                  weatherIcon: Icons.wb_sunny,
                ),
              ),
            ),
          ),
        ),
      );

      final chipSize = tester.getSize(
        find.byKey(HomeLocationWeatherDisplay.chipKey),
      );

      expect(chipSize.width, lessThan(360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long English location chip uses remaining title space', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Row(
                children: [
                  Text('ThoughtEcho'),
                  SizedBox(width: 8),
                  Expanded(
                    child: HomeLocationWeatherDisplay(
                      locationText:
                          'Washington, District of Columbia, United States',
                      weatherText: 'Partly cloudy 18°C',
                      weatherIcon: Icons.cloud,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final titleSize = tester.getSize(find.text('ThoughtEcho'));
      final chipSize = tester.getSize(
        find.byKey(HomeLocationWeatherDisplay.chipKey),
      );

      expect(titleSize.width, greaterThan(80));
      expect(chipSize.width, lessThanOrEqualTo(320 - titleSize.width - 8));
      expect(tester.takeException(), isNull);
    });
  });
}
