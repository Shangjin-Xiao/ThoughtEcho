import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 构建应用并触发一帧
    await tester.pumpWidget(const MindTraceApp());

    // 验证基础UI元素
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
