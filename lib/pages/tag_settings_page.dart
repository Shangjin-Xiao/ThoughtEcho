import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/note_category.dart'; // 替换 import NoteTag 为 NoteCategory
import '../utils/icon_utils.dart';

class TagSettingsPage extends StatefulWidget {
  const TagSettingsPage({Key? key}) : super(key: key);

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '标签管理',
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
                    controller: _tagController,
                    decoration: const InputDecoration(
                      labelText: '新标签名称',
                      hintText: '输入标签名称',
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
                          if (_tagController.text.isEmpty) return;
                          
                          setState(() => _isLoading = true);
                          try {
                            await context
                                .read<DatabaseService>()
                                .addCategory(_tagController.text, iconName: _selectedIconName); // 替换 addTag 为 addCategory

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('标签添加成功')),
                            );
                            _tagController.clear();
                            setState(() {
                              _selectedIconName = null;
                            });
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('添加标签失败：$e')),
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
            StreamBuilder<List<NoteCategory>>( // 替换 StreamBuilder<List<NoteTag>> 为 StreamBuilder<List<NoteCategory>>
              stream: context.read<DatabaseService>().watchCategories(), // 替换 watchTags 为 watchCategories
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text('加载标签失败: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text('暂无标签'),
                  );
                }

                final List<NoteCategory> tags = snapshot.data as List<NoteCategory>; // 添加类型转换
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tags.length,
                  itemBuilder: (context, index) {
                    final NoteCategory tag = tags[index]; // 替换 NoteTag 为 NoteCategory
                    return ListTile(
                      leading: Icon(IconUtils.getIconData(tag.iconName)),
                      title: Text(tag.name),
                      trailing: tag.isDefault ? null : IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('确认删除'),
                              content: Text('确定要删除标签"${tag.name}"吗？'),
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
                                  .deleteCategory(tag.id); // 替换 deleteTag 为 deleteCategory

                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('标签删除成功')),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('删除标签失败：$e')),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择图标'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: IconUtils.getAllIcons().length,
            itemBuilder: (context, index) {
              final iconEntry = IconUtils.getAllIcons()[index];
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedIconName = iconEntry.key;
                  });
                  Navigator.of(context).pop();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _selectedIconName == iconEntry.key
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconEntry.value),
                      const SizedBox(height: 4),
                      Text(
                        iconEntry.key,
                        style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}