import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../models/ai_settings.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 设置'),
      ),
      body: SingleChildScrollView(
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

            // Add AI Risk Warning
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                '请注意：AI 生成的内容可能不完全准确或可靠，请谨慎使用并自行判断。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ),
            // End of AI Risk Warning

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
      ),
    );
  }
}