import 'dart:async';
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

import '../../test_harness.dart';

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
  bool get showNoteEditTime => false;

  @override
  String get exportFormat => 'image';

  @override
  bool get noteListDisableCardShadows => false;

  @override
  bool get noteListDisableBackdropBlur => false;

  @override
  String get noteInsertAnimationType => 'none';

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

class _FakeDatabaseService extends ChangeNotifier implements DatabaseService {
  _FakeDatabaseService({required List<Quote> quotes}) : _quotes = quotes;

  final List<Quote> _quotes;
  String? lastRestoredId;
  String? lastPermanentlyDeletedId;
  bool emptyTrashCalled = false;
  int getDeletedQuotesCallCount = 0;
  int? maxItemsPerFetch;
  Completer<List<Quote>>? delayedDeletedQuotesAfterInitialLoad;

  @override
  Future<List<Quote>> getDeletedQuotes({
    int offset = 0,
    int limit = 20,
    String orderBy = 'deleted_at DESC',
  }) async {
    getDeletedQuotesCallCount++;
    final delayedFetch = delayedDeletedQuotesAfterInitialLoad;
    if (getDeletedQuotesCallCount > 1 && delayedFetch != null) {
      return delayedFetch.future;
    }
    final effectiveLimit = maxItemsPerFetch == null
        ? limit
        : (limit < maxItemsPerFetch! ? limit : maxItemsPerFetch!);
    final end = (offset + effectiveLimit).clamp(0, _quotes.length);
    if (offset >= _quotes.length) {
      return const [];
    }
    return _quotes.sublist(offset, end);
  }

  @override
  Future<int> getDeletedQuotesCount() async => _quotes.length;

  @override
  Future<void> restoreQuote(String id) async {
    lastRestoredId = id;
    _quotes.removeWhere((q) => q.id == id);
    notifyListeners();
  }

  @override
  Future<void> permanentlyDeleteQuote(String id) async {
    lastPermanentlyDeletedId = id;
    _quotes.removeWhere((q) => q.id == id);
    notifyListeners();
  }

  @override
  Future<void> emptyTrash() async {
    emptyTrashCalled = true;
    _quotes.clear();
    notifyListeners();
  }

  @override
  Stream<List<NoteCategory>> watchCategories() =>
      Stream<List<NoteCategory>>.value(
        const [],
      );

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DatabaseService.${invocation.memberName} 未实现');
}

Quote _buildDeletedRichQuote({
  String id = 'trash-note-1',
  String content = '今天拍了一张照片并补了几句说明',
  DateTime? deletedAt,
}) {
  return Quote(
    id: id,
    content: content,
    date: DateTime(2026, 4, 4, 8, 30).toIso8601String(),
    editSource: 'fullscreen',
    deltaContent: jsonEncode([
      {
        'insert': '$content\n',
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
    deletedAt:
        (deletedAt ?? DateTime(2026, 4, 5, 12, 0)).toUtc().toIso8601String(),
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
    await TestHarness.initialize();
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
      expect(find.byKey(QuoteContent.collapsedWrapperKey), findsOneWidget);
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

      expect(find.byTooltip(l10n.trashRetentionPeriod), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.trashRetentionPeriod));
      await tester.pumpAndSettle();

      expect(find.text(l10n.trashRetentionOption30Days), findsOneWidget);
      expect(find.text(l10n.trashRetentionOption90Days), findsOneWidget);

      await tester.tap(find.text(l10n.trashRetentionOption90Days));
      await tester.pumpAndSettle();

      expect(settingsService.lastSetTrashRetentionDays, 90);

      await _disposeApp(tester);
    });

    testWidgets('点击恢复按钮后笔记从回收站消失并显示提示', (tester) async {
      final databaseService =
          _FakeDatabaseService(quotes: [_buildDeletedRichQuote()]);

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      expect(find.byType(TrashQuoteCard), findsOneWidget);

      await tester.tap(find.text(l10n.restore));
      await tester.pumpAndSettle();

      expect(find.byType(TrashQuoteCard), findsNothing);
      expect(find.text(l10n.noteRestored), findsOneWidget);
      expect(databaseService.lastRestoredId, 'trash-note-1');

      await _disposeApp(tester);
    });

    testWidgets('恢复笔记后保持当前列表可见，不进入全屏刷新', (tester) async {
      final databaseService = _FakeDatabaseService(
        quotes: [
          _buildDeletedRichQuote(),
          _buildDeletedRichQuote(
            id: 'trash-note-2',
            content: '保留在列表中的笔记',
            deletedAt: DateTime(2026, 4, 4, 12),
          ),
        ],
      )..delayedDeletedQuotesAfterInitialLoad = Completer<List<Quote>>();

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      await tester.tap(find.text(l10n.restore).first);
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(TrashQuoteCard), findsOneWidget);
      expect(find.text(l10n.noteRestored), findsOneWidget);

      databaseService.delayedDeletedQuotesAfterInitialLoad?.complete(const []);
      await _disposeApp(tester);
    });

    testWidgets('恢复已加载的最后一条时继续补拉未加载回收站数据', (tester) async {
      final databaseService = _FakeDatabaseService(
        quotes: [
          _buildDeletedRichQuote(content: '第一页笔记'),
          _buildDeletedRichQuote(
            id: 'trash-note-2',
            content: '下一页笔记',
            deletedAt: DateTime(2026, 4, 4, 12),
          ),
        ],
      )..maxItemsPerFetch = 1;

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      expect(find.byType(TrashQuoteCard), findsOneWidget);
      expect(find.text(l10n.trashCount(2)), findsOneWidget);

      await tester.tap(find.text(l10n.restore));
      await tester.pumpAndSettle();

      expect(databaseService.lastRestoredId, 'trash-note-1');
      expect(find.byType(TrashQuoteCard), findsOneWidget);
      final card = tester.widget<TrashQuoteCard>(find.byType(TrashQuoteCard));
      expect(card.quote.id, 'trash-note-2');
      expect(find.text(l10n.trashCount(1)), findsOneWidget);
      expect(find.text(l10n.trashEmpty), findsNothing);

      await _disposeApp(tester);
    });

    testWidgets('点击永久删除按钮后笔记从回收站消失', (tester) async {
      final databaseService =
          _FakeDatabaseService(quotes: [_buildDeletedRichQuote()]);

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      expect(find.byType(TrashQuoteCard), findsOneWidget);

      await tester.tap(
        find.widgetWithText(TextButton, l10n.permanentlyDelete).first,
      );
      await tester.pumpAndSettle();

      // Confirm dialog
      expect(find.text(l10n.permanentlyDeleteConfirmation), findsOneWidget);
      await tester.tap(
        find.widgetWithText(TextButton, l10n.permanentlyDelete).last,
      );
      await tester.pumpAndSettle();

      expect(find.byType(TrashQuoteCard), findsNothing);
      expect(databaseService.lastPermanentlyDeletedId, 'trash-note-1');

      await _disposeApp(tester);
    });

    testWidgets('清空回收站后立即显示空状态，不进入全屏刷新', (tester) async {
      final databaseService =
          _FakeDatabaseService(quotes: [_buildDeletedRichQuote()])
            ..delayedDeletedQuotesAfterInitialLoad = Completer<List<Quote>>();

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      await tester.tap(find.text(l10n.emptyTrash));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10n.emptyTrash).last);
      await tester.pump();

      expect(find.text(l10n.trashEmpty), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(databaseService.emptyTrashCalled, isTrue);

      databaseService.delayedDeletedQuotesAfterInitialLoad?.complete(const []);
      await _disposeApp(tester);
    });

    testWidgets('回收站为空时仍显示保留期设置入口', (tester) async {
      final databaseService = _FakeDatabaseService(quotes: const []);

      await tester.pumpWidget(_buildTestApp(databaseService: databaseService));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TrashPage));
      final l10n = AppLocalizations.of(context);

      expect(find.byTooltip(l10n.trashRetentionPeriod), findsOneWidget);

      await _disposeApp(tester);
    });
  });
}
