import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../models/note_category.dart';

class CategorySettingsPage extends StatefulWidget {
  const CategorySettingsPage({Key? key}) : super(key: key);

  @override
  State<CategorySettingsPage> createState() => _CategorySettingsPageState();
}

class _CategorySettingsPageState extends State<CategorySettingsPage> {
  final _categoryController = TextEditingController();
  bool _isLoading = false;

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
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (_categoryController.text.isEmpty) return;
                          
                          setState(() => _isLoading = true);
                          try {
                            await context
                                .read<DatabaseService>()
                                .addCategory(_categoryController.text);
                            
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('分类添加成功')),
                            );
                            _categoryController.clear();
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
}