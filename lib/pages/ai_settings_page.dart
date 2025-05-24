import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/ai_service.dart';
import '../models/ai_settings.dart';
import '../services/secure_storage_service.dart';
import '../utils/color_utils.dart'; // Import color_utils.dart

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

  // Updated presets list based on verification
  final List<Map<String, String>> aiPresets = [
    {
      'name': 'OpenAI',
      'apiUrl': 'https://api.openai.com/v1/chat/completions',
      'model': 'gpt-4o', // Confirmed latest
    },
    {
      'name': 'OpenRouter', // Assumed to support latest OpenAI via identifier
      'apiUrl': 'https://openrouter.ai/api/v1/chat/completions',
      'model': 'openai/gpt-4o',
    },
    {
      'name': '硅基流动', // Model left empty as GPT-4o support is unconfirmed
      'apiUrl': 'https://api.siliconflow.cn/v1/chat/completions',
      'model': '', // Needs user input based on their Silicon Flow plan/docs
    },
    {
      'name': 'DeepSeek',
      'apiUrl': 'https://api.deepseek.com/v1/chat/completions',
      'model': 'deepseek-chat', // Keep their recommended model
    },
    {
      'name': 'Anthropic (Claude)', // Updated to Claude 3.7 Sonnet latest alias
      'apiUrl': 'https://api.anthropic.com/v1/messages',
      'model': 'claude-3.7-sonnet-latest',
    },
    {
      'name': 'Ollama', // Empty model name
      'apiUrl': 'http://localhost:11434/v1/chat/completions',
      'model': '', // Needs user input
    },
    {
      'name': 'LMStudio', // Empty model name
      'apiUrl': 'http://localhost:1234/v1/chat/completions',
      'model': '', // Needs user input
    },
    {
      'name': 'OpenAPI兼容', // Empty model name
      'apiUrl': 'http://your-openapi-server/v1/chat/completions',
      'model': '', // Needs user input
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
      final secureStorage = SecureStorageService();
      final secureApiKey = await secureStorage.getApiKey();

      // 在异步操作后检查 mounted 状态
      if (!mounted) return;

      final settings = Provider.of<SettingsService>(context, listen: false);
      final aiSettings = settings.aiSettings;

      debugPrint('=== AI设置页面加载调试 ===');
      debugPrint('安全存储中的API密钥: ${secureApiKey != null ? "存在 (长度: ${secureApiKey.length})" : "不存在"}');
      debugPrint('设置中的AI配置:');
      debugPrint('  API URL: ${aiSettings.apiUrl}');
      debugPrint('  Model: ${aiSettings.model}');
      debugPrint('  API Key: ${aiSettings.apiKey.isNotEmpty ? "存在 (长度: ${aiSettings.apiKey.length})" : "不存在"}');
      debugPrint('  Temperature: ${aiSettings.temperature}');
      debugPrint('  Max Tokens: ${aiSettings.maxTokens}');
      debugPrint('  Host Override: ${aiSettings.hostOverride}');

      setState(() {
        _modelController.text = aiSettings.model;
        _apiUrlController.text = aiSettings.apiUrl;
        _apiKeyController.text = secureApiKey ?? aiSettings.apiKey; // Use secure key first
        _temperatureController.text = aiSettings.temperature.toString();
        _maxTokensController.text = aiSettings.maxTokens.toString();
        _hostOverride = aiSettings.hostOverride;
        _hostOverrideController.text = _hostOverride ?? '';
        try {
          // Try to match preset based on API URL and potentially model if not empty
           _selectedPreset = aiPresets.firstWhere(
                (p) => p['apiUrl'] == aiSettings.apiUrl && (p['model'] == aiSettings.model || (p['model'] == '' && aiSettings.model.isNotEmpty)) // Match if preset model is empty and loaded model is not
            )['name'];
           // Refined matching: Match if URLs and models match OR if preset URL matches, preset model is empty, and loaded model has a value (custom model for that preset URL)
        } catch (_) {
          _selectedPreset = null; // No matching preset found (custom config)
        }
      });
    } catch (e) {
      debugPrint('加载AI设置失败: $e');
      // 在异步操作后检查 mounted 状态
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载AI设置失败: $e')),
      );
    }
  }

 Future<void> _saveSettings() async {
    // 异步操作开始前，如果 context 可能在操作过程中变得无效，则先获取需要的服务实例
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context); // 获取 ScaffoldMessenger

    // Validate numeric fields before parsing
    final tempText = _temperatureController.text;
    final maxTokensText = _maxTokensController.text;
    double? temperature = double.tryParse(tempText);
    int? maxTokens = int.tryParse(maxTokensText);

    // Basic validation feedback
    if (tempText.isNotEmpty && temperature == null) {
       // 检查 mounted 状态
       if (!mounted) return;
       scaffoldMessenger.showSnackBar(const SnackBar(content: Text('温度值无效，请输入数字。')));
       return; // Stop saving
    }
     if (maxTokensText.isNotEmpty && maxTokens == null) {
       // 检查 mounted 状态
       if (!mounted) return;
       scaffoldMessenger.showSnackBar(const SnackBar(content: Text('最大令牌数无效，请输入整数。')));
       return; // Stop saving
    }

    // Use defaults if fields are empty or parsing failed (though we added checks above)
    temperature ??= 0.7;
    maxTokens ??= 1000; // Or handle empty state differently if needed

    try {
      final String hostOverride = _hostOverrideController.text.trim();

      debugPrint('=== AI设置页面保存调试 ===');
      debugPrint('API URL: ${_apiUrlController.text}');
      debugPrint('Model: ${_modelController.text}');
      debugPrint('API Key: ${_apiKeyController.text.isNotEmpty ? "存在 (长度: ${_apiKeyController.text.length})" : "不存在"}');
      debugPrint('Temperature: $temperature');
      debugPrint('Max Tokens: $maxTokens');
      debugPrint('Host Override: $hostOverride');

      final secureStorage = SecureStorageService();
      await secureStorage.saveApiKey(_apiKeyController.text);
      debugPrint('API密钥已保存到安全存储');

      // 在异步操作后检查 mounted 状态
      if (!mounted) return;

      await settingsService.updateAISettings(
        AISettings(
          model: _modelController.text,
          apiUrl: _apiUrlController.text,
          apiKey: '', // API Key is saved securely, not here
          temperature: temperature, // Use parsed or default value
          maxTokens: maxTokens, // Use parsed or default value
          hostOverride: hostOverride.isEmpty ? null : hostOverride,
        ),
      );
      debugPrint('AI设置已更新到SettingsService');

      // 在异步操作后检查 mounted 状态
      if (!mounted) return;
      scaffoldMessenger.showSnackBar( // 使用获取到的 scaffoldMessenger
        const SnackBar(content: Text('AI设置已保存')),
      );
      FocusScope.of(context).unfocus(); // Hide keyboard after saving
    } catch (e) {
      // 在异步操作后检查 mounted 状态
      if (!mounted) return;
      scaffoldMessenger.showSnackBar( // 使用获取到的 scaffoldMessenger
        SnackBar(content: Text('保存设置失败: $e')),
      );
    }
  }  Future<void> _testConnection() async {
    // 先保存当前设置
    await _saveSettings();
    
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    
    try {
      // 显示加载状态
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在测试连接...'),
            ],
          ),
        ),
      );

      // 获取AI服务实例并测试连接
      final aiService = Provider.of<AIService>(context, listen: false);
      
      await aiService.testConnection();
      
      if (!mounted) return;
      navigator.pop(); // 关闭加载对话框
      
      // 显示成功消息
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('AI连接测试成功！'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭加载对话框
      
      // 显示错误消息
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('连接测试失败：${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
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
              isExpanded: true,
              items: aiPresets.map((preset) {
                return DropdownMenuItem(
                  value: preset['name'],
                  child: Text(preset['name']!, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedPreset = value;
                  final preset = aiPresets.firstWhere((p) => p['name'] == value);
                  _apiUrlController.text = preset['apiUrl']!;
                  _modelController.text = preset['model']!; // This will be empty for some presets now
                  // Optionally clear API key when changing preset?
                  // _apiKeyController.clear();
                });
              },
              decoration: const InputDecoration(
                labelText: '快速选择AI服务预设',
                border: OutlineInputBorder(),
              ),
              hint: const Text('选择或手动配置'),
            ),
            const SizedBox(height: 20),
            Text(
              'API 设置 (${_selectedPreset ?? '自定义'})',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API URL',
                hintText: '服务接口地址',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() { _selectedPreset = null; }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: '服务所需的密钥',
                border: OutlineInputBorder(),
                 prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: '模型名称',
                // Updated hint text for clarity
                hintText: _selectedPreset == 'Ollama' || _selectedPreset == 'LMStudio' || _selectedPreset == 'OpenAPI兼容' || _selectedPreset == '硅基流动'
                          ? '请输入模型名称'
                          : '例如: gpt-4o, claude-3.7-sonnet-latest',
                border: const OutlineInputBorder(),
                 prefixIcon: const Icon(Icons.model_training),
              ),
               onChanged: (_) => setState(() { _selectedPreset = null; }),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxTokensController,
                    decoration: const InputDecoration(
                      labelText: '最大令牌',
                      hintText: '例如: 2048',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.token),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostOverrideController,
              decoration: const InputDecoration(
                labelText: '主机覆盖 (Host Override)',
                hintText: '可选，用于代理或特殊网络',
                border: OutlineInputBorder(),
                 prefixIcon: Icon(Icons.dns),
              ),
               keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                '注意：AI生成内容仅供参考。API Key 将安全存储在设备本地。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.applyOpacity(0.7),
                    ),
                textAlign: TextAlign.center,
              ),
            ),            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('保存 AI 设置'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      textStyle: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _testConnection,
                    icon: const Icon(Icons.network_check),
                    label: const Text('测试连接'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      textStyle: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
             const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}