import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

/// 优化后的添加笔记对话框性能测试
void main() {
  group('Optimized AddNoteDialog Performance Tests', () {
    late List<NoteCategory> mockTags;
    late DatabaseService mockDatabaseService;
    late LocationService mockLocationService;
    late WeatherService mockWeatherService;

    setUp(() {
      // 模拟大量标签数据来测试性能
      mockTags = List.generate(
          100,
          (index) => NoteCategory(
                id: 'tag_$index',
                name: '标签 $index',
                iconName: index % 2 == 0 ? '😀' : 'star',
              ));

      // 创建模拟服务
      mockDatabaseService = MockDatabaseService();
      mockLocationService = MockLocationService();
      mockWeatherService = MockWeatherService();
    });

    testWidgets('对话框应该快速显示，性能优于之前版本', (WidgetTester tester) async {
      // 构建测试应用
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DatabaseService>.value(value: mockDatabaseService),
            Provider<LocationService>.value(value: mockLocationService),
            Provider<WeatherService>.value(value: mockWeatherService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => AddNoteDialog(
                        tags: mockTags,
                        onSave: (_) {},
                      ),
                    );
                  },
                  child: const Text('打开对话框'),
                ),
              ),
            ),
          ),
        ),
      );

      // 记录开始时间
      final startTime = DateTime.now();

      // 点击按钮打开对话框
      await tester.tap(find.text('打开对话框'));
      await tester.pumpAndSettle();

      // 记录结束时间
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // 验证对话框已显示
      expect(find.byType(AddNoteDialog), findsOneWidget);

      // 验证性能：对话框打开应该在300ms内完成（比之前的481ms快）
      expect(duration.inMilliseconds, lessThan(300),
          reason: '对话框打开时间仍然过长: ${duration.inMilliseconds}ms');

      // Test output: 优化后对话框打开耗时: ${duration.inMilliseconds}ms
    });

    testWidgets('标签搜索应该快速响应，无明显卡顿', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DatabaseService>.value(value: mockDatabaseService),
            Provider<LocationService>.value(value: mockLocationService),
            Provider<WeatherService>.value(value: mockWeatherService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddNoteDialog(
                tags: mockTags,
                onSave: (_) {},
              ),
            ),
          ),
        ),
      );

      // 查找并展开标签选择区域
      final expansionTile = find.byType(ExpansionTile);
      expect(expansionTile, findsOneWidget);

      await tester.tap(expansionTile);
      await tester.pumpAndSettle();

      // 查找搜索框
      final searchField = find.widgetWithText(TextField, '搜索标签...');
      expect(searchField, findsOneWidget);

      // 测试搜索性能
      final startTime = DateTime.now();

      // 输入搜索文本
      await tester.enterText(searchField, '标签 1');
      await tester.pumpAndSettle();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // 验证性能：搜索应该在100ms内完成
      expect(duration.inMilliseconds, lessThan(100),
          reason: '标签搜索时间过长: ${duration.inMilliseconds}ms');

      // Test output: 标签搜索耗时: ${duration.inMilliseconds}ms
    });
  });
}

// 模拟服务类
class MockDatabaseService extends DatabaseService {
  @override
  Future<List<NoteCategory>> getCategories() async {
    return [];
  }

  @override
  Future<void> addQuote(quote) async {}

  @override
  Future<void> updateQuote(quote) async {}
}

class MockLocationService extends LocationService {
  @override
  String getFormattedLocation() => '测试位置';
}

class MockWeatherService extends WeatherService {
  @override
  String? get currentWeather => '晴天';

  @override
  String? get temperature => '25°C';
}
