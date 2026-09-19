import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/pages/thoughter/session_history_page.dart';

import '../test_harness.dart';

class _FakeChatSessionService extends ChatSessionService {
  _FakeChatSessionService({
    required this.sessions,
    required this.messageCounts,
    this.searchResults = const [],
  });

  final List<ChatSession> sessions;
  final Map<String, int> messageCounts;
  final List<ChatSessionSearchResult> searchResults;
  String? lastSearchQuery;
  final List<String> deletedSessionIds = [];

  @override
  Future<List<ChatSession>> getAllSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    return List.from(sessions);
  }

  @override
  Future<List<ChatSession>> getSessionsForNote(String noteId) async {
    return sessions.where((session) => session.noteId == noteId).toList();
  }

  @override
  Future<int> getMessageCount(String sessionId) async {
    return messageCounts[sessionId] ?? 0;
  }

  @override
  Future<Map<String, ChatSessionOverview>> getSessionOverviews(
    List<String> sessionIds,
  ) async {
    return {
      for (final id in sessionIds)
        id: ChatSessionOverview(
          messageCount: messageCounts[id] ?? 0,
          snippet: '',
        ),
    };
  }

  @override
  Future<List<ChatSessionSearchResult>> searchSessions(
    String query, {
    int limit = 20,
  }) async {
    lastSearchQuery = query;
    return searchResults;
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    deletedSessionIds.add(sessionId);
    sessions.removeWhere((s) => s.id == sessionId);
  }

  @override
  Future<void> deleteSessions(List<String> sessionIds) async {
    deletedSessionIds.addAll(sessionIds);
    sessions.removeWhere((s) => sessionIds.contains(s.id));
  }

  @override
  Future<void> togglePin(String sessionId) async {
    // No-op for test fake
  }
}

Widget _buildTestApp(SessionHistoryPage child) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

ChatSession _session({
  required String id,
  required String title,
  required DateTime lastActiveAt,
  String? noteId,
}) {
  return ChatSession(
    id: id,
    sessionType: 'chat',
    noteId: noteId,
    title: title,
    createdAt: lastActiveAt,
    lastActiveAt: lastActiveAt,
  );
}

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  testWidgets('hides empty untitled sessions in history list', (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final service = _FakeChatSessionService(
      sessions: [
        _session(
          id: 'blank-session',
          title: '   ',
          lastActiveAt: now,
        ),
        _session(
          id: 'valid-session',
          title: '有效会话',
          lastActiveAt: now.subtract(const Duration(minutes: 5)),
        ),
      ],
      messageCounts: const {
        'blank-session': 0,
        'valid-session': 2,
      },
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionHistoryPage)),
    );
    expect(find.text('有效会话'), findsOneWidget);
    expect(find.text(l10n.messageCountLabel(0)), findsNothing);
  });

  testWidgets('shows localized fallback title for untitled sessions',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final service = _FakeChatSessionService(
      sessions: [
        _session(
          id: 'untitled-with-messages',
          title: '  ',
          lastActiveAt: now,
        ),
      ],
      messageCounts: const {
        'untitled-with-messages': 3,
      },
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionHistoryPage)),
    );
    expect(find.text(l10n.unnamed), findsOneWidget);
  });

  testWidgets('searches message content and displays the matching snippet',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final matchedSession = _session(
      id: 'content-match',
      title: '周末计划',
      lastActiveAt: now,
    );
    final service = _FakeChatSessionService(
      sessions: [matchedSession],
      messageCounts: const {'content-match': 4},
      searchResults: [
        ChatSessionSearchResult(
          session: matchedSession,
          snippet: '后来我们聊到了海边露营和天气',
          isTruncated: false,
          matchStart: 8,
          matchEnd: 10,
        ),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '露营');
    await tester.pumpAndSettle();

    expect(service.lastSearchQuery, '露营');
    expect(find.textContaining('海边露营和天气'), findsOneWidget);
    expect(find.text('周末计划'), findsOneWidget);
  });

  testWidgets(
      'applies highlight styles to matching search text in snippet and title',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final matchedSession = _session(
      id: 'highlight-match',
      title: '学习Flutter',
      lastActiveAt: now,
    );
    final service = _FakeChatSessionService(
      sessions: [matchedSession],
      messageCounts: const {'highlight-match': 1},
      searchResults: [
        ChatSessionSearchResult(
          session: matchedSession,
          snippet: 'Flutter是Google的UI框架',
          isTruncated: false,
          matchStart: 0,
          matchEnd: 7,
        ),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Flutter');
    await tester.pumpAndSettle();

    // Verify both title and snippet are found
    expect(find.textContaining('学习Flutter'), findsOneWidget);
    expect(find.textContaining('Flutter是Google的UI框架'), findsOneWidget);

    // Verify that RichText widgets exist for the highlights
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    expect(richTexts.length, greaterThanOrEqualTo(2));
  });

  testWidgets(
      'enters multi-select mode via action button and toggles selection',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final service = _FakeChatSessionService(
      sessions: [
        _session(id: 's1', title: '会话一', lastActiveAt: now),
        _session(
          id: 's2',
          title: '会话二',
          lastActiveAt: now.subtract(const Duration(minutes: 5)),
        ),
      ],
      messageCounts: const {'s1': 2, 's2': 3},
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionHistoryPage)),
    );

    // Click multi-select button in AppBar
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pumpAndSettle();

    // In multi-select mode, title shows 0 selected
    expect(find.text(l10n.selectedChatCount(0)), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // Tap first card to select it
    await tester.tap(find.text('会话一'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectedChatCount(1)), findsOneWidget);

    // Tap second card to select it
    await tester.tap(find.text('会话二'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectedChatCount(2)), findsOneWidget);

    // Tap second card again to deselect
    await tester.tap(find.text('会话二'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectedChatCount(1)), findsOneWidget);
  });

  testWidgets('enters multi-select mode via long press on a card',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final service = _FakeChatSessionService(
      sessions: [
        _session(id: 's1', title: '长按会话', lastActiveAt: now),
      ],
      messageCounts: const {'s1': 1},
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionHistoryPage)),
    );

    // Long press card
    await tester.longPress(find.text('长按会话'));
    await tester.pumpAndSettle();

    // Automatically in multi-select mode with 1 selected
    expect(find.text(l10n.selectedChatCount(1)), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('selects all and deselects all in multi-select mode',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final service = _FakeChatSessionService(
      sessions: [
        _session(id: 's1', title: '会话A', lastActiveAt: now),
        _session(id: 's2', title: '会话B', lastActiveAt: now),
      ],
      messageCounts: const {'s1': 1, 's2': 1},
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionHistoryPage)),
    );

    // Enter multi-select
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pumpAndSettle();

    // Tap Select All
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectedChatCount(2)), findsOneWidget);

    // Tap Deselect All
    await tester.tap(find.byIcon(Icons.deselect_rounded));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectedChatCount(0)), findsOneWidget);
  });

  testWidgets(
      'batch deletes selected sessions with confirmation dialog and calls onBatchDelete',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final service = _FakeChatSessionService(
      sessions: [
        _session(id: 's1', title: '待删一', lastActiveAt: now),
        _session(id: 's2', title: '待删二', lastActiveAt: now),
        _session(id: 's3', title: '保留项', lastActiveAt: now),
      ],
      messageCounts: const {'s1': 1, 's2': 1, 's3': 2},
    );

    List<String>? batchDeletedIds;

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onBatchDelete: (ids) async {
            batchDeletedIds = List.from(ids);
            await service.deleteSessions(ids);
          },
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SessionHistoryPage)),
    );

    // Enter multi-select
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pumpAndSettle();

    // Select s1 and s2
    await tester.tap(find.text('待删一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待删二'));
    await tester.pumpAndSettle();

    // Tap delete button in AppBar
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    // Confirmation dialog should appear
    expect(find.text(l10n.deleteSelectedChats), findsOneWidget);
    expect(find.text(l10n.deleteSelectedChatsConfirm(2)), findsOneWidget);

    // Tap confirm delete in dialog
    await tester.tap(find.widgetWithText(TextButton, l10n.delete));
    await tester.pumpAndSettle();

    // Verify onBatchDelete was invoked with both IDs
    expect(batchDeletedIds, containsAll(['s1', 's2']));
    expect(batchDeletedIds, isNot(contains('s3')));

    // Should exit multi-select mode and remaining session should be visible
    expect(find.text('保留项'), findsOneWidget);
    expect(find.text('待删一'), findsNothing);
    expect(find.text('待删二'), findsNothing);
  });

  testWidgets(
      'swipe to delete reveals delete action and slidable is disabled in multi-select mode',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final service = _FakeChatSessionService(
      sessions: [
        _session(id: 's1', title: '可滑动会话', lastActiveAt: now),
      ],
      messageCounts: const {'s1': 1},
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slidableFinder = find.byType(Slidable);
    expect(slidableFinder, findsOneWidget);
    final slidable = tester.widget<Slidable>(slidableFinder);
    expect(slidable.enabled, isTrue);

    // Enter multi-select mode
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pumpAndSettle();

    // In multi-select mode, Slidable must be disabled
    final slidableInMultiSelect =
        tester.widget<Slidable>(find.byType(Slidable));
    expect(slidableInMultiSelect.enabled, isFalse);

    // Exit multi-select mode via close button
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    final slidableAfterExit = tester.widget<Slidable>(find.byType(Slidable));
    expect(slidableAfterExit.enabled, isTrue);
  });
}
