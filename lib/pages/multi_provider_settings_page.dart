import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/ai_service.dart';
import '../models/ai_provider_settings.dart';
import '../utils/dio_network_utils.dart';
import '../services/secure_storage_service.dart';

class MultiProviderSettingsPage extends StatefulWidget {
  const MultiProviderSettingsPage({super.key});

  @override
  State<MultiProviderSettingsPage> createState() => _MultiProviderSettingsPageState();
}

class _MultiProviderSettingsPageState extends State<MultiProviderSettingsPage> {
  late MultiAISettings _multiSettings;
  final Map<String, bool> _testingStatus = {};
  final Map<String, String?> _testResults = {};
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    _multiSettings = settingsService.multiAISettings;
    debugPrint('加载多供应商设置，当前provider: ${_multiSettings.currentProviderId}');
    debugPrint('供应商列表: ${_multiSettings.providers.map((p) => '${p.name}(${p.id})').join(', ')}');
  }
  Future<void> _saveSettings() async {
    try {
      debugPrint('保存多供应商设置，当前provider: ${_multiSettings.currentProviderId}');
      debugPrint('供应商配置数量: ${_multiSettings.providers.length}');
      
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      await settingsService.saveMultiAISettings(_multiSettings);
      
      // 验证设置是否真的保存了
      final savedSettings = settingsService.multiAISettings;
      debugPrint('验证保存结果，当前provider: ${savedSettings.currentProviderId}');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('保存多供应商设置失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _testProvider(AIProviderSettings provider) async {
    if (provider.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${provider.name} 需要配置API密钥')),
      );
      return;
    }

    setState(() {
      _testingStatus[provider.id] = true;
      _testResults[provider.id] = null;
    });

    try {
      // 创建测试消息
      final testMessages = [
        {
          'role': 'system',
          'content': '你是一个AI助手。请简单回复"连接测试成功"。',
        },
        {
          'role': 'user',
          'content': '测试连接',
        },
      ];

      // 使用指定provider测试连接
      final response = await DioNetworkUtils.makeRequestWithProvider(
        '',
        {
          'messages': testMessages,
          'temperature': 0.1,
          'max_tokens': 50,
        },
        provider,
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['choices'] != null &&
            data['choices'].isNotEmpty &&
            data['choices'][0]['message'] != null) {
          setState(() {
            _testResults[provider.id] = '连接成功';
          });
        } else {
          setState(() {
            _testResults[provider.id] = '响应格式异常';
          });
        }
      } else {
        setState(() {
          _testResults[provider.id] = '连接失败：${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _testResults[provider.id] = '连接失败：${e.toString()}';
      });
    } finally {
      setState(() {
        _testingStatus[provider.id] = false;
      });
    }
  }

  void _setCurrentProvider(AIProviderSettings provider) {
    setState(() {
      _multiSettings = _multiSettings.copyWith(currentProviderId: provider.id);
    });
    _saveSettings();
  }

  void _toggleFailover(bool enabled) {
    setState(() {
      _multiSettings = _multiSettings.copyWith(enableFailover: enabled);
    });
    _saveSettings();
  }

  void _configureProvider(AIProviderSettings provider) {
    _showProviderConfigDialog(provider);
  }

  void _showProviderConfigDialog(AIProviderSettings provider) {
    final apiKeyController = TextEditingController(text: provider.apiKey);
    final modelController = TextEditingController(text: provider.model);
    final temperatureController = TextEditingController(text: provider.temperature.toString());
    final maxTokensController = TextEditingController(text: provider.maxTokens.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('配置 ${provider.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '输入API密钥',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: '例如：gpt-4o, claude-3-sonnet',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: temperatureController,
                      decoration: const InputDecoration(
                        labelText: '温度',
                        hintText: '0.0-2.0',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: maxTokensController,
                      decoration: const InputDecoration(
                        labelText: '最大令牌',
                        hintText: '1000',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final double? temperature = double.tryParse(temperatureController.text);
              final int? maxTokens = int.tryParse(maxTokensController.text);

              if (temperature == null || temperature < 0 || temperature > 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('温度值必须在0.0-2.0之间')),
                );
                return;
              }

              if (maxTokens == null || maxTokens <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('最大令牌数必须大于0')),
                );
                return;
              }              // 更新provider配置
              final updatedProviders = _multiSettings.providers.map((p) {
                if (p.id == provider.id) {
                  return p.copyWith(
                    apiKey: apiKeyController.text.trim(),
                    model: modelController.text.trim(),
                    temperature: temperature,
                    maxTokens: maxTokens,
                    isEnabled: apiKeyController.text.trim().isNotEmpty,
                  );
                }
                return p;
              }).toList();

              // 更新本地设置
              _multiSettings = _multiSettings.copyWith(providers: updatedProviders);

              // 立即保存设置
              await _saveSettings();
              
              // 更新UI状态
              setState(() {});
              
              if (!mounted) return;
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${provider.name} 配置已更新并保存')),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Color _getProviderStatusColor(AIProviderSettings provider) {
    if (!provider.isEnabled || provider.apiKey.isEmpty) {
      return Colors.grey;
    }
    
    final result = _testResults[provider.id];
    if (result == null) return Colors.orange;
    if (result.contains('成功')) return Colors.green;
    return Colors.red;
  }

  IconData _getProviderStatusIcon(AIProviderSettings provider) {
    if (!provider.isEnabled || provider.apiKey.isEmpty) {
      return Icons.circle_outlined;
    }
    
    final result = _testResults[provider.id];
    if (result == null) return Icons.help_outline;
    if (result.contains('成功')) return Icons.check_circle;
    return Icons.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 服务商管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('使用说明'),
                  content: const Text(
                    '• 选择当前使用的AI服务商\n'
                    '• 配置每个服务商的API密钥和参数\n'
                    '• 开启故障转移功能可在当前服务商失败时自动切换\n'
                    '• 绿色表示连接正常，红色表示连接失败，灰色表示未配置',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('了解'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<SettingsService>(
        builder: (context, settingsService, child) {
          _multiSettings = settingsService.multiAISettings;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 故障转移设置
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自动故障转移',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('启用自动切换'),
                        subtitle: const Text('当前服务商失败时自动尝试其他可用服务商'),
                        value: _multiSettings.enableFailover,
                        onChanged: _toggleFailover,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 服务商列表
              Text(
                'AI 服务商列表',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              ..._multiSettings.providers.map((provider) {
                final isCurrent = provider.id == _multiSettings.currentProviderId;
                final isAvailable = provider.isEnabled && provider.apiKey.isNotEmpty;
                final isTesting = _testingStatus[provider.id] ?? false;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        Icon(
                          _getProviderStatusIcon(provider),
                          color: _getProviderStatusColor(provider),
                          size: 24,
                        ),
                        if (isCurrent)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Text(provider.name),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '当前',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('模型：${provider.model.isEmpty ? "未配置" : provider.model}'),
                        if (_testResults[provider.id] != null)
                          Text(
                            _testResults[provider.id]!,
                            style: TextStyle(
                              color: _testResults[provider.id]!.contains('成功')
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTesting)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.network_check),
                            onPressed: isAvailable ? () => _testProvider(provider) : null,
                            tooltip: '测试连接',
                          ),
                        IconButton(
                          icon: const Icon(Icons.settings),
                          onPressed: () => _configureProvider(provider),
                          tooltip: '配置',
                        ),
                        if (isAvailable && !isCurrent)
                          IconButton(
                            icon: const Icon(Icons.radio_button_unchecked),
                            onPressed: () => _setCurrentProvider(provider),
                            tooltip: '设为当前',
                          ),
                      ],
                    ),
                    onTap: isAvailable && !isCurrent 
                        ? () => _setCurrentProvider(provider)
                        : null,
                  ),
                );
              }).toList(),
              
              const SizedBox(height: 24),
              
              // 说明文本
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用提示',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. 点击"配置"按钮为服务商添加API密钥\n'
                      '2. 配置完成后可以测试连接状态\n'
                      '3. 选择一个服务商作为主要使用的服务商\n'
                      '4. 开启故障转移后，主服务商失败时会自动切换到其他可用服务商',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
