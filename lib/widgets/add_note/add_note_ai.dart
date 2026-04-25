part of '../add_note_dialog.dart';

extension _AddNoteDialogAI on _AddNoteDialogState {
  /// 显示AI推荐标签对话框
  Future<void> _showAIRecommendedTags(String content) async {
    if (!mounted) return;

    final settingsService = _readServiceOrNull<SettingsService>(context);
    if (settingsService == null) return;

    final localAI = settingsService.localAISettings;
    // 检查是否启用了智能标签推荐
    if (!localAI.enabled || !localAI.smartTagsEnabled) {
      return;
    }

    // TODO: 调用本地AI模型获取推荐标签 - 后端实现后添加
    // 目前返回mock数据
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Mock: 暂时不推荐任何标签
    final List<String> recommendedTagIds = [];

    if (recommendedTagIds.isEmpty) return;

    // 显示推荐标签对话框
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.recommendedTags),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: recommendedTagIds.map((tagId) {
            final tag = _availableTags.firstWhere(
              (t) => t.id == tagId,
              orElse: () => NoteCategory(
                id: tagId,
                name: tagId,
                iconName: 'label',
              ),
            );
            return FilterChip(
              label: Text(tag.name),
              avatar: IconUtils.isEmoji(tag.iconName)
                  ? IconUtils.getDisplayIcon(tag.iconName)
                  : Icon(IconUtils.getIconData(tag.iconName), size: 18),
              onSelected: (selected) {
                // 应用推荐标签
                setState(() {
                  if (selected && !_selectedTagIds.contains(tagId)) {
                    _selectedTagIds.add(tagId);
                  }
                });
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              // 应用所有推荐标签
              setState(() {
                for (final tagId in recommendedTagIds) {
                  if (!_selectedTagIds.contains(tagId)) {
                    _selectedTagIds.add(tagId);
                  }
                }
              });
              Navigator.pop(context);
            },
            child: Text(l10n.applyToEditor),
          ),
        ],
      ),
    );
  }
}
