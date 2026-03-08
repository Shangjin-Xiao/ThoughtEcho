part of '../note_full_editor_page.dart';

/// Metadata editing bottom sheet dialog.
extension NoteEditorMetadataDialog on _NoteFullEditorPageState {
  Future<void> _showMetadataDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.onSurfaceVariant.applyOpacity(
                            // MODIFIED
                            0.4,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).editMetadata,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.check),
                            label: Text(AppLocalizations.of(context).done),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          // 作者/作品输入
                          Text(
                            l10n.sourceInfo,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _authorController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).authorPerson,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _workController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).workSource,
                                    prefixIcon: const Icon(
                                      Icons.menu_book_outlined,
                                    ),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          const SizedBox(height: 24),

                          // 颜色选择
                          Text(
                            l10n.colorLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ListTile(
                              title: Text(l10n.selectCardColorLabel),
                              subtitle: Text(
                                _selectedColorHex == null
                                    ? l10n.noColor
                                    : l10n.colorSet,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _selectedColorHex != null
                                      ? Color(
                                          int.parse(
                                                _selectedColorHex!.substring(1),
                                                radix: 16,
                                              ) |
                                              0xFF000000,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _selectedColorHex == null
                                        ? theme.colorScheme.outline
                                        : Colors.transparent,
                                  ),
                                ),
                                child: _selectedColorHex == null
                                    ? Icon(
                                        Icons.block,
                                        size: 16,
                                        color: theme.colorScheme.outline,
                                      )
                                    : null,
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              onTap: () async {
                                // 使用async/await确保颜色选择完成后刷新UI
                                if (!context.mounted) return;
                                await _showCustomColorPicker(context);
                                // 强制刷新对话框UI以显示新选的颜色
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          _buildMetadataLocationWeatherSection(
                            theme, l10n, setState,
                          ),
                          const SizedBox(height: 24),
                          // 标签选择
                          Row(
                            children: [
                              Text(
                                l10n.tagsLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                l10n.selectedTagsCount(_selectedTagIds.length),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ExpansionTile(
                              title: Text(
                                AppLocalizations.of(context).selectTags,
                              ),
                              leading: const Icon(Icons.sell_outlined),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              children: [
                                // 搜索框
                                TextField(
                                  controller: _tagSearchController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).searchTags,
                                    prefixIcon: const Icon(Icons.search),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                      horizontal: 12.0,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _tagSearchQuery = value.toLowerCase();
                                    });
                                  },
                                ),
                                const SizedBox(height: 8), // 标签列表
                                Container(
                                  constraints: const BoxConstraints(
                                    maxHeight: 200,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Builder(
                                      builder: (context) {
                                        // 过滤标签
                                        final filteredTags =
                                            widget.allTags!.where((tag) {
                                          return _tagSearchQuery.isEmpty ||
                                              tag.name.toLowerCase().contains(
                                                    _tagSearchQuery,
                                                  );
                                        }).toList();

                                        if (filteredTags.isEmpty) {
                                          return Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Text(
                                                AppLocalizations.of(
                                                  context,
                                                ).noMatchingTags,
                                              ),
                                            ),
                                          );
                                        }

                                        return Wrap(
                                          spacing: 8.0,
                                          runSpacing: 8.0,
                                          children: filteredTags.map((tag) {
                                            final selected = _selectedTagIds
                                                .contains(tag.id);
                                            return FilterChip(
                                              selected: selected,
                                              label: Text(tag.name),
                                              avatar: _tagAvatarSmall(
                                                tag.iconName,
                                              ),
                                              onSelected: (bool value) {
                                                setState(() {
                                                  if (value) {
                                                    _selectedTagIds.add(tag.id);
                                                  } else {
                                                    _selectedTagIds.remove(
                                                      tag.id,
                                                    );
                                                  }
                                                });
                                              },
                                              selectedColor: theme
                                                  .colorScheme.primaryContainer,
                                              checkmarkColor:
                                                  theme.colorScheme.primary,
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 显示已选标签
                          if (_selectedTagIds.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.selectedTags,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8.0,
                                    runSpacing: 4.0,
                                    children: _selectedTagIds.map((tagId) {
                                      final tag = widget.allTags!.firstWhere(
                                        (t) => t.id == tagId,
                                        orElse: () => NoteCategory(
                                          id: tagId,
                                          name: l10n.unknownTagWithId(
                                            tagId.substring(
                                              0,
                                              min(4, tagId.length),
                                            ),
                                          ),
                                          iconName: 'help_outline',
                                        ),
                                      );
                                      return Chip(
                                        label: Text(tag.name),
                                        avatar: _buildTagIcon(tag),
                                        onDeleted: () {
                                          setState(() {
                                            _selectedTagIds.remove(tagId);
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    // 优化：对话框关闭后使用单次 setState 更新UI
    if (mounted) {
      setState(() {
        // 强制刷新所有状态
      });
    }
  }
}
