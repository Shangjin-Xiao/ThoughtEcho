import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/trash_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:thoughtecho/widgets/trash_quote_card.dart';

import '../../test_setup.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  int get trashRetentionDays => 30;

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  bool get showExactTime => false;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

class _FakeDatabaseService extends ChangeNotifier implements DatabaseService {
  _FakeDatabaseService({required List<Quote> quotes}) : _quotes = quotes;

  final List<Quote> _quotes;

  @override
  Future<List<Quote>> getDeletedQuotes({
    int offset = 0,
    int limit = 20,
    String orderBy = 'deleted_at DESC',
  }) async {
    final end = (offset + limit).clamp(0, _quotes.length);
    if (offset >= _quotes.length) {
      return const [];
    }
    return _quotes.sublist(offset, end);
  }

  @override
  Future<int> getDeletedQuotesCount() async => _quotes.length;

  @override
  Stream<List<NoteCategory>> watchCategories() =>
      Stream<List<NoteCategory>>.value(
        const [],
      );

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DatabaseService.${invocation.memberName} 未实现');
}

Quote _buildDeletedRichQuote() {
  return Quote(
    id: 'trash-note-1',
    content: '今天拍了一张照片并补了几句说明',
    date: DateTime(2026, 4, 4, 8, 30).toIso8601String(),
    editSource: 'fullscreen',
    deltaContent: jsonEncode([
      {
        'insert': '今天拍了一张照片并补了几句说明\n',
      },
      {
        'insert': {
          'image': '/tmp/test-image.jpg',
        },
      },
      {
        'insert': '\n',
      },
    ]),
    isDeleted: true,
    deletedAt: DateTime(2026, 4, 5, 12, 0).toUtc().toIso8601String(),
    colorHex: '#DCEBFF',
  );
}

Widget _buildTestApp({required DatabaseService databaseService}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
      ChangeNotifierProvider<SettingsService>.value(
        value: _FakeSettingsService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: const TrashPage(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupTestEnvironment();
  });

  group('TrashPage', () {
    testWidgets('用富文本内容组件展示已删除笔记，保留回收站操作入口', (tester) async {
      final databaseService =
          _FakeDatabaseService(quotes: [_buildDeletedRichQuote()]);

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      expect(find.byType(TrashQuoteCard), findsOneWidget);
      expect(find.byType(QuoteContent), findsOneWidget);
      expect(find.byKey(QuoteContent.collapsedWrapperKey), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text(l10n.restoreNote), findsOneWidget);
      expect(find.text(l10n.permanentlyDelete), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
