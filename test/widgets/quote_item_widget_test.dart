import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:provider/provider.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  bool _prioritizeBoldContentInCollapse = false;

  @override
  bool get prioritizeBoldContentInCollapse => _prioritizeBoldContentInCollapse;

  set prioritizeBoldContentInCollapse(bool value) {
    if (_prioritizeBoldContentInCollapse != value) {
      _prioritizeBoldContentInCollapse = value;
      notifyListeners();
    }
  }

  // 不需要的方法抛出未实现异常，确保测试中不会被误用。
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

Quote _buildQuote({
  String content = 'This is a test note content.',
  String? deltaContent,
  String editSource = 'fullscreen',
}) {
  return Quote(
    id: 'q1',
    content: content,
    date: DateTime.now().toIso8601String(),
    deltaContent: deltaContent,
    editSource: editSource,
    dayPeriod: 'morning',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(QuoteItemWidget.clearExpansionCache);

  group('QuoteItemWidget', () {
    testWidgets('默认状态下展示截断内容并显示提示', (tester) async {
      final quote = _buildQuote(
        content:
            '第一段内容很长很长很长很长很长\n第二段内容也很长很长很长很长很长\n第三段继续很长很长很长很长很长\n第四段也不短\n第五段应该被截断',
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tags: const [],
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('第一段内容'), findsOneWidget);
      expect(find.text('双击查看全文'), findsOneWidget);
    });

    testWidgets('展开状态显示完整内容且截断提示消失', (tester) async {
      final quote = _buildQuote(
        content:
            '第一段内容很长很长很长很长很长\n第二段内容也很长很长很长很长很长\n第三段继续很长很长很长很长很长\n第四段也不短\n第五段应该被完整展示',
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tags: const [],
                isExpanded: true,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('第五段应该被完整展示'), findsOneWidget);
      expect(find.text('双击查看全文'), findsNothing);
    });

    testWidgets('双击触发展开回调', (tester) async {
      final quote = _buildQuote(
        content:
            '第一段内容很长很长很长很长很长\n第二段内容也很长很长很长很长很长\n第三段继续很长很长很长很长很长\n第四段也不短\n第五段应该被截断',
        editSource: 'inline',
      );

      bool toggled = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tags: const [],
                isExpanded: false,
                onToggleExpanded: (expanded) {
                  toggled = expanded;
                },
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

  final contentGesture = find.byType(GestureDetector).first;

  await tester.tap(contentGesture);
      await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(contentGesture);
      await tester.pumpAndSettle();

      expect(toggled, isTrue);
    });

    testWidgets('富文本默认显示 deltaContent', (tester) async {
      final delta = jsonEncode([
        {
          'insert': '粗体文本',
          'attributes': {'bold': true}
        },
        {'insert': '\n正常文本\n'},
        {
          'insert': {'image': 'https://example.com/img.png'}
        },
      ]);

      final quote = _buildQuote(
        content: 'fallback content',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tags: const [],
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('fallback content'), findsNothing);
      expect(find.byType(quill.QuillEditor), findsOneWidget);
    });
  });
}
