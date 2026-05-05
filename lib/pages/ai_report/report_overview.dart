part of '../ai_periodic_report_page.dart';

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题优化：添加图标和更好的视觉层次
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dataOverview,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _getDateRangeText(l10n),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 统计卡片网格 - 根据标志决定是否播放动画
          TweenAnimationBuilder<double>(
            key: ValueKey('stats1_$_dataKey'), // 添加key确保动画只在数据变化时触发
            duration: _shouldAnimateOverview
                ? const Duration(milliseconds: 600)
                : Duration.zero, // 不动画时立即显示
            tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          l10n.noteCount,
                          '$totalNotes',
                          l10n.notesUnitPlain,
                          Icons.note_alt_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          l10n.totalWordCount,
                          '$totalWords',
                          l10n.wordsUnitPlain,
                          Icons.text_fields,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            key: ValueKey('stats2_$_dataKey'),
            duration: _shouldAnimateOverview
                ? const Duration(milliseconds: 800)
                : Duration.zero,
            tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          l10n.avgWords,
                          '$avgWords',
                          l10n.wordsPerNote,
                          Icons.calculate_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          l10n.activeDays,
                          '${_getActiveDays()}',
                          l10n.daysUnitPlain,
                          Icons.calendar_today_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // 新增：三个"最多"指标 - 根据标志决定是否播放动画
          TweenAnimationBuilder<double>(
            key: ValueKey('stats3_$_dataKey'),
            duration: _shouldAnimateOverview
                ? const Duration(milliseconds: 1000)
                : Duration.zero,
            tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCardWithCustomIcon(
                          l10n.commonPeriod,
                          _mostDayPeriodDisplay ?? l10n.noDataYet,
                          '',
                          _mostDayPeriodIcon ?? Icons.timelapse,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCardWithCustomIcon(
                          l10n.commonWeather,
                          _mostWeatherDisplay ?? l10n.noDataYet,
                          '',
                          _mostWeatherIcon ?? Icons.cloud_queue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCardWithTagIcon(
                          l10n.commonTag,
                          _mostTopTag ?? l10n.noDataYet,
                          '',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // 洞察小灯泡（移到常用标签下面）
          _buildInsightBulbBar(),
          const SizedBox(height: 24),

          // 本周期收藏最多（放在洞察下面，最近笔记上面）- 根据标志决定是否播放动画
          if (_periodQuotes.isNotEmpty) ...[
            TweenAnimationBuilder<double>(
              key: ValueKey('favorites_$_dataKey'),
              duration: _shouldAnimateOverview
                  ? const Duration(milliseconds: 800)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: _buildPeriodTopFavoritesSection(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // 最近笔记部分 - 根据标志决定是否播放动画
          if (_periodQuotes.isNotEmpty) ...[
            TweenAnimationBuilder<double>(
              key: ValueKey('recent_$_dataKey'),
              duration: _shouldAnimateOverview
                  ? const Duration(milliseconds: 1000)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.recentNotes,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._periodQuotes.take(3).map(
                              (quote) => TweenAnimationBuilder<double>(
                                duration: Duration(
                                  milliseconds: 600 +
                                      (_periodQuotes.indexOf(quote) * 200),
                                ),
                                tween: Tween(begin: 0.0, end: 1.0),
                                builder: (context, animValue, child) {
                                  return Transform.translate(
                                    offset: Offset(0, 15 * (1 - animValue)),
                                    child: Opacity(
                                      opacity: animValue,
                                      child: _buildQuotePreview(quote),
                                    ),
                                  );
                                },
                              ),
                            ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ] else ...[
            // 空状态优化
            _buildEmptyState(),
          ],
        ],
      ),
    );
  }

  // 构建“本周期收藏最多”的展示区域
  Widget _buildPeriodTopFavoritesSection() {
    final l10n = AppLocalizations.of(context);
    // 过滤出有心形点击的笔记，并按次数排序
    final List<Quote> favorited = _periodQuotes
        .where((q) => q.favoriteCount > 0)
        .toList()
      ..sort((a, b) => b.favoriteCount.compareTo(a.favoriteCount));

    if (favorited.isEmpty) {
      // 若本周期没有心形点击，显示一个轻量提示
      return TweenAnimationBuilder<double>(
        key: ValueKey('favorites_empty_$_dataKey'),
        duration: _shouldAnimateOverview
            ? const Duration(milliseconds: 600)
            : Duration.zero,
        tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Opacity(
              opacity: value,
              child: Row(
                children: [
                  Icon(
                    Icons.favorite_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.noFavoritesInPeriod,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          key: ValueKey('favorites_title_$_dataKey'),
          duration: _shouldAnimateOverview
              ? const Duration(milliseconds: 500)
              : Duration.zero,
          tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: Row(
                  children: [
                    Icon(Icons.favorite, size: 20, color: Colors.red.shade400),
                    const SizedBox(width: 8),
                    Text(
                      l10n.mostFavoritedInPeriod,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        ...favorited.take(3).map(
              (q) => TweenAnimationBuilder<double>(
                key: ValueKey('favorite_${q.id}_$_dataKey'),
                duration: _shouldAnimateOverview
                    ? Duration(milliseconds: 600 + (favorited.indexOf(q) * 150))
                    : Duration.zero,
                tween: Tween(
                  begin: _shouldAnimateOverview ? 0.0 : 1.0,
                  end: 1.0,
                ),
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, 15 * (1 - value)),
                    child: Opacity(
                      opacity: value,
                      child: _buildFavoritePreviewChip(q),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }

  // 一个紧凑的收藏预览块 - 优化视觉效果
  Widget _buildFavoritePreviewChip(Quote quote) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.lightImpact();
            // 可以添加跳转到笔记详情的逻辑
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade100, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 800),
                  tween: Tween(begin: 0.8, end: 1.0),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.shade200,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    quote.content.length > 80
                        ? '${quote.content.substring(0, 80)}...'
                        : quote.content,
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

  // 洞察小灯泡组件 - 真正的流式显示（AI生成一个字就立即显示）
  Widget _buildInsightBulbBar() {
    final l10n = AppLocalizations.of(context);
    // 判断是否正在等待首个响应（加载中但还没有文本）
    final isWaitingFirstResponse = _insightLoading && _insightText.isEmpty;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 灯泡图标：流式接收中闪烁，完成后稳定
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1500),
                tween: Tween(begin: 0.8, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: _insightLoading ? value : 1.0,
                    child: Icon(
                      Icons.lightbulb,
                      color: _insightLoading
                          ? Colors.amber.withValues(alpha: value)
                          : Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              ),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
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
