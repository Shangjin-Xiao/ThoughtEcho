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
  _FakeSettingsService({int trashRetentionDays = 30})
      : _trashRetentionDays = trashRetentionDays;

  int _trashRetentionDays;
  int? lastSetTrashRetentionDays;

  @override
  int get trashRetentionDays => _trashRetentionDays;

  @override
  Future<void> setTrashRetentionDays(
    int days, {
    DateTime? modifiedAt,
  }) async {
    _trashRetentionDays = days;
    lastSetTrashRetentionDays = days;
    notifyListeners();
  }

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
  final settingsService = _FakeSettingsService();
  return _buildTestAppWithServices(
    databaseService: databaseService,
    settingsService: settingsService,
  );
}

Widget _buildTestAppWithServices({
  required DatabaseService databaseService,
  required SettingsService settingsService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
      ChangeNotifierProvider<SettingsService>.value(
        value: settingsService,
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

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 600));
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
      expect(find.text(l10n.restore), findsOneWidget);
      expect(find.text(l10n.permanentlyDelete), findsOneWidget);

      await _disposeApp(tester);
    });

    testWidgets('在回收站页内可调整保留期并立即生效', (tester) async {
      final settingsService = _FakeSettingsService(trashRetentionDays: 30);
      final databaseService =
          _FakeDatabaseService(quotes: [_buildDeletedRichQuote()]);

      await tester.pumpWidget(
        _buildTestAppWithServices(
          databaseService: databaseService,
          settingsService: settingsService,
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      expect(find.text(l10n.trashRetentionPeriod), findsOneWidget);
      expect(find.text(l10n.trashRetentionOption30Days), findsOneWidget);

      await tester.tap(find.text(l10n.trashRetentionPeriod));
      await tester.pumpAndSettle();

      expect(find.text(l10n.trashRetentionOption90Days), findsOneWidget);

      await tester.tap(find.text(l10n.trashRetentionOption90Days));
      await tester.pumpAndSettle();

      expect(settingsService.lastSetTrashRetentionDays, 90);
      expect(find.text(l10n.trashRetentionOption90Days), findsOneWidget);

      await _disposeApp(tester);
    });

    testWidgets('回收站为空时仍显示保留期设置入口', (tester) async {
      final databaseService = _FakeDatabaseService(quotes: const []);

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      expect(find.text(l10n.trashRetentionPeriod), findsOneWidget);
      expect(find.text(l10n.trashRetentionOption30Days), findsOneWidget);

      await _disposeApp(tester);
    });
  });
}
