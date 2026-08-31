import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../extensions/note_tag_localization_extension.dart';
import '../services/database_service.dart';
import '../models/note_tag.dart';
import '../utils/icon_utils.dart';
import '../gen_l10n/app_localizations.dart';
import '../theme/theme_style.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_error_view.dart';

class TagSettingsPage extends StatefulWidget {
  const TagSettingsPage({super.key});

  @override
  State<TagSettingsPage> createState() => _CategorySettingsPageState();
}

class _CategorySettingsPageState extends State<TagSettingsPage> {
  final _categoryController = TextEditingController();
  final _categoryNameController = TextEditingController();
  bool _isLoading = false;
  String? _selectedIconName;

  @override
  void dispose() {
    _categoryController.dispose();
    _categoryNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tagManagement)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.tagManagement,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            // 输入与添加区域卡片化
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _categoryController,
                            maxLength: 50,
                            decoration: InputDecoration(
                              labelText: l10n.newTagName,
                              hintText: l10n.enterTagNameHint,
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  shapeTokens.inputRadius,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: l10n.selectIcon,
                          child: InkWell(
                            onTap: () => _showIconSelector(context),
                            borderRadius: BorderRadius.circular(
                              shapeTokens.cardRadius,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(
                                  shapeTokens.cardRadius,
                                ),
                              ),
                              child: _selectedIconName != null
                                  ? (IconUtils.isEmoji(_selectedIconName)
                                      ? Text(
                                          IconUtils.getDisplayIcon(
                                            _selectedIconName!,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 20,
                                          ),
                                        )
                                      : Icon(
                                          IconUtils.getIconData(
                                            _selectedIconName,
                                          ),
                                        ))
                                  : const Icon(Icons.add_circle_outline),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: _isLoading
                              ? const AppInlineLoadingIndicator(
                                  size: 16,
                                  strokeWidth: 2,
                                )
                              : const Icon(Icons.check),
                          label: Text(_isLoading ? l10n.adding : l10n.add),
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  final text = _categoryController.text.trim();
                                  if (text.isEmpty) {
                                    AppSnackBar.warning(
                                      context,
                                      l10n.pleaseEnterTagName,
                                    );
                                    return;
                                  }
                                  setState(() => _isLoading = true);
                                  try {
                                    final db = context.read<DatabaseService>();
                                    await db.addTag(
                                      text,
                                      iconName: _selectedIconName,
                                    );
                                    if (context.mounted) {
                                      AppSnackBar.success(
                                        context,
                                        l10n.tagAddedSuccess,
                                      );
                                      _categoryController.clear();
                                      setState(() => _selectedIconName = null);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      AppSnackBar.error(
                                        context,
                                        l10n.addTagFailed(e.toString()),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedOpacity(
                      opacity: _selectedIconName != null ? 1 : 0.6,
                      duration: const Duration(milliseconds: 200),
                      child: Row(
                        children: [
                          Icon(
                            _selectedIconName != null &&
                                    !IconUtils.isEmoji(_selectedIconName)
                                ? IconUtils.getIconData(_selectedIconName)
                                : Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _selectedIconName == null
                                  ? l10n.iconSelectionHint
                                  : l10n.iconSelected(_selectedIconName!),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (_selectedIconName != null)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _selectedIconName = null),
                              child: Text(l10n.clear),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<NoteTag>>(
              stream: context.read<DatabaseService>().watchTags(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingView(size: 60);
                }

                if (snapshot.hasError) {
                  return AppErrorView(
                    text: l10n.loadTagsFailed(snapshot.error.toString()),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return AppEmptyView(text: l10n.noTags);
                }

                final categories = snapshot.data!;
                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 0.6,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _buildCategoryItem(
                        category,
                        index,
                        categories.length,
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showIconSelector(BuildContext context) {
    final TextEditingController emojiSearchController = TextEditingController();
    String searchQuery = '';
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    Map<String, bool> expandedTags = {
      l10n.emotion: true,
      l10n.thinking: false,
      l10n.nature: false,
      l10n.mood: false,
      l10n.life: false,
      l10n.growth: false,
      l10n.reward: false,
      l10n.systemIcons: false,
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final emojiCategories = IconUtils.getCategorizedEmojis();

          Map<String, List<String>> filteredEmojis = {};
          if (searchQuery.isEmpty) {
            filteredEmojis = emojiCategories;
          } else {
            emojiCategories.forEach((category, emojis) {
              filteredEmojis[category] = emojis;
            });
          }

          final materialIcons = IconUtils.categoryIcons.entries.toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
            ),
            title: Text(l10n.selectIcon),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  TextField(
                    controller: emojiSearchController,
                    decoration: InputDecoration(
                      hintText: l10n.enterEmojiHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: emojiSearchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: l10n.clear,
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                emojiSearchController.clear();
                                setState(() => searchQuery = '');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          shapeTokens.inputRadius,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => searchQuery = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  if (emojiSearchController.text.isNotEmpty &&
                      emojiSearchController.text.characters.length == 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Text(
                            l10n.useAsIcon(emojiSearchController.text),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            child: Text(l10n.select),
                            onPressed: () {
                              setState(
                                () => _selectedIconName =
                                    emojiSearchController.text,
                              );
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          ...filteredEmojis.entries.map((entry) {
                            final category = entry.key;
                            final emojis = entry.value;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  title: Text(
                                    category,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  trailing: Icon(
                                    expandedTags[category] ?? false
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      expandedTags[category] =
                                          !(expandedTags[category] ?? false);
                                    });
                                  },
                                ),
                                if (expandedTags[category] ?? false)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                    ),
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: emojis.map((emoji) {
                                        final isSelected =
                                            _selectedIconName == emoji;
                                        return InkWell(
                                          onTap: () {
                                            setState(
                                              () => _selectedIconName = emoji,
                                            );
                                            Navigator.of(context).pop();
                                          },
                                          borderRadius: BorderRadius.circular(
                                            shapeTokens.cardRadius,
                                          ),
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                shapeTokens.cardRadius,
                                              ),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.outline,
                                                width: isSelected ? 2 : 1,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                emoji,
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                const Divider(),
                              ],
                            );
                          }),
                          ListTile(
                            title: Text(
                              l10n.systemIcons,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            trailing: Icon(
                              expandedTags[l10n.systemIcons] ?? false
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            onTap: () {
                              setState(() {
                                expandedTags[l10n.systemIcons] =
                                    !(expandedTags[l10n.systemIcons] ?? false);
                              });
                            },
                          ),
                          if (expandedTags[l10n.systemIcons] ?? false)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 8,
                                children: materialIcons.map((entry) {
                                  final iconName = entry.key;
                                  final iconData = entry.value;
                                  final isSelected =
                                      _selectedIconName == iconName;

                                  return SizedBox(
                                    width: 70,
                                    height: 70,
                                    child: InkWell(
                                      onTap: () {
                                        setState(
                                          () => _selectedIconName = iconName,
                                        );
                                        Navigator.of(context).pop();
                                      },
                                      borderRadius: BorderRadius.circular(
                                        shapeTokens.cardRadius,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                shapeTokens.cardRadius,
                                              ),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.outline,
                                              ),
                                            ),
                                            child: Icon(iconData),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            iconName,
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editCategory(BuildContext context, NoteTag category) {
    final nameController = TextEditingController(text: category.name);
    String? selectedIcon = category.iconName;
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
          ),
          title: Text(l10n.editTagTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n.tagNameLabel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      shapeTokens.inputRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(l10n.iconLabel),
                  IconButton(
                    icon: IconUtils.getCategoryIcon(selectedIcon),
                    tooltip: l10n.iconLabel,
                    onPressed: () async {
                      final BuildContext currentContext = dialogContext;
                      if (!context.mounted) return;
                      final icon = await showDialog<String>(
                        context: currentContext,
                        builder: (iconDialogContext) =>
                            _IconSelectorDialog(initialIcon: selectedIcon),
                      );
                      if (icon != null && mounted) {
                        setState(() => selectedIcon = icon);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isEmpty) return;

                final dbService = Provider.of<DatabaseService>(
                  context,
                  listen: false,
                );
                await dbService.updateTag(
                  category.id,
                  newName,
                  iconName: selectedIcon,
                );

                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryItem(NoteTag category, int index, int total) {
    final isDefault = category.isDefault;
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final bool isHiddenTag = category.id == DatabaseService.hiddenTagId;
    final String displayName = category.localizedName(l10n);

    return InkWell(
      onTap: isHiddenTag ? null : () => _editCategory(context, category),
      onLongPress: (isDefault || isHiddenTag)
          ? null
          : () => _deleteCategory(context, category),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
              ),
              child: Center(
                child: IconUtils.getCategoryIcon(category.iconName),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(
                              shapeTokens.buttonRadius,
                            ),
                          ),
                          child: Text(
                            isHiddenTag ? l10n.systemTag : l10n.defaultTag,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isHiddenTag
                        ? l10n.hiddenTagUsageHint
                        : (isDefault
                            ? l10n.systemDefaultTag
                            : l10n.tapToEditLongPressToDelete),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDefault || isHiddenTag
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: isHiddenTag ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isHiddenTag)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: l10n.edit,
                onPressed: () => _editCategory(context, category),
              ),
            if (!isDefault && !isHiddenTag)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: l10n.delete,
                onPressed: () => _deleteCategory(context, category),
              ),
          ],
        ),
      ),
    );
  }

  void _deleteCategory(BuildContext context, NoteTag category) {
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        ),
        title: Text(l10n.confirmDelete),
        content: Text(l10n.deleteTagConfirmation(category.localizedName(l10n))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true && mounted && context.mounted) {
        try {
          final dbService = context.read<DatabaseService>();
          await dbService.deleteTag(category.id);

          if (!mounted) return;
          if (context.mounted) {
            AppSnackBar.success(context, l10n.tagDeletedSuccess);
          }
        } catch (e) {
          if (!mounted) return;
          if (context.mounted) {
            AppSnackBar.error(context, l10n.deleteTagFailed(e.toString()));
          }
        }
      }
    });
  }
}

class _IconSelectorDialog extends StatefulWidget {
  final String? initialIcon;
  const _IconSelectorDialog({this.initialIcon});

  @override
  State<_IconSelectorDialog> createState() => _IconSelectorDialogState();
}

class _IconSelectorDialogState extends State<_IconSelectorDialog> {
  late String? _selectedIcon;
  final TextEditingController _emojiSearchController = TextEditingController();
  String _searchQuery = '';
  late Map<String, bool> expandedTags;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    expandedTags = {
      l10n.emotion: true,
      l10n.thinking: false,
      l10n.nature: false,
      l10n.mood: false,
      l10n.life: false,
      l10n.growth: false,
      l10n.reward: false,
      l10n.systemIcons: false,
    };
  }

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.initialIcon;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final emojiCategories = IconUtils.getCategorizedEmojis();
    final materialIcons = IconUtils.categoryIcons.entries.toList();
    Map<String, List<String>> filteredEmojis = {};
    if (_searchQuery.isEmpty) {
      filteredEmojis = emojiCategories;
    } else {
      emojiCategories.forEach((category, emojis) {
        filteredEmojis[category] = emojis;
      });
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
      ),
      title: Text(l10n.selectIcon),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            TextField(
              controller: _emojiSearchController,
              decoration: InputDecoration(
                hintText: l10n.enterEmojiHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _emojiSearchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: l10n.clear,
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _emojiSearchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
            const SizedBox(height: 8),
            if (_emojiSearchController.text.isNotEmpty &&
                _emojiSearchController.text.characters.length == 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Text(
                      l10n.useAsIcon(_emojiSearchController.text),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      child: Text(l10n.select),
                      onPressed: () {
                        Navigator.of(context).pop(_emojiSearchController.text);
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ...filteredEmojis.entries.map((entry) {
                      final category = entry.key;
                      final emojis = entry.value;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            title: Text(
                              category,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            trailing: Icon(
                              expandedTags[category] ?? false
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            onTap: () {
                              setState(() {
                                expandedTags[category] =
                                    !(expandedTags[category] ?? false);
                              });
                            },
                          ),
                          if (expandedTags[category] ?? false)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: emojis.map((emoji) {
                                  final isSelected = _selectedIcon == emoji;
                                  return InkWell(
                                    onTap: () {
                                      Navigator.of(context).pop(emoji);
                                    },
                                    borderRadius: BorderRadius.circular(
                                      shapeTokens.cardRadius,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          shapeTokens.cardRadius,
                                        ),
                                        border: Border.all(
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                        ),
                                      ),
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      );
                    }),
                    ListTile(
                      title: Text(
                        l10n.systemIcons,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      trailing: Icon(
                        expandedTags[l10n.systemIcons] ?? false
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onTap: () {
                        setState(() {
                          expandedTags[l10n.systemIcons] =
                              !(expandedTags[l10n.systemIcons] ?? false);
                        });
                      },
                    ),
                    if (expandedTags[l10n.systemIcons] ?? false)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 8,
                          children: materialIcons.map((entry) {
                            final iconName = entry.key;
                            final iconData = entry.value;
                            final isSelected = _selectedIcon == iconName;
                            return SizedBox(
                              width: 70,
                              height: 70,
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).pop(iconName);
                                },
                                borderRadius: BorderRadius.circular(
                                  shapeTokens.cardRadius,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          shapeTokens.cardRadius,
                                        ),
                                        border: Border.all(
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                        ),
                                      ),
                                      child: Icon(iconData),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
