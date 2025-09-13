import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/note_category.dart'; // 替换 import NoteTag 为 NoteCategory
import '../utils/icon_utils.dart';
import '../theme/app_theme.dart';

class TagSettingsPage extends StatefulWidget {
  const TagSettingsPage({super.key});

  @override
  State<TagSettingsPage> createState() => _TagSettingsPageState();
}

class _TagSettingsPageState extends State<TagSettingsPage> {
  final _tagController = TextEditingController();
  bool _isLoading = false;
  String? _selectedIconName;

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('标签管理'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和描述卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withAlpha(200),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withAlpha(50),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.label_rounded,
                          color: colorScheme.onPrimary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '标签管理',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '创建和管理您的个人标签体系',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer
                                    .withAlpha(180),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 添加新标签卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withAlpha(50),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '添加新标签',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          decoration: InputDecoration(
                            labelText: '标签名称',
                            hintText: '请输入标签名称',
                            prefixIcon: const Icon(Icons.edit_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: colorScheme.surface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 图标选择按钮
                      Container(
                        decoration: BoxDecoration(
                          color: _selectedIconName != null
                              ? colorScheme.primary.withAlpha(20)
                              : colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedIconName != null
                                ? colorScheme.primary
                                : colorScheme.outline.withAlpha(50),
                          ),
                        ),
                        child: IconButton(
                          onPressed: () => _showIconSelector(context),
                          icon: _selectedIconName != null
                              ? (IconUtils.isEmoji(_selectedIconName!)
                                  ? Text(
                                      IconUtils.getDisplayIcon(
                                          _selectedIconName!),
                                      style: const TextStyle(fontSize: 20),
                                    )
                                  : Icon(
                                      IconUtils.getIconData(_selectedIconName!),
                                      color: colorScheme.primary,
                                    ))
                              : Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          tooltip: '选择图标',
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 添加按钮
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.primary,
                              colorScheme.primary.withAlpha(200),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  if (_tagController.text.isEmpty) return;

                                  // 在异步操作前获取上下文的参数和服务
                                  final scaffoldMessenger =
                                      ScaffoldMessenger.of(
                                    context,
                                  );
                                  final dbService =
                                      context.read<DatabaseService>();

                                  setState(() => _isLoading = true);
                                  try {
                                    await dbService.addCategory(
                                      _tagController.text,
                                      iconName: _selectedIconName,
                                    ); // 替换 addTag 为 addCategory

                                    if (!mounted) return;
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(content: Text('标签添加成功')),
                                    );
                                    _tagController.clear();
                                    setState(() {
                                      _selectedIconName = null;
                                    });
                                  } catch (e) {
                                    if (!mounted) return;
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(content: Text('添加标签失败：$e')),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : Text(
                                  '添加',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 现有标签列表
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withAlpha(50),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '我的标签',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  StreamBuilder<List<NoteCategory>>(
                    // 替换 StreamBuilder<List<NoteTag>> 为 StreamBuilder<List<NoteCategory>>
                    stream: context
                        .read<DatabaseService>()
                        .watchCategories(), // 替换 watchTags 为 watchCategories
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '加载标签中...',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Container(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 48,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '加载标签失败',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${snapshot.error}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.label_off_outlined,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '暂无标签',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '创建您的第一个标签来开始整理思想',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final List<NoteCategory> tags =
                          snapshot.data as List<NoteCategory>; // 添加类型转换
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: tags.length,
                        separatorBuilder: (context, index) => Divider(
                          color: colorScheme.outline.withAlpha(30),
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                        ),
                        itemBuilder: (context, index) {
                          final NoteCategory tag =
                              tags[index]; // 替换 NoteTag 为 NoteCategory
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: tag.isDefault
                                  ? colorScheme.primaryContainer.withAlpha(50)
                                  : null,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: tag.isDefault
                                      ? colorScheme.primary.withAlpha(20)
                                      : colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: tag.isDefault
                                        ? colorScheme.primary.withAlpha(50)
                                        : colorScheme.outline.withAlpha(30),
                                  ),
                                ),
                                child: Center(
                                  child: IconUtils.isEmoji(tag.iconName)
                                      ? Text(
                                          IconUtils.getDisplayIcon(
                                              tag.iconName),
                                          style: const TextStyle(fontSize: 20),
                                        )
                                      : Icon(
                                          IconUtils.getIconData(tag.iconName),
                                          color: tag.isDefault
                                              ? colorScheme.primary
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                ),
                              ),
                              title: Text(
                                tag.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: tag.isDefault
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: tag.isDefault
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                ),
                              ),
                              subtitle: tag.isDefault
                                  ? Text(
                                      '系统默认标签',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            colorScheme.primary.withAlpha(150),
                                      ),
                                    )
                                  : null,
                              trailing: tag.isDefault
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            colorScheme.primary.withAlpha(20),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color:
                                              colorScheme.primary.withAlpha(50),
                                        ),
                                      ),
                                      child: Text(
                                        '默认',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: colorScheme.error,
                                      ),
                                      onPressed: () async {
                                        // 在异步操作前获取上下文的参数和服务
                                        final scaffoldMessenger =
                                            ScaffoldMessenger.of(context);
                                        final dbService =
                                            context.read<DatabaseService>();

                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            title: Row(
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: colorScheme.error,
                                                ),
                                                const SizedBox(width: 8),
                                                const Text('确认删除'),
                                              ],
                                            ),
                                            content: Text(
                                              '确定要删除标签"${tag.name}"吗？\n\n删除后，使用此标签的笔记将不再显示该标签。',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: Text(
                                                  '取消',
                                                  style: TextStyle(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      colorScheme.error,
                                                ),
                                                child: const Text('删除'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirmed == true) {
                                          try {
                                            await dbService
                                                .deleteCategory(tag.id);

                                            if (!mounted) return;
                                            scaffoldMessenger.showSnackBar(
                                              SnackBar(
                                                content: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .check_circle_outline_rounded,
                                                      color: colorScheme
                                                          .onInverseSurface,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Text('标签删除成功'),
                                                  ],
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            if (!mounted) return;
                                            scaffoldMessenger.showSnackBar(
                                              SnackBar(
                                                content: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .error_outline_rounded,
                                                      color: colorScheme
                                                          .onErrorContainer,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text('删除标签失败：$e'),
                                                  ],
                                                ),
                                                backgroundColor:
                                                    colorScheme.errorContainer,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
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

                                Divider(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
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
}
