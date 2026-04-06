import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  bool _prioritizeBoldContentInCollapse = false;
  bool _showExactTime = false;
  bool _showNoteEditTime = false;

  @override
  bool get prioritizeBoldContentInCollapse => _prioritizeBoldContentInCollapse;

  set prioritizeBoldContentInCollapse(bool value) {
    if (_prioritizeBoldContentInCollapse != value) {
      _prioritizeBoldContentInCollapse = value;
      notifyListeners();
    }
  }

  @override
  bool get showExactTime => _showExactTime;

  set showExactTime(bool value) {
    if (_showExactTime != value) {
      _showExactTime = value;
      notifyListeners();
    }
  }

  @override
  bool get showNoteEditTime => _showNoteEditTime;

  set showNoteEditTime(bool value) {
    if (_showNoteEditTime != value) {
      _showNoteEditTime = value;
      notifyListeners();
    }
  }

  // 不需要的方法抛出未实现异常，确保测试中不会被误用。
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

Quote _buildQuote({
  String id = 'q1',
  String content = 'This is a test note content.',
  String? deltaContent,
  String editSource = 'fullscreen',
  String? date,
  String? lastModified,
}) {
  return Quote(
    id: id,
    content: content,
    date: date ?? DateTime.now().toIso8601String(),
    deltaContent: deltaContent,
    editSource: editSource,
    dayPeriod: 'morning',
    lastModified: lastModified,
  );
}

const String _longContentChunk =
    '这是一个非常非常长的笔记内容，用于验证折叠逻辑是否生效，包含了足够的文字来超过默认的折叠高度。';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(QuoteItemWidget.clearExpansionCacheForTest);

  group('QuoteItemWidget', () {
    testWidgets('默认状态下展示截断内容并显示提示', (tester) async {
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
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

      expect(find.textContaining('非常长的笔记内容'), findsOneWidget);
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
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
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
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      bool toggled = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
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

      expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);

      final contentGesture = find.byKey(
        const ValueKey('quote_item.double_tap_region'),
      );

      await tester.tap(contentGesture);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(contentGesture);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(toggled, isTrue);
    });

    testWidgets('双击时显示高亮反馈', (tester) async {
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
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

      final gestureDetector = find.byKey(
        const ValueKey('quote_item.double_tap_region'),
      );

      await tester.tap(gestureDetector);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(gestureDetector);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        find.byKey(const ValueKey('quote_item.double_tap_overlay')),
        findsOneWidget,
      );
    });

    testWidgets('富文本默认显示 deltaContent', (tester) async {
      final delta = jsonEncode([
        {
          'insert': '粗体文本',
          'attributes': {'bold': true},
        },
        {'insert': '\n正常文本\n'},
        {
          'insert': {'image': 'https://example.com/img.png'},
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
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
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

    testWidgets('开启后在创建时间下方显示编辑时间', (tester) async {
      final settings = _FakeSettingsService()..showNoteEditTime = true;
      final quote = _buildQuote(
        date: DateTime(2025, 6, 21, 9, 0).toIso8601String(),
        lastModified: DateTime(2025, 6, 22, 10, 30).toIso8601String(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
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

      expect(find.textContaining('已编辑'), findsOneWidget);
      expect(find.textContaining('2025-06-22'), findsOneWidget);
    });

    testWidgets('关闭时不显示编辑时间', (tester) async {
      final settings = _FakeSettingsService()..showNoteEditTime = false;
      final quote = _buildQuote(
        date: DateTime(2025, 6, 21, 9, 0).toIso8601String(),
        lastModified: DateTime(2025, 6, 22, 10, 30).toIso8601String(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
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

      expect(find.textContaining('编辑于'), findsNothing);
    });

    testWidgets('编辑时间与创建时间一致或无效时不显示编辑时间', (tester) async {
      final settings = _FakeSettingsService()..showNoteEditTime = true;
      final createdAt = DateTime(2025, 6, 21, 9, 0);
      final sameTimeQuote = _buildQuote(
        id: 'q2',
        date: createdAt.toIso8601String(),
        lastModified: createdAt.toIso8601String(),
      );
      final invalidTimeQuote = _buildQuote(
        id: 'q3',
        date: createdAt.toIso8601String(),
        lastModified: 'invalid-date',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: Column(
                children: [
                  QuoteItemWidget(
                    quote: sameTimeQuote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                  QuoteItemWidget(
                    quote: invalidTimeQuote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('编辑于'), findsNothing);
    });
  });
}
