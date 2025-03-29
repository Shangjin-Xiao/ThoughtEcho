import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';

class HitokotoSettingsPage extends StatefulWidget {
  const HitokotoSettingsPage({Key? key}) : super(key: key);

  @override
  State<HitokotoSettingsPage> createState() => _HitokotoSettingsPageState();
}

class _HitokotoSettingsPageState extends State<HitokotoSettingsPage> {
  late String _selectedType;
  final List<String> _selectedMultipleTypes = [];
  bool _isMultipleSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _selectedType = context.read<SettingsService>().appSettings.hitokotoType;
    // 如果当前选择的是多类型，解析它们
    if (_selectedType.contains(',')) {
      _isMultipleSelectionMode = true;
      _selectedMultipleTypes.addAll(_selectedType.split(','));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 创建一个新的Map，把抖机灵放在第一位
    final Map<String, String> reorderedTypes = {
      'l': '抖机灵 (随机)',
      ...Map.fromEntries(ApiService.hitokotoTypes.entries.where((e) => e.key != 'l')),
    };
    
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
                  '您可以自定义首页显示的"每日一言"类型。\n选择"抖机灵"将随机显示所有类型，或者您可以开启多选从其他类型中随机抽取。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('开启多选模式'),
                  subtitle: const Text('从多个类型中随机抽取（选择抖机灵时无法多选）'),
                  value: _isMultipleSelectionMode && _selectedType != 'l',
                  onChanged: (value) {
                    if (_selectedType == 'l') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('选择"抖机灵"时无法开启多选')),
                      );
                      return;
                    }
                    setState(() {
                      _isMultipleSelectionMode = value;
                      if (!value) {
                        // 如果关闭多选，则使用第一个选中的类型或默认值
                        _selectedType = _selectedMultipleTypes.isNotEmpty 
                            ? _selectedMultipleTypes.first 
                            : 'l';
                        _selectedMultipleTypes.clear();
                        context.read<SettingsService>().updateHitokotoType(_selectedType);
                      } else {
                        // 如果开启多选，初始选中当前类型
                        _selectedMultipleTypes.clear();
                        _selectedMultipleTypes.add(_selectedType);
                        context.read<SettingsService>().updateHitokotoType(_selectedType);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(),
          if (_isMultipleSelectionMode)
            ...reorderedTypes.entries.where((e) => e.key != 'l').map((entry) {
              return CheckboxListTile(
                title: Text(entry.value),
                subtitle: Text('类型代码: ${entry.key}'),
                value: _selectedMultipleTypes.contains(entry.key),
                onChanged: (bool? value) {
                  if (value == true) {
                    setState(() {
                      _selectedMultipleTypes.add(entry.key);
                      _selectedType = _selectedMultipleTypes.join(',');
                    });
                  } else {
                    setState(() {
                      _selectedMultipleTypes.remove(entry.key);
                      // 至少要选择一个类型
                      if (_selectedMultipleTypes.isEmpty) {
                        _selectedMultipleTypes.add('a');
                      }
                      _selectedType = _selectedMultipleTypes.join(',');
                    });
                  }
                  context.read<SettingsService>().updateHitokotoType(_selectedType);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('设置已保存')),
                  );
                },
              );
            }).toList()
          else
            ...reorderedTypes.entries.map((entry) {
              return RadioListTile<String>(
                title: Text(entry.value),
                subtitle: Text('类型代码: ${entry.key}'),
                value: entry.key,
                groupValue: _selectedType,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedType = value;
                      if (value == 'l') {
                        // 选择抖机灵时，禁用多选
                        _isMultipleSelectionMode = false;
                        _selectedMultipleTypes.clear();
                      }
                    });
                    context.read<SettingsService>().updateHitokotoType(value);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('设置已保存')),
                    );
                  }
                },
              );
            }).toList(),
        ],
      ),
    );
  }
} 