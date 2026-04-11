import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/chat_session.dart';
import '../services/chat_session_service.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';

/// 会话历史底部弹窗 - 现代卡片风格设计
class SessionHistorySheet extends StatefulWidget {
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
  State<SessionHistorySheet> createState() => _SessionHistorySheetState();
}

class _SessionHistorySheetState extends State<SessionHistorySheet> {
  List<ChatSession>? _sessions;
  bool _isLoading = true;
  Map<String, int> _messageCounts = {};

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      // If no noteId, show all sessions; otherwise filter by noteId
      final List<ChatSession> sessions;
      if (widget.noteId.isEmpty) {
        sessions = await widget.chatSessionService.getAllSessions();
      } else {
        sessions =
            await widget.chatSessionService.getSessionsForNote(widget.noteId);
      }

      // Load message counts for each session
      final Map<String, int> counts = {};
      for (final session in sessions) {
        try {
          counts[session.id] =
              await widget.chatSessionService.getMessageCount(session.id);
        } catch (e) {
          AppLogger.w('Failed to load message count for ${session.id}', error: e);
          counts[session.id] = 0;
        }
      }

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _messageCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.e('Failed to load sessions', error: e);
      if (mounted) {
        setState(() {
          _sessions = [];
          _messageCounts = {};
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

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
                onPressed: widget.onNewChat,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.newChat),
              ),
            ]),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_sessions == null || _sessions!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(l10n.noChats,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _sessions!.length,
                itemBuilder: (context, index) {
                  return _buildSessionCard(
                    context,
                    _sessions![index],
                    theme,
                    l10n,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    ChatSession session,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final isCurrent = session.id == widget.currentSessionId;
    final messageCount = _messageCounts[session.id] ?? 0;
    final truncatedTitle = session.title.length > 50
        ? '${session.title.substring(0, 50)}...'
        : session.title;
    final lastUpdated = TimeUtils.formatElapsedRelativeTimeLocalized(
      context,
      session.lastActiveAt,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Slidable(
        key: ValueKey(session.id),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _confirmDelete(context, session.id),
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              icon: Icons.delete_outline,
              label: l10n.delete,
            ),
          ],
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isCurrent
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : theme.colorScheme.surface,
            border: Border.all(
              color: isCurrent
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: isCurrent ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isCurrent ? null : () => widget.onSelect(session.id),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Message Count
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            truncatedTitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Message count badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            messageCount.toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Last Updated Time
                    Text(
                      lastUpdated,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Call delete callback
              widget.onDelete(sessionId);
              // Reload sessions after deletion
              if (mounted) {
                await _loadSessions();
              }
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
