// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_trace/main.dart'; // 修改导入路径

void main() {
  testWidgets('基础 UI 测试', (WidgetTester tester) async {
    await tester.pumpWidget(const App()); // 使用正确的应用根组件名称
    
    // 基础UI验证
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    
    // 可以添加更多具体的UI测试
  });
}
