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

  @override
  void initState() {
    super.initState();
    _selectedType = context.read<SettingsService>().appSettings.hitokotoType;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('一言设置'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '选择一言类型',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(),
          ...ApiService.hitokotoTypes.entries.map((entry) {
            return RadioListTile<String>(
              title: Text(entry.value),
              subtitle: Text('类型代码: ${entry.key}'),
              value: entry.key,
              groupValue: _selectedType,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
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