import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../models/note_category.dart';
import '../models/ai_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _categoryController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = context.read<SettingsService>().aiSettings;
    setState(() {
      _apiUrlController.text = settings.apiUrl;
      _apiKeyController.text = settings.apiKey;
      _modelController.text = settings.model;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'AI 设置'),
              Tab(text: '笔记设置'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildAISettings(),
            _buildNoteSettings(),
          ],
        ),
      ),
    );
  }

  Widget _buildAISettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'API 设置',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiUrlController,
            decoration: const InputDecoration(
              labelText: 'API URL',
              hintText: '例如：https://api.openai.com/v1/chat/completions',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: '输入你的 API Key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: '模型',
              hintText: '例如：gpt-3.5-turbo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              final settings = AISettings(
                apiUrl: _apiUrlController.text,
                apiKey: _apiKeyController.text,
                model: _modelController.text,
              );
              context.read<SettingsService>().updateAISettings(settings);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('设置已保存')),
              );
            },
            child: const Text('保存 AI 设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteSettings() {
    return SingleChildScrollView(
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
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final categories = snapshot.data!;
              if (categories.isEmpty) {
                return const Center(
                  child: Text('暂无分类'),
                );
              }

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
    );
  }
}