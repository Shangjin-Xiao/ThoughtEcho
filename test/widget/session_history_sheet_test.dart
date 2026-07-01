import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/widgets/session_history_sheet.dart';

import '../test_setup.dart';

class _FakeChatSessionService extends ChatSessionService {
  _FakeChatSessionService({
    required this.sessions,
    required this.messageCounts,
  });

  final List<ChatSession> sessions;
  final Map<String, int> messageCounts;

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
}

Widget _buildTestApp(SessionHistorySheet child) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
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
    await TestSetup.setupWidgetTest();
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
        SessionHistorySheet(
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
      tester.element(find.byType(SessionHistorySheet)),
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
        SessionHistorySheet(
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
      tester.element(find.byType(SessionHistorySheet)),
    );
    expect(find.text(l10n.unnamed), findsOneWidget);
  });
}
