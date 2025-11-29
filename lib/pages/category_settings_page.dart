import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/note_category.dart';
import '../utils/icon_utils.dart';
import '../theme/app_theme.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class CategorySettingsPage extends StatefulWidget {
  const CategorySettingsPage({super.key});

  @override
  State<CategorySettingsPage> createState() => _CategorySettingsPageState();
}

class _CategorySettingsPageState extends State<CategorySettingsPage> {
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tagManagement)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.tagManagement,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // 输入与添加区域卡片化
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
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
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: l10n.selectIcon,
                        child: InkWell(
                          onTap: () => _showIconSelector(context),
                          borderRadius:
                              BorderRadius.circular(AppTheme.cardRadius),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppTheme.cardRadius,
                              ),
                            ),
                            child: _selectedIconName != null
                                ? (IconUtils.isEmoji(_selectedIconName)
                                    ? Text(
                                        IconUtils.getDisplayIcon(
                                          _selectedIconName!,
                                        ),
                                        style: const TextStyle(fontSize: 20),
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
                      ElevatedButton.icon(
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(_isLoading ? l10n.adding : l10n.add),
                        onPressed: _isLoading
                            ? null
                            : () async {
                                final text = _categoryController.text.trim();
                                if (text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(l10n.pleaseEnterTagName),
                                        duration: AppConstants
                                            .snackBarDurationNormal),
                                  );
                                  return;
                                }
                                final messenger = ScaffoldMessenger.of(context);
                                setState(() => _isLoading = true);
                                try {
                                  final db = context.read<DatabaseService>();
                                  await db.addCategory(
                                    text,
                                    iconName: _selectedIconName,
                                  );
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                          content: Text(l10n.tagAddedSuccess),
                                          duration: AppConstants
                                              .snackBarDurationNormal),
                                    );
                                    _categoryController.clear();
                                    setState(() => _selectedIconName = null);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                          content: Text(l10n.addTagFailed(e.toString())),
                                          duration: AppConstants
                                              .snackBarDurationError),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
            const SizedBox(height: 16),
            StreamBuilder<List<NoteCategory>>(
              stream: context.read<DatabaseService>().watchCategories(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text(l10n.loadTagsFailed(snapshot.error.toString())));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text(l10n.noTags));
                }

                final categories = snapshot.data!;
                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
                          category, index, categories.length);
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
    Map<String, bool> expandedCategories = {
      '情感': true,
      '思考': false,
      '自然': false,
      '心情': false,
      '生活': false,
      '成长': false,
      '奖励': false,
      '系统图标': false,
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // 获取emoji分类
          final emojiCategories = IconUtils.getCategorizedEmojis();

          // 过滤emoji
          Map<String, List<String>> filteredEmojis = {};
          if (searchQuery.isEmpty) {
            filteredEmojis = emojiCategories;
          } else {
            // 简单过滤，实际应用中可能需要更复杂的过滤逻辑
            emojiCategories.forEach((category, emojis) {
              filteredEmojis[category] = emojis;
            });
          }

          // Material图标列表，仅在搜索为空时显示
          final materialIcons = IconUtils.categoryIcons.entries.toList();

          return AlertDialog(
            title: const Text('选择图标'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  // 搜索框和自定义emoji输入
                  TextField(
                    controller: emojiSearchController,
                    decoration: InputDecoration(
                      hintText: '直接输入表情符号...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: emojiSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                emojiSearchController.clear();
                                setState(() => searchQuery = '');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() => searchQuery = value);
                    },
                  ),
                  const SizedBox(height: 8),

                  // 显示用户输入的emoji (如果是单个字符)
                  if (emojiSearchController.text.isNotEmpty &&
                      emojiSearchController.text.characters.length == 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Text(
                            '使用 "${emojiSearchController.text}" 作为图标',
                            style: const TextStyle(color: Colors.blue),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            child: const Text('选择'),
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

                  // emoji分类和系统图标列表
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // emoji分类列表
                          ...filteredEmojis.entries.map((entry) {
                            final category = entry.key;
                            final emojis = entry.value;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 分类标题
                                ListTile(
                                  title: Text(
                                    category,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  trailing: Icon(
                                    expandedCategories[category] ?? false
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      expandedCategories[category] =
                                          !(expandedCategories[category] ??
                                              false);
                                    });
                                  },
                                ),

                                // 分类内的emoji
                                if (expandedCategories[category] ?? false)
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
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Theme.of(
                                                      context,
                                                    )
                                                      .colorScheme
                                                      .primaryContainer
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                AppTheme.cardRadius,
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

                          // 系统图标部分
                          ListTile(
                            title: const Text(
                              '系统图标',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            trailing: Icon(
                              expandedCategories['系统图标'] ?? false
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            onTap: () {
                              setState(() {
                                expandedCategories['系统图标'] =
                                    !(expandedCategories['系统图标'] ?? false);
                              });
                            },
                          ),

                          if (expandedCategories['系统图标'] ?? false)
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
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Theme.of(
                                                      context,
                                                    )
                                                      .colorScheme
                                                      .primaryContainer
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                AppTheme.cardRadius,
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
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editCategory(BuildContext context, NoteCategory category) {
    final nameController = TextEditingController(text: category.name);
    String? selectedIcon = category.iconName;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          // 修正：此处应为“编辑分类”而非“编辑标签”
          title: const Text('编辑标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                // 改为“标签名称”以匹配统一用语
                decoration: const InputDecoration(labelText: '标签名称'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('图标：'),
                  IconButton(
                    icon: IconUtils.getCategoryIcon(selectedIcon),
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
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isEmpty) return;

                // 获取必要的context相关对象
                final dbService = Provider.of<DatabaseService>(
                  context,
                  listen: false,
                );
                await dbService.updateCategory(
                  category.id,
                  newName,
                  iconName: selectedIcon,
                );

                // 修复内存泄露：在异步操作后检查mounted状态
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryItem(NoteCategory category, int index, int total) {
    final isDefault = category.isDefault;
    return InkWell(
      onTap: () => _editCategory(context, category),
      onLongPress: isDefault
          ? null
          : () => _deleteCategory(context, category), // 修复：默认标签不能长按删除
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
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
                          category.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
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
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '默认',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDefault ? '系统默认标签' : '点击编辑，长按删除',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDefault
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: '编辑',
              onPressed: () => _editCategory(context, category),
            ),
            if (!isDefault)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: '删除',
                onPressed: () => _deleteCategory(context, category),
              ),
          ],
        ),
      ),
    );
  }

  void _deleteCategory(BuildContext context, NoteCategory category) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除标签"${category.name}"吗？相关联的笔记将保留，但不再关联此标签。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true && mounted && context.mounted) {
        try {
          final dbService = context.read<DatabaseService>();
          await dbService.deleteCategory(category.id);

          // 修复内存泄露：在异步操作后检查mounted状态
          if (!mounted) return;
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(
                content: Text('标签删除成功'),
                duration: AppConstants.snackBarDurationNormal));
          }
        } catch (e) {
          // 修复内存泄露：在异步操作后检查mounted状态
          if (!mounted) return;
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(
                content: Text('删除标签失败：$e'),
                duration: AppConstants.snackBarDurationError));
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
  Map<String, bool> expandedCategories = {
    '情感': true,
    '思考': false,
    '自然': false,
    '心情': false,
    '生活': false,
    '成长': false,
    '奖励': false,
    '系统图标': false,
  };

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.initialIcon;
  }

  @override
  Widget build(BuildContext context) {
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
      title: const Text('选择图标'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            TextField(
              controller: _emojiSearchController,
              decoration: InputDecoration(
                hintText: '直接输入表情符号...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _emojiSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _emojiSearchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
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
                      '使用 "${_emojiSearchController.text}" 作为图标',
                      style: const TextStyle(color: Colors.blue),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      child: const Text('选择'),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: Icon(
                              expandedCategories[category] ?? false
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            onTap: () {
                              setState(() {
                                expandedCategories[category] =
                                    !(expandedCategories[category] ?? false);
                              });
                            },
                          ),
                          if (expandedCategories[category] ?? false)
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
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          8,
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
                                        style: const TextStyle(
                                          fontSize: 24,
                                        ),
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
                      title: const Text(
                        '系统图标',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: Icon(
                        expandedCategories['系统图标'] ?? false
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onTap: () {
                        setState(() {
                          expandedCategories['系统图标'] =
                              !(expandedCategories['系统图标'] ?? false);
                        });
                      },
                    ),
                    if (expandedCategories['系统图标'] ?? false)
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
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          8,
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
          child: const Text('取消'),
        ),
      ],
    );
  }
}
