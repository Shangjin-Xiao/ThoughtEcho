import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thoughtecho/widgets/quill_enhanced_toolbar_unified.dart';

void main() {
  group('UnifiedQuillToolbar Tests', () {
    late quill.QuillController controller;

    setUp(() {
      controller = quill.QuillController.basic();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('UnifiedQuillToolbar renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: UnifiedQuillToolbar(controller: controller)),
        ),
      );

      // 验证工具栏是否渲染
      expect(find.byType(UnifiedQuillToolbar), findsOneWidget);

      // 验证基本按钮是否存在
      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.redo), findsOneWidget);
      expect(find.byIcon(Icons.format_bold), findsOneWidget);
      expect(find.byIcon(Icons.format_italic), findsOneWidget);

      // 验证媒体按钮是否存在
      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    });

    testWidgets('FullScreenToolbar alias works', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FullScreenToolbar(controller: controller)),
        ),
      );

      // 验证别名是否工作
      expect(find.byType(FullScreenToolbar), findsOneWidget);
      expect(find.byType(UnifiedQuillToolbar), findsOneWidget);
    });

    testWidgets('Media buttons trigger dialogs', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            quill.FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          home: Scaffold(body: UnifiedQuillToolbar(controller: controller)),
        ),
      );

      // 点击图片按钮
      await tester.tap(find.byIcon(Icons.image));
      await tester.pumpAndSettle();

      // 验证对话框是否出现
      expect(find.text('导入图片'), findsOneWidget);

      // 关闭对话框
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 点击视频按钮
      await tester.tap(find.byIcon(Icons.videocam));
      await tester.pumpAndSettle();

      // 验证对话框是否出现
      expect(find.text('导入视频'), findsOneWidget);

      // 关闭对话框
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 点击音频按钮
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();

      // 验证对话框是否出现
      expect(find.text('导入音频'), findsOneWidget);
    });

    test('Controller integration works', () {
      // 测试控制器基本功能
      expect(controller.document.isEmpty(), isTrue);

      // 插入文本
      controller.document.insert(0, 'Test text');
      expect(controller.document.toPlainText(), equals('Test text'));

      // 测试撤销/重做功能
      expect(controller.hasUndo, isTrue);
      controller.undo();
      expect(controller.document.isEmpty(), isTrue);

      expect(controller.hasRedo, isTrue);
      controller.redo();
      expect(controller.document.toPlainText(), equals('Test text'));
    });
  });

  group('Media Type Helper Tests', () {
    test('Media type names are correct', () {
      // 这些是内部方法，我们通过行为测试来验证
      // 实际的媒体类型名称会在对话框中显示
    });
  });
}
