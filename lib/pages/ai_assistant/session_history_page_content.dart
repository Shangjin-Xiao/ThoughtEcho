part of 'session_history_page.dart';

extension _SessionHistoryPageContent on _SessionHistoryPageState {
  Widget _buildEmptyState(ThemeData theme, AppLocalizations l10n) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noChats,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _buildSearchResultsList(
    BuildContext context,
    List<ChatSessionSearchResult> results,
    ThemeData theme,
    AppLocalizations l10n,
  ) =>
      ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          return _buildSessionCard(
            context: context,
            session: result.session,
            snippet: result.snippet,
            theme: theme,
            l10n: l10n,
          );
        },
      );

  Widget _buildGroupedSessionsList(
    BuildContext context,
    List<ChatSession> sessions,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final groups = _groupSessionsByDate(sessions, l10n);
    final groupOrder = [
      l10n.sessionGroupToday,
      l10n.sessionGroupYesterday,
      l10n.sessionGroupThisWeek,
      l10n.sessionGroupEarlier,
    ];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: groupOrder.length,
      itemBuilder: (context, index) {
        final groupKey = groupOrder[index];
        final groupSessions = groups[groupKey];
        if (groupSessions == null || groupSessions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            for (final session in groupSessions)
              _buildSessionCard(
                context: context,
                session: session,
                snippet: _lastMessageSnippets[session.id] ?? '',
                theme: theme,
                l10n: l10n,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSessionCard({
    required BuildContext context,
    required ChatSession session,
    required String snippet,
    required ThemeData theme,
    required AppLocalizations l10n,
  }) {
    final isCurrent = session.id == widget.currentSessionId;
    final messageCount = _messageCounts[session.id] ?? 0;
    final displayTitle = _resolveSessionTitle(session, l10n);
    final title = displayTitle.length > 50
        ? '${displayTitle.substring(0, 50)}...'
        : displayTitle;
    final updated = TimeUtils.formatElapsedRelativeTimeLocalized(
      context,
      session.lastActiveAt,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Slidable(
        key: ValueKey(session.id),
        startActionPane: ActionPane(
          motion: const ScrollMotion(),
          children: [
            SlidableAction(
              onPressed: (_) async {
                await widget.chatSessionService.togglePin(session.id);
                await _loadSessions();
                if (_searchQuery.isNotEmpty) {
                  await _performSearch(_searchQuery);
                }
              },
              backgroundColor:
                  session.isPinned ? Colors.orange : theme.colorScheme.primary,
              foregroundColor: Colors.white,
              icon: session.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              label: session.isPinned ? l10n.unpinChat : l10n.pinChat,
            ),
          ],
        ),
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
                    Row(
                      children: [
                        if (session.isPinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        snippet,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      updated,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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

  bool _isEmptyUntitledSession(ChatSession session, int messageCount) =>
      session.title.trim().isEmpty && messageCount == 0;

  String _resolveSessionTitle(ChatSession session, AppLocalizations l10n) {
    final title = session.title.trim();
    return title.isEmpty ? l10n.unnamed : title;
  }

  void _confirmDelete(BuildContext context, String sessionId) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteChat),
        content: Text(l10n.deleteChatConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              widget.onDelete(sessionId);
              if (!mounted) return;
              await _loadSessions();
              if (_searchQuery.isNotEmpty) {
                await _performSearch(_searchQuery);
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
