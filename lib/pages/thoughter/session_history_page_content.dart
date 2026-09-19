part of 'session_history_page.dart';

extension _SessionHistoryPageContent on _SessionHistoryPageState {
  Widget _buildEmptyState(ThemeData theme, AppLocalizations l10n) =>
      AppEmptyView(text: l10n.noChats);

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
            snippetMatchStart: result.matchStart,
            snippetMatchEnd: result.matchEnd,
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
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
              child: Row(
                children: [
                  Text(
                    groupKey,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(
                        AppShapeTokens.of(context).buttonRadius * 0.4,
                      ),
                    ),
                    child: Text(
                      '${groupSessions.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
    int snippetMatchStart = -1,
    int snippetMatchEnd = -1,
  }) {
    final cardRadius = AppShapeTokens.of(context).cardRadius;
    final isSelected = _selectedSessionIds.contains(session.id);
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cardRadius),
        child: Slidable(
          key: ValueKey(session.id),
          enabled: !_isMultiSelectMode,
          startActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.24,
            children: [
              SlidableAction(
                onPressed: (_) async {
                  await widget.chatSessionService.togglePin(session.id);
                  await _loadSessions();
                  if (_searchQuery.isNotEmpty) {
                    await _performSearch(_searchQuery);
                  }
                },
                backgroundColor: session.isPinned
                    ? AppSemanticColors.of(context).warningContainer
                    : theme.colorScheme.primary,
                foregroundColor: session.isPinned
                    ? AppSemanticColors.of(context).onWarningContainer
                    : theme.colorScheme.onPrimary,
                icon: session.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                label: session.isPinned ? l10n.unpinChat : l10n.pinChat,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(cardRadius),
                ),
              ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.24,
            children: [
              SlidableAction(
                onPressed: (_) => _confirmDelete(context, session.id),
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                icon: Icons.delete_outline_rounded,
                label: l10n.delete,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(cardRadius),
                ),
              ),
            ],
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                  : (isCurrent
                      ? theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3)
                      : theme.colorScheme.surfaceContainerHigh),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : (isCurrent
                        ? theme.colorScheme.primary.withValues(alpha: 0.5)
                        : Colors.transparent),
                width: isSelected || isCurrent ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(cardRadius),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isMultiSelectMode
                    ? () => _toggleSessionSelection(session.id)
                    : (isCurrent ? null : () => widget.onSelect(session.id)),
                onLongPress: _isMultiSelectMode
                    ? () => _toggleSessionSelection(session.id)
                    : () =>
                        _enterMultiSelectMode(initialSelectedId: session.id),
                borderRadius: BorderRadius.circular(cardRadius),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_isMultiSelectMode) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 22,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (session.isPinned) ...[
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: _buildHighlightedText(
                                    text: title,
                                    query: _searchQuery,
                                    baseStyle:
                                        theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ) ??
                                            const TextStyle(
                                                fontWeight: FontWeight.w600),
                                    theme: theme,
                                    useBackground: false,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      AppShapeTokens.of(context).buttonRadius *
                                          0.4,
                                    ),
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
                              (snippetMatchStart >= 0 &&
                                      snippetMatchEnd > snippetMatchStart)
                                  ? _buildHighlightedTextByRange(
                                      text: snippet,
                                      matchStart: snippetMatchStart,
                                      matchEnd: snippetMatchEnd,
                                      baseStyle:
                                          theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ) ??
                                              TextStyle(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                      theme: theme,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : _buildHighlightedText(
                                      text: snippet,
                                      query: _searchQuery,
                                      baseStyle:
                                          theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ) ??
                                              TextStyle(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                      theme: theme,
                                      useBackground: true,
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText({
    required String text,
    required String query,
    required TextStyle baseStyle,
    required ThemeData theme,
    required bool useBackground,
    int maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    if (query.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final List<InlineSpan> spans = [];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    int start = 0;
    int indexOfQuery = lowerText.indexOf(lowerQuery, start);

    final highlightStyle = useBackground
        ? baseStyle.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          )
        : baseStyle.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          );

    while (indexOfQuery != -1) {
      if (indexOfQuery > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfQuery),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfQuery, indexOfQuery + query.length),
        style: highlightStyle,
      ));
      start = indexOfQuery + query.length;
      indexOfQuery = lowerText.indexOf(lowerQuery, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
      ));
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: spans,
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  /// 使用已知的 [matchStart]/[matchEnd] 精确高亮 snippet 中的匹配词。
  /// 由服务层 _buildSnippet 计算得出，无需在 UI 层重新搜索。
  Widget _buildHighlightedTextByRange({
    required String text,
    required int matchStart,
    required int matchEnd,
    required TextStyle baseStyle,
    required ThemeData theme,
    int maxLines = 2,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    final clampedStart = matchStart.clamp(0, text.length);
    final clampedEnd = matchEnd.clamp(clampedStart, text.length);

    final highlightStyle = baseStyle.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
    );

    final spans = <InlineSpan>[];
    if (clampedStart > 0) {
      spans.add(TextSpan(text: text.substring(0, clampedStart)));
    }
    if (clampedEnd > clampedStart) {
      spans.add(
        TextSpan(
          text: text.substring(clampedStart, clampedEnd),
          style: highlightStyle,
        ),
      );
    }
    if (clampedEnd < text.length) {
      spans.add(TextSpan(text: text.substring(clampedEnd)));
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: overflow,
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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
