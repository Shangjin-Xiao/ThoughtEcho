// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_trace/main.dart';
import 'package:mind_trace/services/settings_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

mixin MockSharedPreferencesMixin on Mock implements SharedPreferences {}
class MockSharedPreferences extends Mock with MockSharedPreferencesMixin implements SharedPreferences {}

void main() {
  testWidgets('Mind Trace App Test', (WidgetTester tester) async {
    // 创建 MockSharedPreferences 实例
    final mockSharedPreferences = MockSharedPreferences();

    // 初始化设置服务并等待异步操作完成
    SettingsService settingsService = SettingsService(mockSharedPreferences);

    // 构建应用程序并等待所有异步操作完成
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    // 验证应用程序标题是否正确显示
    expect(find.text('心迹'), findsOneWidget);
  });
}
