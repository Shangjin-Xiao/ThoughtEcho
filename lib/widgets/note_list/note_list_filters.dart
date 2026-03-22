part of '../note_list_view.dart';

/// Filter display and chip rendering for NoteListViewState.
extension NoteListFiltersExtension on NoteListViewState {
  /// 构建现代化的筛选条件展示区域
  Widget _buildFilterDisplay(ThemeData theme, double horizontalPadding) {
    final hasFilters = widget.selectedTagIds.isNotEmpty ||
        widget.selectedWeathers.isNotEmpty ||
        widget.selectedDayPeriods.isNotEmpty;

    // 使用 AnimatedSize 实现整个筛选区域的展开/收起动画
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: !hasFilters
          ? const SizedBox.shrink()
          : _buildFilterContent(theme, horizontalPadding),
    );
  }

  /// 构建筛选条件的实际内容
  Widget _buildFilterContent(ThemeData theme, double horizontalPadding) {
    // 收集所有筛选chip
    final List<Widget> allChips = [];

    // 添加标签chip (带图标支持) - 添加进出场动画
    if (widget.selectedTagIds.isNotEmpty) {
      allChips.addAll(
        widget.selectedTagIds.map((tagId) {
          final tag = _effectiveTags.firstWhere(
            (tag) => tag.id == tagId,
            orElse: () => NoteCategory(id: tagId, name: '未知标签'),
          );
          return TweenAnimationBuilder<double>(
            key: ValueKey('tag_$tagId'),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: child,
                ),
              );
            },
            child: _buildModernFilterChip(
              theme: theme,
              label: tag.name,
              icon: IconUtils.isEmoji(tag.iconName)
                  ? IconUtils.getDisplayIcon(tag.iconName)
                  : IconUtils.getIconData(tag.iconName),
              isIconEmoji: IconUtils.isEmoji(tag.iconName),
              color: theme.colorScheme.primary,
              onDeleted: () {
                final newSelectedTags = List<String>.from(widget.selectedTagIds)
                  ..remove(tagId);
                widget.onTagSelectionChanged(newSelectedTags);
              },
            ),
          );
        }),
      );
    }

    // 添加天气chip（按大类显示）
    if (widget.selectedWeathers.isNotEmpty) {
      final Set<String> categorySet = {};
      for (final key in widget.selectedWeathers) {
        final cat = WeatherService.getFilterCategoryByWeatherKey(key);
        if (cat != null) categorySet.add(cat);
      }

      allChips.addAll(
        categorySet.map((cat) {
          final label =
              WeatherService.getLocalizedFilterCategoryLabel(context, cat);
          final icon = WeatherService.getFilterCategoryIcon(cat);
          return TweenAnimationBuilder<double>(
            key: ValueKey('weather_cat_$cat'),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: child,
                ),
              );
            },
            child: _buildModernFilterChip(
              theme: theme,
              label: label,
              icon: icon,
              color: theme.colorScheme.secondary,
              onDeleted: () {
                final keysToRemove =
                    WeatherService.getWeatherKeysByFilterCategory(cat);
                final newWeathers = List<String>.from(widget.selectedWeathers)
                  ..removeWhere((w) => keysToRemove.contains(w));
                widget.onFilterChanged(newWeathers, widget.selectedDayPeriods);
              },
            ),
          );
        }),
      );

      // 处理未归类的key
      final Set<String> knownKeys = categorySet
          .expand((cat) => WeatherService.getWeatherKeysByFilterCategory(cat))
          .toSet();
      final List<String> others =
          widget.selectedWeathers.where((k) => !knownKeys.contains(k)).toList();
      for (final k in others) {
        final label = WeatherService.getLocalizedWeatherLabel(context, k);
        allChips.add(
          TweenAnimationBuilder<double>(
            key: ValueKey('weather_$k'),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: child,
                ),
              );
            },
            child: _buildModernFilterChip(
              theme: theme,
              label: label,
              color: theme.colorScheme.secondary,
              onDeleted: () {
                final newWeathers = List<String>.from(widget.selectedWeathers)
                  ..remove(k);
                widget.onFilterChanged(newWeathers, widget.selectedDayPeriods);
              },
            ),
          ),
        );
      }
    }

    // 添加时间段chip - 添加进出场动画
    if (widget.selectedDayPeriods.isNotEmpty) {
      allChips.addAll(
        widget.selectedDayPeriods.map((periodKey) {
          final periodLabel = TimeUtils.getLocalizedDayPeriodLabel(
            context,
            periodKey,
          );
          final periodIcon = TimeUtils.getDayPeriodIconByKey(periodKey);
          return TweenAnimationBuilder<double>(
            key: ValueKey('period_$periodKey'),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: child,
                ),
              );
            },
            child: _buildModernFilterChip(
              theme: theme,
              label: periodLabel,
              icon: periodIcon,
              color: theme.colorScheme.tertiary,
              onDeleted: () {
                final newDayPeriods = List<String>.from(
                  widget.selectedDayPeriods,
                )..remove(periodKey);
                widget.onFilterChanged(widget.selectedWeathers, newDayPeriods);
              },
            ),
          );
        }),
      );
    }

    // 创建清除全部按钮
    final clearAllButton = Container(
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            widget.onTagSelectionChanged([]);
            widget.onFilterChanged([], []);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      ),
    );

    final width = MediaQuery.of(context).size.width;
    final isTablet = width > AppConstants.tabletMinWidth;
    final maxWidth = isTablet ? AppConstants.tabletMaxContentWidth : width;
    // 为chip之间添加间距
    List<Widget> spacedChips = [];
    for (int i = 0; i < allChips.length; i++) {
      spacedChips.add(allChips[i]);
      if (i != allChips.length - 1) {
        spacedChips.add(const SizedBox(width: 8));
      }
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(
          horizontalPadding,
          6.0,
          horizontalPadding,
          0,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 筛选图标 - 与芯片同高
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    Icons.filter_alt_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: spacedChips,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              clearAllButton,
            ],
          ),
        ),
      ),
    );
  }

  /// 构建现代化的筛选条件芯片 (支持图标显示)
  Widget _buildModernFilterChip({
    required ThemeData theme,
    required String label,
    required Color color,
    required VoidCallback onDeleted,
    dynamic icon,
    bool isIconEmoji = false,
  }) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 10, right: icon != null ? 4 : 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  if (isIconEmoji) ...[
                    Text(icon as String, style: const TextStyle(fontSize: 15)),
                  ] else ...[
                    Icon(icon as IconData, size: 15, color: color),
                  ],
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onDeleted,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Center(
                  child: Icon(
                    Icons.close,
                    size: 15,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
