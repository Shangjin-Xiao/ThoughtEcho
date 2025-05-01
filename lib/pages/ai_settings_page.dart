import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../models/ai_settings.dart';
import '../services/secure_storage_service.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _maxTokensController = TextEditingController();
  String? _hostOverride;
  final _hostOverrideController = TextEditingController();
  final List<Map<String, String>> aiPresets = [
    {
      'name': 'OpenAI',
      'apiUrl': 'https://api.openai.com/v1/chat/completions',
      'model': 'gpt-3.5-turbo',
    },
    {
      'name': 'OpenRouter',
      'apiUrl': 'https://openrouter.ai/api/v1/chat/completions',
      'model': 'openai/gpt-3.5-turbo',
    },
    {
      'name': '硅基流动',
      'apiUrl': 'https://api.g8way.io/v1/chat/completions',
      'model': 'gpt-3.5-turbo',
    },
    {
      'name': 'DeepSeek',
      'apiUrl': 'https://api.deepseek.com/v1/chat/completions',
      'model': 'deepseek-chat',
    },
    {
      'name': 'Anthropic (Claude)',
      'apiUrl': 'https://api.anthropic.com/v1/messages',
      'model': 'claude-3-opus-20240229',
    },
    {
      'name': 'Ollama',
      'apiUrl': 'http://localhost:11434/v1/chat/completions',
      'model': 'llama2',
    },
    {
      'name': 'LMStudio',
      'apiUrl': 'http://localhost:1234/v1/chat/completions',
      'model': 'llama2',
    },
    {
      'name': 'OpenAPI兼容',
      'apiUrl': 'http://your-openapi-server/v1/chat/completions',
      'model': 'gpt-3.5-turbo',
    },
  ];
  String? _selectedPreset;

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
    _temperatureController.dispose();
    _maxTokensController.dispose();
    _hostOverrideController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      // 从安全存储获取API密钥
      final secureStorage = SecureStorageService();
      final secureApiKey = await secureStorage.getApiKey();
      
      final settings = Provider.of<SettingsService>(context, listen: false);
      final aiSettings = settings.aiSettings;
      
      setState(() {
        _modelController.text = aiSettings.model;
        _apiUrlController.text = aiSettings.apiUrl;
        
        // 优先使用安全存储的API密钥
        _apiKeyController.text = secureApiKey ?? aiSettings.apiKey;
        _temperatureController.text = aiSettings.temperature.toString();
        _maxTokensController.text = aiSettings.maxTokens.toString();
        _hostOverride = aiSettings.hostOverride;
        _hostOverrideController.text = _hostOverride ?? '';
        try {
          _selectedPreset = aiPresets.firstWhere((p) => p['model'] == aiSettings.model)['name'];
        } catch (_) {
          _selectedPreset = null;
        }
      });
    } catch (e) {
      debugPrint('加载AI设置失败: $e');
    }
  }

  Future<void> _saveSettings() async {
    final service = Provider.of<SettingsService>(context, listen: false);
    
    try {
      // 获取当前设置中的值
      final double temperature = double.tryParse(_temperatureController.text) ?? 0.7;
      final int maxTokens = int.tryParse(_maxTokensController.text) ?? 1000;
      
      // 使用安全存储保存API密钥
      final secureStorage = SecureStorageService();
      await secureStorage.saveApiKey(_apiKeyController.text);
      
      // 保存其他设置到普通存储
      await service.updateAISettings(
        AISettings(
          model: _modelController.text,
          apiUrl: _apiUrlController.text,
          apiKey: '', // 不再将API密钥保存到普通设置中
          temperature: temperature,
          maxTokens: maxTokens,
          hostOverride: _hostOverride,
        ),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存设置失败: $e')),
        );
      }
    }
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
            DropdownButtonFormField<String>(
              value: _selectedPreset,
              items: aiPresets.map((preset) {
                return DropdownMenuItem(
                  value: preset['name'],
                  child: Text(preset['name']!),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPreset = value;
                  final preset = aiPresets.firstWhere((p) => p['name'] == value);
                  _apiUrlController.text = preset['apiUrl']!;
                  _modelController.text = preset['model']!;
                });
              },
              decoration: const InputDecoration(
                labelText: '快速选择AI服务预设',
                border: OutlineInputBorder(),
              ),
            ),
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
            const SizedBox(height: 16),
            TextField(
              controller: _temperatureController,
              decoration: const InputDecoration(
                labelText: '温度',
                hintText: '例如：0.7',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxTokensController,
              decoration: const InputDecoration(
                labelText: '最大令牌数',
                hintText: '例如：1000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostOverrideController,
              decoration: const InputDecoration(
                labelText: '主机覆盖',
                hintText: '例如：http://localhost:8080',
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
              onPressed: _saveSettings,
              child: const Text('保存 AI 设置'),
            ),
          ],
        ),
      ),
    );
  }
}