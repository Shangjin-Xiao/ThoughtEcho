import 'package:flutter/material.dart';
import '../models/note_category.dart';
import '../utils/icon_utils.dart'; // Import IconUtils
import '../services/weather_service.dart'; // Import WeatherService
import '../utils/time_utils.dart'; // Import TimeUtils

class NoteFilterSortSheet extends StatefulWidget {
  final List<NoteCategory> allTags;
  final List<String> selectedTagIds;
  final String sortType;
  final bool sortAscending;
  final List<String>? selectedWeathers;
  final List<String>? selectedDayPeriods;
  final void Function(
    List<String> tagIds,
    String sortType,
    bool sortAscending,
    List<String> selectedWeathers,
    List<String> selectedDayPeriods,
  )
  onApply;

  const NoteFilterSortSheet({
    super.key,
    required this.allTags,
    required this.selectedTagIds,
    required this.sortType,
    required this.sortAscending,
    this.selectedWeathers,
    this.selectedDayPeriods,
    required this.onApply,
  });

  @override
  State<NoteFilterSortSheet> createState() => _NoteFilterSortSheetState();
}

class _NoteFilterSortSheetState extends State<NoteFilterSortSheet> {
  static const Map<String, String> _sortTypeKeyToLabel = {
    'time': '按时间排序',
    'name': '按名称排序',
  };

  late List<String> _tempSelectedTagIds;
  late String _tempSortType;
  late bool _tempSortAscending;
  late List<String> _tempSelectedWeathers;
  late List<String> _tempSelectedDayPeriods;

  // 性能优化：缓存常用数据
  late final List<String> _weatherCategories;
  late final List<String> _dayPeriodKeys;

  // 性能优化：缓存天气图标和标签映射，避免build过程中重复计算
  late final Map<String, IconData> _weatherIconCache;
  late final Map<String, String> _weatherLabelCache;
  late final Map<String, IconData> _dayPeriodIconCache;
  late final Map<String, String> _dayPeriodLabelCache;

  @override
  void initState() {
    super.initState();
    _tempSelectedTagIds = List.from(widget.selectedTagIds);
    _tempSortType = widget.sortType;
    _tempSortAscending = widget.sortAscending;
    _tempSelectedWeathers =
        widget.selectedWeathers != null
            ? List.from(widget.selectedWeathers!)
            : <String>[];
    _tempSelectedDayPeriods =
        widget.selectedDayPeriods != null
            ? List.from(widget.selectedDayPeriods!)
            : <String>[];

    // 性能优化：预计算常用数据和缓存映射
    _weatherCategories = WeatherService.filterCategoryToLabel.keys.toList();
    _dayPeriodKeys = TimeUtils.dayPeriodKeyToLabel.keys.toList();

    // 预缓存天气相关数据
    _weatherIconCache = {};
    _weatherLabelCache = {};
    for (final category in _weatherCategories) {
      _weatherIconCache[category] = WeatherService.getFilterCategoryIcon(
        category,
      );
      _weatherLabelCache[category] =
          WeatherService.filterCategoryToLabel[category]!;
    }

    // 预缓存时间段相关数据
    _dayPeriodIconCache = {};
    _dayPeriodLabelCache = {};
    for (final periodKey in _dayPeriodKeys) {
      _dayPeriodIconCache[periodKey] = TimeUtils.getDayPeriodIconByKey(
        periodKey,
      );
      _dayPeriodLabelCache[periodKey] = TimeUtils.getDayPeriodLabel(periodKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    return Padding(
      padding: MediaQuery.of(context).viewInsets.add(const EdgeInsets.all(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和重置按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '筛选与排序',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _tempSelectedTagIds.clear();
                        _tempSortType = 'time';
                        _tempSortAscending = false;
                        _tempSelectedWeathers.clear();
                        _tempSelectedDayPeriods.clear();
                      });
                    },
                    child: const Text('重置'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 筛选条件卡片
              _buildFilterCard(
                title: '标签筛选',
                child: _buildTagsFilter(theme),
                theme: theme,
                showScrollHint: widget.allTags.isNotEmpty,
              ),
              const SizedBox(height: 12),

              _buildFilterCard(
                title: '天气筛选',
                child: _buildWeatherFilter(theme),
                theme: theme,
                showScrollHint: true,
              ),
              const SizedBox(height: 12),

              _buildFilterCard(
                title: '时间段筛选',
                child: _buildDayPeriodFilter(theme),
                theme: theme,
                showScrollHint: true,
              ),
              const SizedBox(height: 12),

              _buildFilterCard(
                title: '排序方式',
                child: _buildSortOptions(theme),
                theme: theme,
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed:
                        _hasChanges()
                            ? () {
                              widget.onApply(
                                _tempSelectedTagIds,
                                _tempSortType,
                                _tempSortAscending,
                                _tempSelectedWeathers,
                                _tempSelectedDayPeriods,
                              );
                              Navigator.pop(context);
                            }
                            : null, // 优化：如果没有变化则禁用按钮
                    child: const Text('应用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建筛选条件卡片
  Widget _buildFilterCard({
    required String title,
    required Widget child,
    required ThemeData theme,
    bool showScrollHint = false,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (showScrollHint) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.swipe_left,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  /// 构建水平滑动筛选器包装器
  Widget _buildHorizontalScrollableFilter({
    required List<Widget> children,
    required ThemeData theme,
  }) {
    if (children.isEmpty) {
      return const SizedBox(height: 40);
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: children.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => children[index],
        physics: const BouncingScrollPhysics(),
      ),
    );
  }

  /// 构建标签筛选器
  Widget _buildTagsFilter(ThemeData theme) {
    if (widget.allTags.isEmpty) {
      return Text(
        '暂无标签',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final chips =
        widget.allTags.map((tag) {
          final isSelected = _tempSelectedTagIds.contains(tag.id);
          // Use IconUtils to get the icon
          final bool isEmoji = IconUtils.isEmoji(tag.iconName);
          final dynamic tagIcon = IconUtils.getIconData(
            tag.iconName,
          ); // getIconData handles null/empty and returns default

          return FilterChip(
            selected: isSelected,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tag.iconName != null && tag.iconName!.isNotEmpty)
                  isEmoji
                      ? Text(
                        tag.iconName!,
                        style: const TextStyle(fontSize: 16),
                      )
                      // Use the IconData from IconUtils
                      : (tagIcon is IconData) // Check if it's IconData
                      ? Icon(tagIcon, size: 16)
                      : const SizedBox.shrink(), // Fallback if not IconData (though getIconData should return a default)                if (tag.iconName != null && tag.iconName!.isNotEmpty)
                  const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    tag.name, 
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _tempSelectedTagIds.add(tag.id);
                } else {
                  _tempSelectedTagIds.remove(tag.id);
                }
              });
            },
          );
        }).toList();

    return _buildHorizontalScrollableFilter(children: chips, theme: theme);
  }

  /// 构建天气筛选器
  Widget _buildWeatherFilter(ThemeData theme) {
    final chips =
        _weatherCategories.map((filterCategory) {
          final isSelected = _tempSelectedWeathers.any(
            (selectedWeather) => WeatherService.getWeatherKeysByFilterCategory(
              filterCategory,
            ).contains(selectedWeather),
          );
          // 使用预缓存的图标和标签，提升性能
          final icon = _weatherIconCache[filterCategory]!;
          final label = _weatherLabelCache[filterCategory]!;
          return FilterChip(
            selected: isSelected,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label, 
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onSelected: (selected) {
              setState(() {
                final categoryKeys =
                    WeatherService.getWeatherKeysByFilterCategory(
                      filterCategory,
                    );
                if (selected) {
                  // 添加该分类下的所有天气key
                  _tempSelectedWeathers.addAll(categoryKeys);
                } else {
                  // 移除该分类下的所有天气key
                  _tempSelectedWeathers.removeWhere(
                    (weather) => categoryKeys.contains(weather),
                  );
                }
              });
            },
          );
        }).toList();

    return _buildHorizontalScrollableFilter(children: chips, theme: theme);
  }

  /// 构建时间段筛选器
  Widget _buildDayPeriodFilter(ThemeData theme) {
    final chips =
        _dayPeriodKeys.map((periodKey) {
          final isSelected = _tempSelectedDayPeriods.contains(periodKey);
          // 使用预缓存的图标和标签，提升性能
          final icon = _dayPeriodIconCache[periodKey]!;
          final label = _dayPeriodLabelCache[periodKey]!;
          return FilterChip(
            selected: isSelected,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label, 
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _tempSelectedDayPeriods.add(periodKey);
                } else {
                  _tempSelectedDayPeriods.remove(periodKey);
                }
              });
            },
          );
        }).toList();

    return _buildHorizontalScrollableFilter(children: chips, theme: theme);
  }

  /// 构建排序选项
  Widget _buildSortOptions(ThemeData theme) {
    return Column(
      children: [
        ..._sortTypeKeyToLabel.entries.map(
          (entry) => RadioListTile<String>(
            title: Text(entry.value),
            value: entry.key,
            groupValue: _tempSortType,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) {
              setState(() {
                _tempSortType = value!;
              });
            },
          ),
        ),
        SwitchListTile(
          title: const Text('升序'),
          value: _tempSortAscending,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            setState(() {
              _tempSortAscending = value;
            });
          },
        ),
      ],
    );
  }

  /// 优化：检查是否有筛选条件变化
  bool _hasChanges() {
    return !_areListsEqual(_tempSelectedTagIds, widget.selectedTagIds) ||
        _tempSortType != widget.sortType ||
        _tempSortAscending != widget.sortAscending ||
        !_areListsEqual(_tempSelectedWeathers, widget.selectedWeathers ?? []) ||
        !_areListsEqual(
          _tempSelectedDayPeriods,
          widget.selectedDayPeriods ?? [],
        );
  }

  /// 优化：辅助方法：比较两个列表是否相等
  bool _areListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }
}
