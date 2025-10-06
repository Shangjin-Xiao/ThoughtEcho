import 'package:flutter/material.dart';
import '../models/note_category.dart';
import '../utils/icon_utils.dart';

/// 标签选择区域 - 独立组件，避免AddNoteDialog重建时重复构建
class TagSelectionSection extends StatefulWidget {
  final List<NoteCategory> tags;
  final List<String> selectedTagIds;
  final ValueChanged<List<String>> onSelectionChanged;
  final bool isLoading;

  const TagSelectionSection({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    required this.onSelectionChanged,
    this.isLoading = false,
  });

  @override
  State<TagSelectionSection> createState() => _TagSelectionSectionState();
}

class _TagSelectionSectionState extends State<TagSelectionSection> {
  final TextEditingController _searchController = TextEditingController();
  List<NoteCategory> _filteredTags = [];
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // 性能优化：初始化时不过滤标签，只在展开时才处理
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TagSelectionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在已展开的情况下才更新过滤
    if (_isExpanded && oldWidget.tags != widget.tags) {
      _updateFilteredTags(_searchController.text);
    }
  }

  void _onSearchChanged() {
    _updateFilteredTags(_searchController.text);
  }

  void _updateFilteredTags(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredTags = widget.tags;
      } else {
        _filteredTags = widget.tags
            .where((tag) => tag.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _toggleTag(String tagId, bool selected) {
    final newSelection = List<String>.from(widget.selectedTagIds);
    if (selected) {
      newSelection.add(tagId);
    } else {
      newSelection.remove(tagId);
    }
    widget.onSelectionChanged(newSelection);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tags.isEmpty) {
      return const Center(child: Text('暂无可用标签，请先添加标签'));
    }

    return ExpansionTile(
      title: Row(
        children: [
          Text(
            '选择标签 (${widget.selectedTagIds.length})',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          if (widget.isLoading) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
      leading: const Icon(Icons.tag),
      initiallyExpanded: _isExpanded,
      onExpansionChanged: (expanded) {
        setState(() {
          _isExpanded = expanded;
          // 性能优化：只在首次展开时初始化过滤列表
          if (expanded && _filteredTags.isEmpty) {
            _filteredTags = widget.tags;
          }
        });
      },
      childrenPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      children: [
        if (_isExpanded) // ✅ 只在展开时构建内容
          _TagSelectionContent(
            searchController: _searchController,
            filteredTags: _filteredTags,
            selectedTagIds: widget.selectedTagIds,
            onToggleTag: _toggleTag,
          ),
      ],
    );
  }
}

/// 标签选择内容 - 进一步拆分，使用const优化
class _TagSelectionContent extends StatelessWidget {
  final TextEditingController searchController;
  final List<NoteCategory> filteredTags;
  final List<String> selectedTagIds;
  final void Function(String tagId, bool selected) onToggleTag;

  const _TagSelectionContent({
    required this.searchController,
    required this.filteredTags,
    required this.selectedTagIds,
    required this.onToggleTag,
  });

  double _computeTagListHeight() {
    const double minHeight = 160.0;
    const double maxHeight = 280.0;
    const double itemHeight = 52.0;

    if (filteredTags.isEmpty) {
      return minHeight;
    }

    final int visibleCount = filteredTags.length < 6 ? filteredTags.length : 6;
    final double estimatedHeight = visibleCount * itemHeight;
    return estimatedHeight.clamp(minHeight, maxHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: searchController,
          decoration: const InputDecoration(
            hintText: '搜索标签...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 12.0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (filteredTags.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('没有找到匹配的标签'),
            ),
          )
        else
          RepaintBoundary( // ✅ 隔离标签列表的重绘
            child: SizedBox(
              height: _computeTagListHeight(),
              child: Scrollbar(
                thumbVisibility: filteredTags.length > 6,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  cacheExtent: 100, // ✅ 移动端减少预渲染
                  itemCount: filteredTags.length,
                  itemBuilder: (context, index) {
                    final tag = filteredTags[index];
                    return _TagListItem(
                      tag: tag,
                      isSelected: selectedTagIds.contains(tag.id),
                      onChanged: (selected) => onToggleTag(tag.id, selected ?? false),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 单个标签项 - 使用const构造函数
class _TagListItem extends StatelessWidget {
  final NoteCategory tag;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _TagListItem({
    required this.tag,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEmoji = IconUtils.isEmoji(tag.iconName);
    final Widget leading = isEmoji
        ? Text(
            IconUtils.getDisplayIcon(tag.iconName),
            style: const TextStyle(fontSize: 20),
          )
        : Icon(IconUtils.getIconData(tag.iconName));

    return CheckboxListTile(
      title: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              tag.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      value: isSelected,
      dense: true,
      controlAffinity: ListTileControlAffinity.trailing,
      onChanged: onChanged,
    );
  }
}

/// 已选标签展示 - 独立组件
class SelectedTagsDisplay extends StatelessWidget {
  final List<String> selectedTagIds;
  final List<NoteCategory> allTags;
  final ValueChanged<String> onRemoveTag;

  const SelectedTagsDisplay({
    super.key,
    required this.selectedTagIds,
    required this.allTags,
    required this.onRemoveTag,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedTagIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '已选标签',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4.0,
            runSpacing: 4.0,
            children: selectedTagIds.map((tagId) {
              final tag = allTags.firstWhere(
                (t) => t.id == tagId,
                orElse: () => NoteCategory(id: tagId, name: '未知标签'),
              );
              return Chip(
                label: IconUtils.isEmoji(tag.iconName)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            IconUtils.getDisplayIcon(tag.iconName),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tag.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      )
                    : Text(tag.name),
                avatar: !IconUtils.isEmoji(tag.iconName)
                    ? Icon(
                        IconUtils.getIconData(tag.iconName),
                        size: 18,
                      )
                    : null,
                deleteIcon: const Icon(Icons.cancel, size: 18),
                onDeleted: () => onRemoveTag(tagId),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
