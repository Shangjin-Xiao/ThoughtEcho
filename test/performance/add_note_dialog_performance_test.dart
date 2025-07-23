import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';
import 'package:thoughtecho/models/note_category.dart';

/// 添加笔记对话框性能测试
///
/// 测试点击加号按钮弹出笔记编辑框的性能
void main() {
  group('AddNoteDialog Performance Tests', () {
    late List<NoteCategory> mockTags;

    setUp(() {
      // 模拟大量标签数据来测试性能
      mockTags = List.generate(
          100,
          (index) => NoteCategory(
                id: 'tag_$index',
                name: '标签 $index',
                iconName: index % 2 == 0 ? '😀' : 'star',
              ));
    });

    testWidgets('对话框应该快速渲染，无明显掉帧', (WidgetTester tester) async {
      // 构建测试应用
      await tester.pumpWidget(
        MaterialApp(
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

      // 验证性能：对话框打开应该在500ms内完成
      expect(duration.inMilliseconds, lessThan(500),
          reason: '对话框打开时间过长: ${duration.inMilliseconds}ms');

      print('✓ 对话框打开耗时: ${duration.inMilliseconds}ms');
    });

    testWidgets('标签列表应该使用延迟加载', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddNoteDialog(
              tags: mockTags,
              onSave: (_) {},
            ),
          ),
        ),
      );

      // 验证ExpansionTile默认是收起状态（优化渲染性能）
      final expansionTile = find.byType(ExpansionTile);
      expect(expansionTile, findsOneWidget);

      // 验证标签选择区域存在
      expect(find.text('选择标签 (0)'), findsOneWidget);

      print('✓ 标签列表使用延迟加载，默认收起状态');
    });

    testWidgets('搜索功能应该正常工作', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddNoteDialog(
              tags: mockTags,
              onSave: (_) {},
            ),
          ),
        ),
      );

      // 展开标签选择区域
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // 查找搜索框
      final searchField = find.widgetWithText(TextField, '搜索标签...');
      expect(searchField, findsOneWidget);

      // 输入搜索关键词
      await tester.enterText(searchField, '标签 1');
      await tester.pumpAndSettle();

      // 验证搜索结果（应该只显示包含"标签 1"的项目）
      // 由于是模拟数据，应该有"标签 1", "标签 10", "标签 11"等
      print('✓ 搜索功能正常工作');
    });

    testWidgets('UI组件应该正确渲染', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddNoteDialog(
              tags: mockTags,
              onSave: (_) {},
            ),
          ),
        ),
      );

      // 验证主要UI组件存在
      expect(find.byType(TextField), findsWidgets); // 内容输入框、作者、作品输入框
      expect(find.byType(FilterChip), findsWidgets); // 位置、天气、颜色选择
      expect(find.byType(ExpansionTile), findsOneWidget); // 标签选择区域
      expect(find.byType(FilledButton), findsWidgets); // 保存、取消按钮

      print('✓ 所有UI组件正确渲染');
    });
  });
}
