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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          AppLogger.w('Failed to load message count for ${session.id}',
              error: e);
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

  /// 按日期分组sessions
  Map<String, List<ChatSession>> _groupSessionsByDate(
      List<ChatSession> sessions, AppLocalizations l10n) {
    final groups = <String, List<ChatSession>>{};
    final now = DateTime.now();

    for (final session in sessions) {
      final date = session.lastActiveAt;
      final dayDiff = now.difference(date).inDays;

      String groupKey;
      if (dayDiff == 0) {
        groupKey = l10n.sessionGroupToday;
      } else if (dayDiff == 1) {
        groupKey = l10n.sessionGroupYesterday;
      } else if (dayDiff < 7) {
        groupKey = l10n.sessionGroupThisWeek;
      } else {
        groupKey = l10n.sessionGroupEarlier;
      }

      groups.putIfAbsent(groupKey, () => []).add(session);
    }

    return groups;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchChatHistory,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
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
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5)),
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
              child: _buildGroupedSessionsList(context, theme, l10n),
            ),
        ],
      ),
    );
  }

  /// 构建分组的sessions列表
  Widget _buildGroupedSessionsList(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final filtered = _searchQuery.isEmpty
        ? _sessions!
        : _sessions!
            .where((s) =>
                s.title.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.noChats,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final groups = _groupSessionsByDate(filtered, l10n);
    final groupOrder = [
      l10n.sessionGroupToday,
      l10n.sessionGroupYesterday,
      l10n.sessionGroupThisWeek,
      l10n.sessionGroupEarlier,
    ];

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: groupOrder.length,
      itemBuilder: (context, index) {
        final groupKey = groupOrder[index];
        final sessions = groups[groupKey];

        if (sessions == null || sessions.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                groupKey,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // Sessions in this group
            ...sessions.map((session) {
              return _buildSessionCard(
                context,
                session,
                theme,
                l10n,
              );
            }),
          ],
        );
      },
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
                : theme.colorScheme.surfaceContainerHigh,
            border: Border.all(
              color: isCurrent
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Message Count Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Expanded(
                          child: Text(
                            truncatedTitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
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
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.messageCountLabel(messageCount),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
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
}
