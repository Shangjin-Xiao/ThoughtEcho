import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/note_category.dart';
import '../utils/icon_utils.dart';

class CategorySettingsPage extends StatefulWidget {
  const CategorySettingsPage({super.key});

  @override
  State<CategorySettingsPage> createState() => _CategorySettingsPageState();
}

class _CategorySettingsPageState extends State<CategorySettingsPage> {
  final _categoryController = TextEditingController();
  bool _isLoading = false;
  String? _selectedIconName;

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '分类管理',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: '新分类名称',
                      hintText: '输入分类名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 添加图标选择按钮
                IconButton(
                  onPressed: () {
                    _showIconSelector(context);
                  },
                  icon: _selectedIconName != null
                      ? Icon(IconUtils.getIconData(_selectedIconName))
                      : const Icon(Icons.add_circle_outline),
                  tooltip: '选择图标',
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (_categoryController.text.isEmpty) return;
                          
                          setState(() => _isLoading = true);
                          try {
                            await context
                                .read<DatabaseService>()
                                .addCategory(_categoryController.text, iconName: _selectedIconName);
                            
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('分类添加成功')),
                            );
                            _categoryController.clear();
                            setState(() {
                              _selectedIconName = null;
                            });
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('添加分类失败：$e')),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _isLoading = false);
                            }
                          }
                        },
                  child: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<NoteCategory>>(
              stream: context.read<DatabaseService>().watchCategories(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text('加载分类失败: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text('暂无分类'),
                  );
                }

                final categories = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return ListTile(
                      leading: Icon(IconUtils.getIconData(category.iconName)),
                      title: Text(category.name),
                      trailing: category.isDefault ? null : IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('确认删除'),
                              content: Text('确定要删除分类"${category.name}"吗？'),
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
                          );

                          if (confirmed == true && mounted) {
                            try {
                              await context
                                  .read<DatabaseService>()
                                  .deleteCategory(category.id);
                              
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('分类删除成功')),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('删除分类失败：$e')),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
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
                  if (emojiSearchController.text.isNotEmpty && emojiSearchController.text.characters.length == 1)
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
                              setState(() => _selectedIconName = emojiSearchController.text);
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
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  trailing: Icon(
                                    expandedCategories[category] ?? false
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      expandedCategories[category] = !(expandedCategories[category] ?? false);
                                    });
                                  },
                                ),
                                
                                // 分类内的emoji
                                if (expandedCategories[category] ?? false)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: emojis.map((emoji) {
                                        final isSelected = _selectedIconName == emoji;
                                        return InkWell(
                                          onTap: () {
                                            setState(() => _selectedIconName = emoji);
                                            Navigator.of(context).pop();
                                          },
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Theme.of(context).colorScheme.primaryContainer
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Theme.of(context).dividerColor,
                                                width: isSelected ? 2 : 1,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                emoji,
                                                style: const TextStyle(fontSize: 24),
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
                                expandedCategories['系统图标'] = !(expandedCategories['系统图标'] ?? false);
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
                                  final isSelected = _selectedIconName == iconName;
                                  
                                  return SizedBox(
                                    width: 70,
                                    height: 70,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() => _selectedIconName = iconName);
                                        Navigator.of(context).pop();
                                      },
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Theme.of(context).colorScheme.primaryContainer
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Colors.transparent,
                                              ),
                                            ),
                                            child: Icon(iconData),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            iconName,
                                            style: const TextStyle(fontSize: 10),
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
        }
      ),
    );
  }
}