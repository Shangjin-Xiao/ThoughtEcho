part of '../explore_page.dart';

extension _ExploreTimeSelector on _ExplorePageState {
  Widget _buildExplorePage(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            if (_isLoadingData)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SliverToBoxAdapter(
                child: _buildDataOverview(),
              ),
            // 底部悬浮的 + 按钮会盖住最后一条内容，留出它的高度
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }

  /// 周期选择器：紧凑的一枚 chip，挂在「数据概览」标题右侧。
  ///
  /// 原来是页面顶部一整张带标题和边框的卡片（展开态占近 300px），里面还有
  /// 一个填充底色的日历按钮——是全页最重的元素，却只是个筛选器；折叠态
  /// 显示的「周 - 7月27日 - 8月2日」又和紧挨着的「数据概览」副标题
  /// 完全重复。合并之后重复消失，滚动折叠那套机制也一并去掉了。
  Widget _buildPeriodPicker() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return MenuAnchor(
      builder: (context, controller, child) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding:
                const EdgeInsets.only(left: 12, right: 8, top: 7, bottom: 7),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // 说全了：翻到上周就写「上周」，翻到更早就写日期范围。
                  // 只写「周」时，选没选过具体日期从这枚 chip 上看不出来。
                  _getPeriodLabel(l10n),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        );
      },
      menuChildren: [
        _buildPeriodMenuItem('week', l10n.thisWeek, Icons.view_week),
        _buildPeriodMenuItem(
            'month', l10n.thisMonth, Icons.calendar_view_month),
        _buildPeriodMenuItem('year', l10n.thisYear, Icons.today),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.calendar_today,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: _selectDate,
          child: Text(l10n.selectDate),
        ),
      ],
    );
  }

  Widget _buildPeriodMenuItem(
    String value,
    String label,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final selected = _selectedPeriod == value;
    return MenuItemButton(
      leadingIcon: Icon(
        icon,
        size: 18,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      trailingIcon: selected
          ? Icon(Icons.check, size: 18, color: theme.colorScheme.primary)
          : null,
      onPressed: () {
        // 菜单里写的就是「本周 / 本月 / 本年」，那它就该真的回到"本"。
        // 原来只换 period 不动 _selectedDate：用户先挑了上周某天，再点
        // 「本周」，选中的仍是上周——菜单说一套、页面做另一套。回到今天
        // 之后，"翻到过去"只由下面那条「选择具体日期」负责。
        final now = DateTime.now();
        final alreadyCurrent = value == _selectedPeriod &&
            ReportPeriodUtils.offsetFromNow(value, _selectedDate, now: now) ==
                ReportPeriodOffset.current;
        if (alreadyCurrent) return;
        _updateState(() {
          _selectedPeriod = value;
          _selectedDate = now;
        });
        _loadPeriodData();
      },
      child: Text(
        label,
        style: selected ? TextStyle(color: theme.colorScheme.primary) : null,
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
