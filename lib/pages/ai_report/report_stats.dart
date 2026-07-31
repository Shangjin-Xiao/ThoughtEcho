part of '../ai_periodic_report_page.dart';

extension _AIReportStats on _AIPeriodicReportPageState {
  /// 数据摘要带：把四个计数指标压成一条，不再各占一张卡片。
  ///
  /// 之前四张 elevation:2 的卡片和下面三个「最多」卡片视觉权重相同，
  /// 七块同样重的内容并排等于没有重点，也把页面唯一的出口挤到了下方。
  Widget _buildSummaryBand({
    required int totalNotes,
    required int totalWords,
    required int avgWords,
    required int activeDays,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Row(
        children: [
          _buildSummaryMetric(
            value: '$totalNotes',
            unit: l10n.notesUnitPlain,
            label: l10n.noteCount,
          ),
          _buildSummaryDivider(),
          _buildSummaryMetric(
            value: '$totalWords',
            unit: l10n.wordsUnitPlain,
            label: l10n.totalWordCount,
          ),
          _buildSummaryDivider(),
          _buildSummaryMetric(
            value: '$activeDays',
            unit: l10n.daysUnitPlain,
            label: l10n.activeDays,
          ),
          _buildSummaryDivider(),
          _buildSummaryMetric(
            value: '$avgWords',
            unit: l10n.wordsUnitPlain,
            label: l10n.avgWords,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String value,
    required String unit,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$label $value $unit',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    unit,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(
            alpha: 0.6,
          ),
    );
  }

  /// 三个「最多」指标：它们的值是分类而不是量，用 chip 比用数字卡片更贴切。
  Widget _buildHighlightChips() {
    final l10n = AppLocalizations.of(context);
    // 提到局部变量才能让类型提升生效，省掉重复的 is/as 判断
    final tagIcon = _mostTopTagIcon;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildHighlightChip(
          label: l10n.commonPeriod,
          value: _mostDayPeriodDisplay ?? l10n.noDataYet,
          icon: _mostDayPeriodIcon ?? Icons.timelapse,
        ),
        _buildHighlightChip(
          label: l10n.commonWeather,
          value: _mostWeatherDisplay ?? l10n.noDataYet,
          icon: _mostWeatherIcon ?? Icons.cloud_queue,
        ),
        _buildHighlightChip(
          label: l10n.commonTag,
          value: _mostTopTag ?? l10n.noDataYet,
          icon: tagIcon is IconData ? tagIcon : null,
          emoji: tagIcon is IconData ? null : tagIcon?.toString(),
        ),
      ],
    );
  }

  Widget _buildHighlightChip({
    required String label,
    required String value,
    IconData? icon,
    String? emoji,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: ConstrainedBox(
        // 标签名可以很长，不约束的话单个 chip 会把窄屏撑破
        constraints: const BoxConstraints(maxWidth: 180),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null)
                Text(emoji, style: const TextStyle(fontSize: 14))
              else
                Icon(
                  icon ?? Icons.local_offer_outlined,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 空状态：整页只说一次「没有笔记」。
  /// 之前是七张全 0 的卡片 + 三个「暂无」+ 这段文案，同一件事说了三遍；
  /// 现在只保留紧凑的摘要带（四个 0 是事实，也让切换周期时布局不跳）加这段。
  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noNotesInPeriodForPeriod(_getPeriodName(l10n)),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.startRecordingThoughts,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建笔记预览
  /// [showExactTime]/[showNoteEditTime] 由调用方在 build 期间读取后传入，
  /// 避免本方法被放进动画回调时再去 context.select。
  Widget _buildQuotePreview(
    Quote quote, {
    required bool showExactTime,
    required bool showNoteEditTime,
  }) {
    final l10n = AppLocalizations.of(context);
    final date = DateTime.parse(quote.date);
    final formattedDate = TimeUtils.formatQuoteDateLocalized(
      context,
      date,
      dayPeriod: quote.dayPeriod,
      showExactTime: showExactTime,
    );
    final DateTime? lastModified = quote.lastModified != null
        ? DateTime.tryParse(quote.lastModified!)
        : null;
    final bool shouldShowEditedAt = showNoteEditTime &&
        lastModified != null &&
        !lastModified.isAtSameMomentAs(date);
    final String? formattedEditedAt = shouldShowEditedAt
        ? l10n.editedAtLabel(
            TimeUtils.formatQuoteDateLocalized(
              context,
              lastModified,
              showExactTime: showExactTime,
            ),
          )
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        // 已经有描边了，不再叠阴影；页面统一走扁平分层
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // 添加点击反馈
            HapticFeedback.lightImpact();
            // 可以添加跳转到笔记详情的逻辑
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  StringUtils.truncateForPreview(quote.content, 120),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formattedDate,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                if (formattedEditedAt != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    formattedEditedAt,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 11,
                                          height: 1.1,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${quote.content.length}${l10n.wordsUnitPlain}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
