import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/chat_session.dart';
import '../../services/chat_session_service.dart';
import '../../theme/app_semantic_colors.dart';
import '../../theme/theme_style.dart';
import '../../utils/app_logger.dart';
import '../../utils/time_utils.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_loading_view.dart';
import '../../widgets/app_snackbar.dart';

part 'session_history_page_content.dart';

/// 会话历史独立页面 - 现代卡片风格设计
class SessionHistoryPage extends StatefulWidget {
  final String noteId;
  final String? currentSessionId;
  final ChatSessionService chatSessionService;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final FutureOr<void> Function(List<String> ids)? onBatchDelete;
  final VoidCallback onNewChat;

  const SessionHistoryPage({
    super.key,
    required this.noteId,
    required this.currentSessionId,
    required this.chatSessionService,
    required this.onSelect,
    required this.onDelete,
    this.onBatchDelete,
    required this.onNewChat,
  });

  @override
  State<SessionHistoryPage> createState() => _SessionHistoryPageState();
}

class _SessionHistoryPageState extends State<SessionHistoryPage> {
  List<ChatSession>? _sessions;
  List<ChatSessionSearchResult>? _searchResults;
  bool _isLoading = true;
  bool _isSearching = false;
  Map<String, int> _messageCounts = {};
  Map<String, String> _lastMessageSnippets = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _isMultiSelectMode = false;
  final Set<String> _selectedSessionIds = {};

  /// 笔记入口默认只看这条笔记的对话，但用户也要能翻到全部对话。
  /// 探索入口本来就是全部（noteId 为空），不显示切换。
  bool _showAllSessions = false;

  bool get _isNoteScoped => widget.noteId.isNotEmpty;

  List<ChatSession> get _currentVisibleSessions {
    if (_searchQuery.isNotEmpty) {
      return _searchResults?.map((r) => r.session).toList() ?? [];
    }
    return _sessions ?? [];
  }

  bool get _areAllVisibleSessionsSelected {
    final visible = _currentVisibleSessions;
    if (visible.isEmpty) return false;
    return visible.every((s) => _selectedSessionIds.contains(s.id));
  }

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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final List<ChatSession> sessions;
      if (!_isNoteScoped || _showAllSessions) {
        sessions = await widget.chatSessionService.getAllSessions();
      } else {
        sessions =
            await widget.chatSessionService.getSessionsForNote(widget.noteId);
      }

      final overviews = await widget.chatSessionService.getSessionOverviews(
        sessions.map((session) => session.id).toList(),
      );
      final counts = <String, int>{
        for (final session in sessions)
          session.id: overviews[session.id]?.messageCount ?? 0,
      };
      final snippets = <String, String>{
        for (final session in sessions)
          session.id: overviews[session.id]?.snippet ?? '',
      };

      final visibleSessions = sessions
          .where((session) => !_isEmptyUntitledSession(
                session,
                counts[session.id] ?? 0,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _sessions = visibleSessions;
          _messageCounts = counts;
          _lastMessageSnippets = snippets;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.e('Failed to load sessions', error: e);
      if (mounted) {
        setState(() {
          _sessions = [];
          _messageCounts = {};
          _lastMessageSnippets = {};
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _performSearch(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = null;
          _isSearching = false;
        });
      }
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results =
          await widget.chatSessionService.searchSessions(trimmedQuery);

      if (results.isNotEmpty) {
        final missingIds = results
            .map((r) => r.session.id)
            .where((id) => !_messageCounts.containsKey(id))
            .toList();
        if (missingIds.isNotEmpty) {
          final overviews =
              await widget.chatSessionService.getSessionOverviews(missingIds);
          for (final entry in overviews.entries) {
            _messageCounts[entry.key] = entry.value.messageCount;
          }
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      AppLogger.e('Search sessions failed', error: e);
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  void _enterMultiSelectMode({String? initialSelectedId}) {
    HapticFeedback.selectionClick();
    setState(() {
      _isMultiSelectMode = true;
      _selectedSessionIds.clear();
      if (initialSelectedId != null) {
        _selectedSessionIds.add(initialSelectedId);
      }
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedSessionIds.clear();
    });
  }

  void _toggleSessionSelection(String sessionId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedSessionIds.contains(sessionId)) {
        _selectedSessionIds.remove(sessionId);
      } else {
        _selectedSessionIds.add(sessionId);
      }
    });
  }

  void _toggleSelectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      final visible = _currentVisibleSessions;
      if (_areAllVisibleSessionsSelected) {
        _selectedSessionIds.clear();
      } else {
        _selectedSessionIds.addAll(visible.map((s) => s.id));
      }
    });
  }

  Future<void> _confirmBatchDelete() async {
    final count = _selectedSessionIds.length;
    if (count == 0) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteSelectedChats),
        content: Text(l10n.deleteSelectedChatsConfirm(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _executeBatchDelete();
    }
  }

  Future<void> _executeBatchDelete() async {
    final idsToDelete = _selectedSessionIds.toList();
    if (idsToDelete.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    try {
      if (widget.onBatchDelete != null) {
        await widget.onBatchDelete!(idsToDelete);
      } else {
        await widget.chatSessionService.deleteSessions(idsToDelete);
        for (final id in idsToDelete) {
          widget.onDelete(id);
        }
      }

      if (!mounted) return;
      final deletedCount = idsToDelete.length;
      _exitMultiSelectMode();
      await _loadSessions();
      if (_searchQuery.isNotEmpty) {
        await _performSearch(_searchQuery);
      }
      if (mounted) {
        AppSnackBar.success(context, l10n.deleteChatsSuccess(deletedCount));
      }
    } catch (e) {
      AppLogger.e('Batch delete sessions failed', error: e);
      if (mounted) {
        AppSnackBar.error(context, l10n.deleteFailedSimple);
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

    return PopScope(
      canPop: !_isMultiSelectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isMultiSelectMode) {
          _exitMultiSelectMode();
        }
      },
      child: Scaffold(
        appBar: _isMultiSelectMode
            ? _buildMultiSelectAppBar(context, theme, l10n)
            : _buildNormalAppBar(context, theme, l10n),
        body: Column(
          children: [
            if (_isNoteScoped && !_isMultiSelectMode) _buildScopeSelector(l10n),
            if (!_isMultiSelectMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: SearchBar(
                  controller: _searchController,
                  hintText: l10n.searchChatHistory,
                  leading: const Icon(Icons.search, size: 20),
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(
                    theme.colorScheme.surfaceContainerHighest,
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppShapeTokens.of(context).inputRadius,
                      ),
                    ),
                  ),
                  trailing: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: l10n.clear,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _searchResults = null;
                          });
                        },
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _performSearch(value);
                  },
                ),
              ),
            Expanded(
              child: _buildBody(context, theme, l10n),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    final visibleCount = _currentVisibleSessions.length;
    return AppBar(
      title: Text(l10n.chatHistory),
      actions: [
        if (visibleCount > 0)
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: l10n.multiSelectChats,
            onPressed: _enterMultiSelectMode,
          ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: l10n.newChat,
          onPressed: widget.onNewChat,
        ),
      ],
    );
  }

  PreferredSizeWidget _buildMultiSelectAppBar(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    final count = _selectedSessionIds.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: l10n.cancel,
        onPressed: _exitMultiSelectMode,
      ),
      title: Text(l10n.selectedChatCount(count)),
      actions: [
        IconButton(
          icon: Icon(
            _areAllVisibleSessionsSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
          ),
          tooltip: _areAllVisibleSessionsSelected
              ? l10n.deselectAll
              : l10n.selectAll,
          onPressed: _toggleSelectAll,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: l10n.deleteSelectedChats,
          onPressed: count > 0 ? _confirmBatchDelete : null,
          color: count > 0 ? theme.colorScheme.error : null,
        ),
      ],
    );
  }

  Widget _buildScopeSelector(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(l10n.sessionScopeThisNote),
            selected: !_showAllSessions,
            onSelected: (_) => _setShowAllSessions(false),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(l10n.sessionScopeAllChats),
            selected: _showAllSessions,
            onSelected: (_) => _setShowAllSessions(true),
          ),
        ],
      ),
    );
  }

  void _setShowAllSessions(bool showAll) {
    if (_showAllSessions == showAll) return;
    setState(() => _showAllSessions = showAll);
    _loadSessions();
  }

  Widget _buildBody(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    if (_isLoading || (_searchQuery.isNotEmpty && _isSearching)) {
      return const AppLoadingView();
    }

    if (_searchQuery.isNotEmpty) {
      final results = _searchResults;
      if (results == null || results.isEmpty) {
        return _buildEmptyState(theme, l10n);
      }
      return _buildSearchResultsList(context, results, theme, l10n);
    }

    final sessions = _sessions;
    if (sessions == null || sessions.isEmpty) {
      return _buildEmptyState(theme, l10n);
    }

    return _buildGroupedSessionsList(context, sessions, theme, l10n);
  }
}
