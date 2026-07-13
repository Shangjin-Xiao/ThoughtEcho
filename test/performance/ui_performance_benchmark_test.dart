import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_category.dart';

/// 简单的性能基准测试，不依赖复杂的Provider设置
void main() {
  group('AddNoteDialog Performance Benchmarks', () {
    testWidgets('标签过滤性能测试', (WidgetTester tester) async {
      // 创建大量标签数据
      final tags = List.generate(
        1000,
        (index) => NoteCategory(
          id: 'tag_$index',
          name: '标签 $index',
          iconName: index % 2 == 0 ? '😀' : 'star',
        ),
      );

      // 测试过滤性能
      final stopwatch = Stopwatch()..start();

      const searchQuery = '标签 1';
      final filteredTags = tags.where((tag) {
        return tag.name.toLowerCase().contains(searchQuery.toLowerCase());
      }).toList();

      stopwatch.stop();

      // 验证结果
      expect(filteredTags.length, greaterThan(0));
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(10),
        reason: '标签过滤时间过长: ${stopwatch.elapsedMilliseconds}ms',
      );

      debugPrint('✓ 标签过滤耗时: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('✓ 找到匹配标签: ${filteredTags.length}个');
    });

    testWidgets('Widget构建性能测试', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();

      // 测试大量Chip Widget的构建性能
      final chips = List.generate(
        100,
        (index) =>
            Chip(label: Text('标签 $index'), avatar: const Icon(Icons.tag)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Wrap(children: chips)),
        ),
      );

      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1500),
        reason: 'Chip Widget构建时间异常: ${stopwatch.elapsedMilliseconds}ms',
      );

      debugPrint('✓ 构建100个Chip Widget耗时: ${stopwatch.elapsedMilliseconds}ms');
    });

    testWidgets('ExpansionTile展开性能测试', (WidgetTester tester) async {
      final largeContent = List.generate(
        200,
        (index) =>
            ListTile(title: Text('项目 $index'), leading: const Icon(Icons.star)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExpansionTile(
                  title: const Text('测试展开'),
                  children: largeContent,
                ),
              ],
            ),
          ),
        ),
      );

      final stopwatch = Stopwatch()..start();

      // 展开ExpansionTile
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'ExpansionTile展开时间异常: ${stopwatch.elapsedMilliseconds}ms',
      );

      debugPrint('✓ ExpansionTile展开耗时: ${stopwatch.elapsedMilliseconds}ms');
    });
  });
}
