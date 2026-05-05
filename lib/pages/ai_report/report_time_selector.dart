part of '../ai_periodic_report_page.dart';

extension _AIReportTimeSelector on _AIPeriodicReportPageState {
  Widget _buildReportPage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        // 现代化标签栏
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildTabItem(0, l10n.dataOverview, Icons.analytics_outlined),
              _buildTabItem(1, l10n.featuredCards, Icons.auto_awesome_outlined),
            ],
          ),
        ),
        // 可折叠的时间选择器
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: _isTimeSelectorCollapsed ? 60 : null,
          child: _buildTimeSelector(),
        ),
        // 内容区域
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                // 向上滚动时折叠
                if (notification.scrollDelta! > 10 &&
                    !_isTimeSelectorCollapsed) {
                  _updateState(() {
                    _isTimeSelectorCollapsed = true;
                  });
                }
                // 向下滚动时展开
                else if (notification.scrollDelta! < -10 &&
                    _isTimeSelectorCollapsed) {
                  _updateState(() {
                    _isTimeSelectorCollapsed = false;
                  });
                }
              }
              return false;
            },
            child: TabBarView(
              controller: _tabController,
              children: [_buildDataOverview(), _buildFeaturedCards()],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建标签项
  Widget _buildTabItem(int index, String title, IconData icon) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建时间选择器
  Widget _buildTimeSelector() {
    return GestureDetector(
      onTap: () {
        _updateState(() {
          _isTimeSelectorCollapsed = !_isTimeSelectorCollapsed;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState: _isTimeSelectorCollapsed
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: _buildCollapsedTimeSelector(),
          secondChild: _buildExpandedTimeSelector(),
        ),
      ),
    );
  }

  /// 构建折叠状态的时间选择器
  Widget _buildCollapsedTimeSelector() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.date_range,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '${_getPeriodName(l10n)} - ${_getDateRangeText(l10n)}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Icon(
            Icons.expand_more,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// 构建展开状态的时间选择器
  Widget _buildExpandedTimeSelector() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.timeRange,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () => _selectDate(),
                  icon: Icon(
                    Icons.calendar_today,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  tooltip: l10n.selectDate,
                  iconSize: 20,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_less,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'week',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.view_week, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        l10n.thisWeek,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'month',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_view_month, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        l10n.thisMonth,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'year',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.today, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        l10n.thisYear,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            selected: {_selectedPeriod},
            onSelectionChanged: (Set<String> selection) {
              _updateState(() {
                _selectedPeriod = selection.first;
                // 切换时间范围时，重置生成的内容
                _featuredCards = [];
                _pendingQuotesForCards = [];
                _selectedCardIndex = null;
              });
              _loadPeriodData();
            },
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// 选择日期
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      _updateState(() {
        _selectedDate = picked;
        // 切换日期时，重置生成的内容
        _featuredCards = [];
        _pendingQuotesForCards = [];
        _selectedCardIndex = null;
      });
      _loadPeriodData();
    }
  }
}
