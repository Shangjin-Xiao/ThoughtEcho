library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/app_loading_view.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoteListView filter subscription race', () {
    testWidgets(
      'can explicitly release search field focus for modal flows',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final noteListKey = GlobalKey<NoteListViewState>();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            noteListKey: noteListKey,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final searchField = find.byType(TextField);
        await tester.tap(searchField);
        await tester.pump();

        EditableText editableText() =>
            tester.widget<EditableText>(find.byType(EditableText).first);

        expect(editableText().focusNode.hasFocus, isTrue);

        noteListKey.currentState!.unfocusSearchField();
        await tester.pump();

        expect(editableText().focusNode.hasFocus, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'clearing filters resubscribes only once with updated filter params',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final initialCallCount = databaseService.watchCalls.length;
        expect(initialCallCount, greaterThan(0));

        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final newCalls =
            databaseService.watchCalls.skip(initialCallCount).toList();

        expect(newCalls, hasLength(1));
        expect(newCalls.single.tagIds, isNull);
        expect(newCalls.single.selectedWeathers, isNull);
        expect(newCalls.single.selectedDayPeriods, isNull);

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'removing a tag filter keeps a single result list on screen',
      (tester) async {
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '筛选变化前可见的笔记',
              date: DateTime(2026, 7, 8, 9).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(ListView), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pump();

        expect(find.byType(ListView), findsOneWidget);
        expect(find.text('筛选变化前可见的笔记'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'shows notes even when tag list is still empty',
      (tester) async {
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '通过通知进入后的笔记',
              date: DateTime(2026, 3, 29).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('通过通知进入后的笔记'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'scrollToQuoteById waits for real first batch after placeholder empty list',
      (tester) async {
        final databaseService = _DelayedFakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final noteListKey = GlobalKey<NoteListViewState>();

        await tester.pumpWidget(
          _TestApp(
            key: const ValueKey('delayed-test-app'),
            databaseService: databaseService,
            settingsService: settingsService,
            noteListKey: noteListKey,
          ),
        );

        await tester.pump();
        databaseService.emitPlaceholder();
        await tester.pump();

        final scrollFuture = noteListKey.currentState!.scrollToQuoteById(
          'quote-1',
        );

        await tester.pump(const Duration(milliseconds: 4200));

        databaseService.emitQuotes([
          Quote(
            id: 'quote-1',
            content: '延迟到达的目标笔记',
            date: DateTime(2026, 4, 25, 8, 0).toIso8601String(),
          ),
        ]);
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 50));

        expect(await scrollFuture, isTrue);
        expect(find.text('延迟到达的目标笔记'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      'does not show an empty note list while initial placeholder data is unresolved',
      (tester) async {
        final databaseService = _DelayedFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
          ),
        );

        await tester.pump();
        databaseService.emitPlaceholder();
        await tester.pump();

        expect(find.text('还没有笔记，开始记录吧！'), findsNothing);

        await tester.pump(const Duration(seconds: 9));

        expect(find.text('还没有笔记，开始记录吧！'), findsNothing);
        expect(find.byType(AppLoadingView), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      'notification target retry can recover after initial load safety timeout',
      (tester) async {
        final databaseService = _DelayedFakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final noteListKey = GlobalKey<NoteListViewState>();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            noteListKey: noteListKey,
          ),
        );

        await tester.pump();
        databaseService.emitPlaceholder();
        await tester.pump();

        final firstAttempt = noteListKey.currentState!.scrollToQuoteById(
          'quote-1',
        );
        await tester.pump(const Duration(milliseconds: 5100));
        expect(await firstAttempt, isFalse);

        final retryAttempt = noteListKey.currentState!.scrollToQuoteById(
          'quote-1',
        );
        await tester.pump(const Duration(milliseconds: 3900));

        databaseService.emitQuotes([
          Quote(
            id: 'quote-1',
            content: '安全超时后到达的目标笔记',
            date: DateTime(2026, 7, 1, 10, 23).toIso8601String(),
          ),
        ]);
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 50));

        expect(await retryAttempt, isTrue);
        expect(find.text('安全超时后到达的目标笔记'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      'uses local keys for ordinary items and precisely positions a deep target',
      (tester) async {
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = _makeQuotes(60);
        final settingsService = _FakeSettingsService();
        final noteListKey = GlobalKey<NoteListViewState>();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            noteListKey: noteListKey,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.byKey(const ValueKey<String>('note-list-row-quote-0')),
          findsOneWidget,
        );

        final scrollFuture = noteListKey.currentState!.scrollToQuoteById(
          'quote-55',
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 50));

        expect(await scrollFuture, isTrue);
        final target = find.ancestor(
          of: find.textContaining('分页测试笔记 55'),
          matching: find.byType(QuoteItemWidget),
        );
        expect(target, findsOneWidget);
        final listTop = tester.getTopLeft(find.byType(ListView)).dy;
        expect(tester.getTopLeft(target).dy, closeTo(listTop + 12, 3));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'provides stable row index lookup for animated note deletion',
      (tester) async {
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '第一条',
              date: DateTime(2026, 3, 29, 12).toIso8601String(),
            ),
            Quote(
              id: 'quote-2',
              content: '第二条',
              date: DateTime(2026, 3, 29, 11).toIso8601String(),
            ),
            Quote(
              id: 'quote-3',
              content: '第三条',
              date: DateTime(2026, 3, 29, 10).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final listView = tester.widget<ListView>(find.byType(ListView));
        final delegate =
            listView.childrenDelegate as SliverChildBuilderDelegate;

        expect(
          delegate.findChildIndexCallback!(
            const ValueKey<String>('note-list-row-quote-2'),
          ),
          1,
        );
        expect(
          delegate.findChildIndexCallback!(
            const ValueKey<String>('note-list-row-quote-3'),
          ),
          2,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'coalesces repeated delete requests while note removal animation is pending',
      (tester) async {
        final deletedQuoteIds = <String>[];
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '待删除笔记',
              date: DateTime(2026, 3, 29, 12).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            onDelete: (quote) => deletedQuoteIds.add(quote.id!),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(SizeTransition), findsNothing);

        final item = tester.widget<QuoteItemWidget>(
          find.byType(QuoteItemWidget).first,
        );
        item.onDelete();
        item.onDelete();

        await tester.pump();
        expect(find.byType(SizeTransition), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 300));

        expect(deletedQuoteIds, ['quote-1']);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'uses a list-level note insertion animation duration',
      (tester) async {
        final noteListKey = GlobalKey<NoteListViewState>();
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '新增动画笔记',
              date: DateTime(2026, 3, 29, 12).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            noteListKey: noteListKey,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        noteListKey.currentState!.triggerInsertAnimation('quote-1');
        await tester.pump();

        final animation = tester.widget<TweenAnimationBuilder<double>>(
          find.byKey(const ValueKey('note_list_insert_quote-1_slide_1')),
        );

        expect(animation.duration, const Duration(milliseconds: 250));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'plays edited note save animation only at the list level',
      (tester) async {
        final noteListKey = GlobalKey<NoteListViewState>();
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '编辑动画笔记',
              date: DateTime(2026, 3, 29, 12).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            noteListKey: noteListKey,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        noteListKey.currentState!.triggerInsertAnimation('quote-1');
        await tester.pump();

        expect(
          find.byKey(const ValueKey('note_list_insert_quote-1_slide_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('save_animate_quote-1_slide_1')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'does not restart an active save animation for the same note',
      (tester) async {
        final noteListKey = GlobalKey<NoteListViewState>();
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = [
            Quote(
              id: 'quote-1',
              content: '重复保存动画笔记',
              date: DateTime(2026, 3, 29, 12).toIso8601String(),
            ),
          ];
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            noteListKey: noteListKey,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        noteListKey.currentState!.triggerInsertAnimation('quote-1');
        await tester.pump();
        noteListKey.currentState!.triggerInsertAnimation('quote-1');
        await tester.pump();

        expect(
          find.byKey(const ValueKey('note_list_insert_quote-1_slide_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('note_list_insert_quote-1_slide_2')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'restarts pending restore animation for repeated delete undo',
      (tester) async {
        final noteListKey = GlobalKey<NoteListViewState>();
        final databaseService = _DelayedFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            noteListKey: noteListKey,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        databaseService.emitQuotes(const []);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(ListView), findsNothing);

        noteListKey.currentState!.triggerInsertAnimation(
          'quote-1',
          animateListInsertion: true,
        );
        databaseService.emitQuotes([
          Quote(
            id: 'quote-1',
            content: '反复删除撤销的笔记',
            date: DateTime(2026, 6, 30, 12).toIso8601String(),
          ),
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.byKey(const ValueKey('note_list_insert_quote-1_slide_1')),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 700));
        databaseService.emitQuotes(const []);
        await tester.pump();

        noteListKey.currentState!.triggerInsertAnimation(
          'quote-1',
          animateListInsertion: true,
        );
        databaseService.emitQuotes([
          Quote(
            id: 'quote-1',
            content: '反复删除撤销的笔记',
            date: DateTime(2026, 6, 30, 12).toIso8601String(),
          ),
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.byKey(const ValueKey('note_list_insert_quote-1_slide_2')),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 850));

        expect(
          find.byKey(const ValueKey('note_list_insert_quote-1_slide_2')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      'loads the next page before positioning a notification target',
      (tester) async {
        final databaseService = _PagingFakeDatabaseService();
        final settingsService = _FakeSettingsService();
        final noteListKey = GlobalKey<NoteListViewState>();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            noteListKey: noteListKey,
          ),
        );
        await tester.pump();
        databaseService.emitInitialPage();
        await tester.pump();

        final scrollFuture = noteListKey.currentState!.scrollToQuoteById(
          'quote-35',
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 50));

        expect(await scrollFuture, isTrue);
        expect(databaseService.loadMoreCallCount, 2); // 1 查找 + 1 定位后预加载
        expect(find.textContaining('分页测试笔记 35'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
      'returns false immediately when the notification target is unavailable',
      (tester) async {
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = _makeQuotes(5);
        final settingsService = _FakeSettingsService();
        final noteListKey = GlobalKey<NoteListViewState>();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            noteListKey: noteListKey,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          await noteListKey.currentState!.scrollToQuoteById('missing-quote'),
          isFalse,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'keeps load more gated while the appended page settles',
      (tester) async {
        final databaseService = _PagingFakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );

        await tester.pump();
        databaseService.emitInitialPage();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final listViewContext = tester.element(find.byType(ListView));
        _dispatchPreloadScrollUpdate(listViewContext);
        await tester.pump();
        expect(databaseService.loadMoreCallCount, 1);

        _dispatchPreloadScrollUpdate(listViewContext);
        await tester.pump(const Duration(milliseconds: 100));

        expect(databaseService.loadMoreCallCount, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        await databaseService.disposeStream();
      },
    );

    testWidgets(
        'uses an extended cache extent to preload variable-height items', (
      tester,
    ) async {
      final databaseService = _FakeDatabaseService()
        ..quotesToEmit = [
          Quote(
            id: 'quote-1',
            content: '普通笔记',
            date: DateTime(2026, 5, 16).toIso8601String(),
          ),
        ];
      final settingsService = _FakeSettingsService();

      await tester.pumpWidget(
        _TestApp(
          databaseService: databaseService,
          settingsService: settingsService,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final listView = tester.widget<ListView>(find.byType(ListView));
      final cacheExtent = listView.cacheExtent;
      expect(cacheExtent, isNotNull);
      expect(
        cacheExtent,
        inInclusiveRange(400.0, 900.0),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('disables automatic semantic indexes for cached list items', (
      tester,
    ) async {
      final databaseService = _FakeDatabaseService()
        ..quotesToEmit = [
          Quote(
            id: 'quote-1',
            content: '普通笔记',
            date: DateTime(2026, 5, 16).toIso8601String(),
          ),
        ];
      final settingsService = _FakeSettingsService();

      await tester.pumpWidget(
        _TestApp(
          databaseService: databaseService,
          settingsService: settingsService,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.semanticChildCount, 1);
      final delegate = listView.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.addSemanticIndexes, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
      'entering PDF selection keeps the selected note at the same position',
      (tester) async {
        final databaseService = _FakeDatabaseService()
          ..quotesToEmit = _makeQuotes(20);
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _TestApp(
            databaseService: databaseService,
            settingsService: settingsService,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final listView = tester.widget<ListView>(find.byType(ListView));
        listView.controller!.jumpTo(900);
        await tester.pump();

        final visibleMoreButtonElement =
            find.byIcon(Icons.more_vert).evaluate().firstWhere((element) {
          final y = tester
              .getCenter(find.byElementPredicate(
                (candidate) => identical(candidate, element),
              ))
              .dy;
          return y > 160 && y < 700;
        });
        final moreButton = find.byElementPredicate(
          (element) => identical(element, visibleMoreButtonElement),
        );
        final initialQuoteItem = tester.widget<QuoteItemWidget>(
          find.ancestor(
            of: moreButton,
            matching: find.byType(QuoteItemWidget),
          ),
        );
        final targetQuoteId = initialQuoteItem.quote.id;
        final selectedNote = find.byWidgetPredicate(
          (widget) =>
              widget is QuoteItemWidget && widget.quote.id == targetQuoteId,
        );
        final offsetBefore = listView.controller!.offset;
        final positionBefore = tester.getTopLeft(selectedNote).dy;

        await tester.tap(moreButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('导出为 PDF'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final updatedListView = tester.widget<ListView>(find.byType(ListView));
        expect(updatedListView.controller!.offset, closeTo(offsetBefore, 0.1));
        expect(tester.getTopLeft(selectedNote).dy, closeTo(positionBefore, 1));
        expect(find.byIcon(Icons.check), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });
}

class _TestApp extends StatefulWidget {
  final _FakeDatabaseService databaseService;
  final _FakeSettingsService settingsService;
  final List<NoteCategory> tags;
  final GlobalKey<NoteListViewState>? noteListKey;
  final ValueChanged<Quote>? onDelete;

  _TestApp({
    super.key,
    required this.databaseService,
    required this.settingsService,
    List<NoteCategory>? tags,
    this.noteListKey,
    this.onDelete,
  }) : tags = tags ?? _defaultTags;

  static final List<NoteCategory> _defaultTags = [
    NoteCategory(id: 'tag-1', name: '标签一', iconName: '🏷️'),
  ];

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  List<String> _selectedTagIds = const ['tag-1'];
  List<String> _selectedWeathers = const ['sunny'];
  List<String> _selectedDayPeriods = const ['morning'];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DatabaseService>.value(
          value: widget.databaseService,
        ),
        ChangeNotifierProvider<SettingsService>.value(
          value: widget.settingsService,
        ),
        ChangeNotifierProvider(create: (_) => NoteSearchController()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Material(
          child: NoteListView(
            key: widget.noteListKey,
            tags: widget.tags,
            selectedTagIds: _selectedTagIds,
            onTagSelectionChanged: (tagIds) {
              setState(() {
                _selectedTagIds = tagIds;
              });
            },
            searchQuery: '',
            sortType: 'time',
            sortAscending: false,
            onSortChanged: (_, __) {},
            onSearchChanged: (_) {},
            onEdit: (_) {},
            onDelete: widget.onDelete ?? (_) {},
            onAskAI: (_) {},
            selectedWeathers: _selectedWeathers,
            selectedDayPeriods: _selectedDayPeriods,
            onFilterChanged: (weathers, dayPeriods) {
              setState(() {
                _selectedWeathers = weathers;
                _selectedDayPeriods = dayPeriods;
              });
            },
          ),
        ),
      ),
    );
  }
}

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  AppSettings get appSettings => AppSettings.defaultSettings();

  @override
  LocalAISettings get localAISettings => LocalAISettings.defaultSettings();

  @override
  bool get requireBiometricForHidden => false;

  @override
  bool get showFavoriteButton => true;

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  bool get noteListDisableCardShadows => false;

  @override
  bool get noteListDisableBackdropBlur => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  String get exportFormat => 'pdf';

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  String get noteInsertAnimationType => 'slide';

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

class _WatchQuotesCall {
  final List<String>? tagIds;
  final List<String>? selectedWeathers;
  final List<String>? selectedDayPeriods;
  final bool includeDeleted;

  const _WatchQuotesCall({
    required this.tagIds,
    required this.selectedWeathers,
    required this.selectedDayPeriods,
    required this.includeDeleted,
  });
}

class _FakeDatabaseService extends DatabaseService {
  final List<_WatchQuotesCall> watchCalls = [];
  List<Quote> quotesToEmit = const [];
  List<NoteCategory> categoriesToReturn = const [];

  _FakeDatabaseService() : super.forTesting();

  @override
  bool get isInitialized => true;

  @override
  bool get hasMoreQuotes => false;

  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool includeDeleted = false,
  }) {
    watchCalls.add(
      _WatchQuotesCall(
        tagIds: tagIds == null ? null : List<String>.from(tagIds),
        selectedWeathers: selectedWeathers == null
            ? null
            : List<String>.from(selectedWeathers),
        selectedDayPeriods: selectedDayPeriods == null
            ? null
            : List<String>.from(selectedDayPeriods),
        includeDeleted: includeDeleted,
      ),
    );
    return Stream<List<Quote>>.value(quotesToEmit);
  }

  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
  }) async {}

  @override
  Future<List<NoteCategory>> getCategories() async => categoriesToReturn;
}

class _DelayedFakeDatabaseService extends _FakeDatabaseService {
  final StreamController<List<Quote>> _controller =
      StreamController<List<Quote>>.broadcast();
  bool _hasMoreQuotes = true;

  @override
  bool get hasMoreQuotes => _hasMoreQuotes;

  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool includeDeleted = false,
  }) {
    watchCalls.add(
      _WatchQuotesCall(
        tagIds: tagIds == null ? null : List<String>.from(tagIds),
        selectedWeathers: selectedWeathers == null
            ? null
            : List<String>.from(selectedWeathers),
        selectedDayPeriods: selectedDayPeriods == null
            ? null
            : List<String>.from(selectedDayPeriods),
        includeDeleted: includeDeleted,
      ),
    );
    return _controller.stream;
  }

  void emitPlaceholder() {
    _hasMoreQuotes = true;
    _controller.add(const []);
  }

  void emitQuotes(List<Quote> quotes) {
    quotesToEmit = quotes;
    _hasMoreQuotes = false;
    _controller.add(quotes);
  }

  Future<void> disposeStream() async {
    await _controller.close();
  }
}

class _PagingFakeDatabaseService extends _DelayedFakeDatabaseService {
  int loadMoreCallCount = 0;

  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
  }) async {
    loadMoreCallCount++;
    _hasMoreQuotes = true;
    _controller.add(_makeQuotes(40));
  }

  void emitInitialPage() {
    _hasMoreQuotes = true;
    _controller.add(_makeQuotes(20));
  }
}

List<Quote> _makeQuotes(int count) {
  return List<Quote>.generate(
    count,
    (index) => Quote(
      id: 'quote-$index',
      content: '分页测试笔记 $index\n${'较长内容 ' * 20}',
      date: DateTime(2026, 5, 10, 8, index).toIso8601String(),
    ),
  );
}

void _dispatchPreloadScrollUpdate(BuildContext context) {
  ScrollUpdateNotification(
    metrics: FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 900,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    ),
    context: context,
    scrollDelta: 10,
  ).dispatch(context);
}
