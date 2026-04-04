import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/chat_session.dart';
import '../services/chat_session_service.dart';
import '../utils/time_utils.dart';

/// 会话历史底部弹窗
class SessionHistorySheet extends StatelessWidget {
  final String noteId;
  final String? currentSessionId;
  final ChatSessionService chatSessionService;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onNewChat;

  const SessionHistorySheet({
    super.key,
    required this.noteId,
    required this.currentSessionId,
    required this.chatSessionService,
    required this.onSelect,
    required this.onDelete,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<List<ChatSession>>(
      future: chatSessionService.getSessionsForNote(noteId),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? [];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(children: [
                  Text(l10n.chatHistory, style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onNewChat,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.newChat),
                  ),
                ]),
              ),
              const Divider(height: 1),
              if (sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(l10n.noChats,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final s = sessions[index];
                      final isCurrent = s.id == currentSessionId;
                      return ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.chat_bubble
                              : Icons.chat_bubble_outline,
                          color: isCurrent ? theme.colorScheme.primary : null,
                        ),
                        title: Text(s.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_fmtDate(context, s.lastActiveAt),
                            style: theme.textTheme.bodySmall),
                        selected: isCurrent,
                        onTap: isCurrent ? null : () => onSelect(s.id),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _confirmDelete(context, s.id),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, String sessionId) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteChat),
        content: Text(l10n.deleteChatConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete(sessionId);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  String _fmtDate(BuildContext context, DateTime d) {
    return TimeUtils.formatElapsedRelativeTimeLocalized(context, d);
  }
}
