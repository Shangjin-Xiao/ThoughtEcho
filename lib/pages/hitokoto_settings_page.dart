import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';

class HitokotoSettingsPage extends StatefulWidget {
  const HitokotoSettingsPage({super.key});

  @override
  State<HitokotoSettingsPage> createState() => _HitokotoSettingsPageState();
}

class _HitokotoSettingsPageState extends State<HitokotoSettingsPage> {
  late String _selectedType;
  final List<String> _selectedTypes = [];

  @override
  void initState() {
    super.initState();
    _selectedType = context.read<SettingsService>().appSettings.hitokotoType;
    // 解析当前选择的类型
    if (_selectedType.contains(',')) {
      _selectedTypes.addAll(_selectedType.split(','));
    } else {
      _selectedTypes.add(_selectedType);
    }
  }

  // 保存选择的类型
  void _saveSelectedTypes() {
    // 确保至少选择一种类型
    if (_selectedTypes.isEmpty) {
      _selectedTypes.add('a');
    }
    _selectedType = _selectedTypes.join(',');
    context.read<SettingsService>().updateHitokotoType(_selectedType);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日一言设置'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日一言类型设置',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '您可以选择一个或多个"每日一言"类型，程序将从您选择的类型中随机抽取内容展示。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          const Divider(),
          ...ApiService.hitokotoTypes.entries.map((entry) {
            return CheckboxListTile(
              title: Text(entry.value),
              subtitle: Text('类型代码: \\${entry.key}'),
              value: _selectedTypes.contains(entry.key),
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    _selectedTypes.add(entry.key);
                  } else {
                    _selectedTypes.remove(entry.key);
                  }
                });
                _saveSelectedTypes();
              },
            );
          }),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedTypes.clear();
                      for (final key in ApiService.hitokotoTypes.keys) {
                        _selectedTypes.add(key);
                      }
                    });
                    _saveSelectedTypes();
                  },
                  child: const Text('全选'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedTypes.clear();
                      _selectedTypes.add('a'); // 至少选一个
                    });
                    _saveSelectedTypes();
                  },
                  child: const Text('清除全部'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}