part of '../ai_periodic_report_page.dart';

extension _AIReportTimeSelector on _AIPeriodicReportPageState {
  Widget _buildReportPage(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // 只响应最外层滚动视图的、用户真实拖动/惯性产生的滚动。
            // 折叠会改变内容高度，进而引发布局修正型的 ScrollUpdateNotification；
            // 若把这类通知也算进来，就会出现 折叠→修正→展开→修正→折叠 的来回抖动。
            if (notification is! ScrollUpdateNotification ||
                notification.depth != 0) {
              return false;
            }
            final delta = notification.scrollDelta;
            if (delta == null) return false;
            final pixels = notification.metrics.pixels;
            if (delta > 10 && !_isTimeSelectorCollapsed && pixels > 24) {
              _setTimeSelectorCollapsed(true);
            } else if (delta < -10 && _isTimeSelectorCollapsed) {
              _setTimeSelectorCollapsed(false);
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: SizedBox(height: 16),
              ),
              SliverToBoxAdapter(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  height: _isTimeSelectorCollapsed ? 60 : null,
                  child: _buildTimeSelector(),
                ),
              ),
              if (_isLoadingData)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SliverToBoxAdapter(
                  child: _buildDataOverview(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 切换折叠状态，并在动画期间上锁。
  ///
  /// 折叠动画本身会改变滚动内容高度，从而再次触发滚动通知；没有这把锁时，
  /// 一次滚动就可能连续翻转好几次，表现为顶部选择器来回闪。
  void _setTimeSelectorCollapsed(bool collapsed, {bool force = false}) {
    if (_isTimeSelectorCollapsed == collapsed) return;
    final now = DateTime.now();
    final last = _lastCollapseToggleAt;
    if (!force &&
        last != null &&
        now.difference(last) <
            _AIPeriodicReportPageState._collapseToggleCooldown) {
      return;
    }
    _lastCollapseToggleAt = now;
    _updateState(() {
      _isTimeSelectorCollapsed = collapsed;
    });
  }

  /// 构建时间选择器
  Widget _buildTimeSelector() {
    return GestureDetector(
      onTap: () => _setTimeSelectorCollapsed(
        !_isTimeSelectorCollapsed,
        force: true,
      ),
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
            ).textTheme.bodyMedium,
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
                ).textTheme.titleMedium,
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
      });
      _loadPeriodData();
    }
  }
}
