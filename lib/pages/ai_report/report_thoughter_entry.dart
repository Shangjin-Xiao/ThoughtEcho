part of '../ai_periodic_report_page.dart';

/// 探索页通往 Thoughter 的入口。
///
/// 之前这里只有一张「与 Thoughter 对话」的卡片，点进去每次都是新会话——
/// `_initServicesAndLoad` 里只有笔记入口会 `getLatestSessionForNote` 恢复，
/// explore 分支直接落到「留空，首条消息时再建」。所以问题不只是入口不好找，
/// 而是没有连续性。这里同时给出三个快捷追问和最近会话列表。
extension _AIReportThoughterEntry on _AIPeriodicReportPageState {
  /// 加载最近的 agent 会话。
  ///
  /// 会话库和笔记库是分开的，取不到时静默降级为不展示，不影响页面其余部分。
  Future<void> _loadRecentSessions() async {
    if (!mounted) return;
    try {
      final service = context.read<ChatSessionService>();
      await service.init();
      final sessions = await service.getAgentSessions();
      if (!mounted) return;
      final recent = sessions
          .take(_AIPeriodicReportPageState._recentSessionLimit)
          .toList();
      final overviews = recent.isEmpty
          ? <String, ChatSessionOverview>{}
          : await service.getSessionOverviews(
              recent.map((s) => s.id).toList(),
            );
      if (!mounted) return;
      _updateState(() {
        _recentSessions = recent;
        _recentSessionOverviews = overviews;
      });
    } catch (e) {
      // 会话服务不可用（未注册 provider、数据库未就绪）时不展示这一块
      AppLogger.d('Recent Thoughter sessions unavailable: $e');
    }
  }

  /// 洞察下方的快捷追问。
  ///
  /// 三个入口都走 `AIAssistantPage.initialQuestion`——它在
  /// `_initServicesAndLoad` 里会直接 `_handleSubmitted`，所以传进去就等于替
  /// 用户问出第一句，不需要改助手页。
  Widget _buildThoughterQuickAsks() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final insight = _insightText.trim();
    // 生成中只有半截洞察，带进对话会让 Thoughter 看到一句没说完的话。
    // 流由本页持有，跳走不会中断，回来就是完整的。
    final hasInsight = insight.isNotEmpty && !_insightLoading;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 没有洞察文本时「追问这条」无从谈起，不显示
        if (hasInsight)
          _buildQuickAskChip(
            icon: Icons.subdirectory_arrow_right,
            label: l10n.exploreAskAboutInsight,
            emphasized: true,
            // 洞察走 openingMessage：它是进上下文的开场白。
            // 不能指望 exploreGuideSummary——那条是 includedInContext: false，
            // 只显示给用户，模型收不到，agent 会不知道「这条」是什么。
            onTap: () => _openThoughter(
              openingMessage: insight,
              initialQuestion: l10n.exploreAskAboutInsightPrompt,
            ),
          ),
        // 另外两个入口同样带上已生成的洞察：不传 openingMessage 时助手页会走
        // _generateAndShowDynamicInsight，用 buildLocalReportInsight 现拼一段
        // 统计文案——用户刚在这一页读到 AI 写的那段，进去却换成系统拼接的，
        // 前后对不上。手上有 AI 洞察就一律用它开场。
        _buildQuickAskChip(
          icon: Icons.summarize_outlined,
          label: l10n.exploreSummarizePeriod(_getPeriodName(l10n)),
          emphasized: !hasInsight,
          onTap: () => _openThoughter(
            openingMessage: hasInsight ? insight : null,
            initialQuestion:
                l10n.exploreSummarizePeriodPrompt(_getPeriodName(l10n)),
          ),
        ),
        _buildQuickAskChip(
          icon: Icons.chat_bubble_outline,
          label: l10n.exploreFreeChat,
          onTap: () => _openThoughter(
            openingMessage: hasInsight ? insight : null,
          ),
        ),
        // 实验性标记跟着入口走，不再单独占一张卡片的位置
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: DefaultTextStyle(
            style: theme.textTheme.labelSmall ?? const TextStyle(),
            child: const ExperimentalBadge(compact: true),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAskChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    final background = emphasized
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = emphasized
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 最近对话：让用户能接着上次聊，而不是每次从白纸开始。
  Widget _buildRecentSessionsSection() {
    if (_recentSessions.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.forum_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.exploreRecentChats,
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: _openSessionHistory,
              child: Text(l10n.exploreViewAllChats),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ..._recentSessions.map(_buildRecentSessionTile),
      ],
    );
  }

  Widget _buildRecentSessionTile(ChatSession session) {
    final theme = Theme.of(context);
    final snippet = _recentSessionOverviews[session.id]?.snippet.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius:
            BorderRadius.circular(AppShapeTokens.of(context).buttonRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openThoughter(session: session),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (snippet.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  TimeUtils.formatElapsedRelativeTimeLocalized(
                    context,
                    session.lastActiveAt,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 打开 Thoughter。
  ///
  /// [session] 非空时深链回那次会话；否则开新会话，并把当前洞察作为引导摘要，
  /// [initialQuestion] 会被助手页自动发出。
  Future<void> _openThoughter({
    ChatSession? session,
    String? initialQuestion,
    String? openingMessage,
  }) async {
    final navigator = Navigator.of(context);

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.explore,
          session: session,
          initialQuestion: initialQuestion,
          openingMessage: session == null ? openingMessage : null,
        ),
      ),
    );
    // 回来时刷新最近会话，标题和摘要可能已经变了
    if (!mounted) return;
    await _loadRecentSessions();
  }

  /// 带着某条笔记进 Thoughter。
  ///
  /// 和「追问这条」同一个模式：带具体上下文进去，而不是又一个泛泛的「打开 AI」。
  /// 走 note 入口而不是 explore——助手页只有 note 分支会
  /// `getLatestSessionForNote` 恢复会话，同一条笔记聊过的会接着上次聊。
  Future<void> _openThoughterForNote(Quote quote) async {
    final navigator = Navigator.of(context);

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.note,
          quote: quote,
        ),
      ),
    );
    if (!mounted) return;
    await _loadRecentSessions();
  }

  Future<void> _openSessionHistory() async {
    final service = context.read<ChatSessionService>();
    final navigator = Navigator.of(context);

    await navigator.push(
      MaterialPageRoute(
        builder: (ctx) => SessionHistoryPage(
          // 空 noteId 走 getAgentSessions()，正是探索页要的那批会话
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (id) {
            Navigator.of(ctx).pop();
            _openThoughterBySessionId(id);
          },
          onDelete: (id) async {
            await service.deleteSession(id);
            await _loadRecentSessions();
          },
          onNewChat: () {
            Navigator.of(ctx).pop();
            _openThoughter();
          },
        ),
      ),
    );
    if (!mounted) return;
    await _loadRecentSessions();
  }

  Future<void> _openThoughterBySessionId(String id) async {
    final match = _recentSessions.where((s) => s.id == id).firstOrNull;
    if (match != null) {
      await _openThoughter(session: match);
      return;
    }
    if (!mounted) return;
    try {
      final service = context.read<ChatSessionService>();
      final all = await service.getAgentSessions();
      final session = all.where((s) => s.id == id).firstOrNull;
      if (!mounted || session == null) return;
      await _openThoughter(session: session);
    } catch (e) {
      AppLogger.d('Failed to open Thoughter session $id: $e');
    }
  }
}
