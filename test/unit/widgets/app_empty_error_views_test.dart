import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:thoughtecho/widgets/app_empty_view.dart';
import 'package:thoughtecho/widgets/app_error_view.dart';

void main() {
  testWidgets('AppEmptyView shows correctly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppEmptyView(
          text: 'Empty State',
        ),
      ),
    ));
    expect(find.text('Empty State'), findsOneWidget);
    expect(find.byIcon(Icons.inbox), findsOneWidget);
  });

  testWidgets('AppErrorView shows correctly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppErrorView(
          text: 'Error State',
        ),
      ),
    ));
    expect(find.text('Error State'), findsOneWidget);
  });
}
