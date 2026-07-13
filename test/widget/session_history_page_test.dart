import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/pages/ai_assistant/session_history_page.dart';

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

  @override
  Future<List<ChatSession>> getAllSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    return sessions;
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
    // No-op for test fake
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
}
