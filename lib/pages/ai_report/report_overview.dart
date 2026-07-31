part of '../ai_periodic_report_page.dart';

/// 收藏红心色值：记录页 quote_item_widget 用的是同一个色值，两边必须一致。
/// 是否收进 AppSemanticColors 并统一迁移三处调用，属于全局待决项。
final Color _favoriteAccent = Colors.red.shade400;

extension _AIReportOverview on _AIPeriodicReportPageState {
  /// 构建数据概览
  Widget _buildDataOverview() {
    final l10n = AppLocalizations.of(context);
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalNotes = _periodQuotes.length;
    final totalWords = _periodQuotes.fold<int>(
      0,
      (sum, quote) => sum + quote.content.length,
    );
    final avgWords = totalNotes > 0 ? (totalWords / totalNotes).round() : 0;

    // 必须在 build 期间读取；下面的“最近笔记”预览是在动画回调里构建的，
    // 那里不允许 context.select。没有笔记时不订阅，省掉无谓的重建。
    final showExactTime = totalNotes > 0
        ? context.select<SettingsService, bool>((s) => s.showExactTime)
        : false;
    final showNoteEditTime = totalNotes > 0
        ? context.select<SettingsService, bool>((s) => s.showNoteEditTime)
        : false;

    // 整页一次入场，不再逐块交错。
    // 之前七到十个 TweenAnimationBuilder 用 400~1000ms 错开，最后一块要 1.4 秒
    // 才落位——数据早就到了，用户还得等动画演完才能看清页面。
    return _buildEntrance(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverviewHeader(l10n),
            const SizedBox(height: 16),

            // 数据摘要带 + 三个「最多」chip
            _buildSummaryBand(
              totalNotes: totalNotes,
              totalWords: totalWords,
              avgWords: avgWords,
              activeDays: _getActiveDays(),
            ),
            // 空周期不摆三个「暂无」chip：下面的空状态已经说过一次了。
            // 摘要带保留——四个 0 是紧凑的事实，也让切换周期时布局不跳。
            if (totalNotes > 0) ...[
              const SizedBox(height: 10),
              _buildHighlightChips(),
            ],
            const SizedBox(height: 20),

            // 洞察 + AI 对话入口
            _buildInsightBulbBar(),
            const SizedBox(height: 12),
            _buildQuickEntries(),
            const SizedBox(height: 24),

            if (_periodQuotes.isNotEmpty) ...[
              _buildPeriodTopFavoritesSection(),
              const SizedBox(height: 20),
              _buildRecentNotesSection(
                l10n,
                showExactTime: showExactTime,
                showNoteEditTime: showNoteEditTime,
              ),
            ] else
              _buildEmptyState(),
          ],
        ),
      ),
    );
  }

  /// 统一的入场动画：一层 300ms 的淡入 + 轻微上移。
  Widget _buildEntrance({required Widget child}) {
    if (!_shouldAnimateOverview) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey('overview_$_dataKey'),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      tween: Tween(begin: 0.0, end: 1.0),
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildOverviewHeader(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.analytics_outlined,
            color: theme.colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.dataOverview, style: theme.textTheme.titleLarge),
              Text(
                _getDateRangeText(l10n),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentNotesSection(
    AppLocalizations l10n, {
    required bool showExactTime,
    required bool showNoteEditTime,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(l10n.recentNotes, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        ..._periodQuotes.take(3).map(
              (quote) => _buildQuotePreview(
                quote,
                showExactTime: showExactTime,
                showNoteEditTime: showNoteEditTime,
              ),
            ),
      ],
    );
  }

  // 构建“本周期收藏最多”的展示区域
  Widget _buildPeriodTopFavoritesSection() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 过滤出有心形点击的笔记，并按次数排序
    final List<Quote> favorited = _periodQuotes
        .where((q) => q.favoriteCount > 0)
        .toList()
      ..sort((a, b) => b.favoriteCount.compareTo(a.favoriteCount));

    if (favorited.isEmpty) {
      // 若本周期没有心形点击，显示一个轻量提示
      return Row(
        children: [
          Icon(
            Icons.favorite_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.noFavoritesInPeriod,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.favorite, size: 20, color: _favoriteAccent),
            const SizedBox(width: 8),
            Text(
              l10n.mostFavoritedInPeriod,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...favorited.take(3).map(_buildFavoritePreviewChip),
      ],
    );
  }

  // 一个紧凑的收藏预览块
  Widget _buildFavoritePreviewChip(Quote quote) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            // 可以添加跳转到笔记详情的逻辑
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _favoriteAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${quote.favoriteCount}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    StringUtils.truncateForPreview(quote.content, 80),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建 AI 对话快捷入口
  Widget _buildQuickEntries() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _buildEntryCard(
      icon: Icons.lightbulb_outline,
      title: l10n.aiChat,
      subtitle: l10n.chatWithAiAssistant,
      color: theme.colorScheme.primaryContainer,
      iconColor: theme.colorScheme.onPrimaryContainer,
      onTap: () => _openAIAssistant(),
    );
  }

  Widget _buildEntryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: iconColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const ExperimentalBadge(
                      compact: true, enableTapNotice: false),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: iconColor.withAlpha(180),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开 AI 助手，传递当前周期数据摘要作为引导
  Future<void> _openAIAssistant() async {
    final navigator = Navigator.of(context);

    final summary = _insightText.trim();

    if (!mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.explore,
          exploreGuideSummary: summary,
        ),
      ),
    );
  }

  // 洞察小灯泡组件 - 真正的流式显示（AI生成一个字就立即显示）
  Widget _buildInsightBulbBar() {
    final l10n = AppLocalizations.of(context);
    // 判断是否正在等待首个响应（加载中但还没有文本）
    final isWaitingFirstResponse = _insightLoading && _insightText.isEmpty;

    // 洞察是这一屏的主角：不用阴影抬升，改用比摘要带更高一档的容器色，
    // 让整页保持同一套扁平的层次语言。
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 生成中由下面的进度条表达，图标保持稳定。
            // 原来那个 0.8→1.0 的 amber 动画只跑一次就停了，本想做的"呼吸"
            // 效果并没有实现，反而多出一层动画。
            Icon(
              Icons.lightbulb,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 等待首个响应时显示加载提示
                  if (isWaitingFirstResponse) ...[
                    Text(
                      l10n.generatingInsightsForPeriod(_getPeriodName(l10n)),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ]
                  // 有文本时直接显示（流式接收中或已完成）
                  else if (_insightText.isNotEmpty)
                    // 直接显示实时文本，不使用打字机动画，流式接收时也不显示加载指示器
                    Text(
                      _insightText,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.5),
                    )
                  // 没有洞察内容且加载完成时显示空状态
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        // 卡片本身已经是 surfaceContainerHigh，这里必须再深一档，
                        // 否则内外同色、层次消失
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.noInsights,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
