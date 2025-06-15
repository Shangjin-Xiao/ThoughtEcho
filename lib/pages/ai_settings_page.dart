import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../services/settings_service.dart';
import '../services/ai_service.dart';
import '../models/ai_settings.dart';
import '../models/ai_provider_settings.dart';
import '../models/multi_ai_settings.dart';
import '../utils/app_logger.dart';
import '../services/api_key_manager.dart';
import '../utils/ai_network_manager.dart';
import '../utils/api_key_debugger.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _maxTokensController = TextEditingController();
  String? _hostOverride;
  final _hostOverrideController = TextEditingController();

  // 多provider管理相关状态
  late MultiAISettings _multiSettings;
  AIProviderSettings? _currentProvider;
  final Map<String, bool> _testingStatus = {};
  final Map<String, String?> _testResults = {};

  // API Key状态显示
  String _apiKeyStatus = '';
  bool _isCheckingApiKey = false;

  // Updated presets list based on verification
  final List<Map<String, String>> aiPresets = [
    {
      'name': 'OpenAI',
      'apiUrl': 'https://api.openai.com/v1/chat/completions',
      'model': 'gpt-4o',
    },
    {
      'name': 'OpenRouter',
      'apiUrl': 'https://openrouter.ai/api/v1/chat/completions',
      'model': 'openai/gpt-4o',
    },
    {
      'name': '硅基流动',
      'apiUrl': 'https://api.siliconflow.cn/v1/chat/completions',
      'model': '',
    },
    {
      'name': 'DeepSeek',
      'apiUrl': 'https://api.deepseek.com/v1/chat/completions',
      'model': 'deepseek-chat',
    },
    {
      'name': 'Anthropic (Claude)',
      'apiUrl': 'https://api.anthropic.com/v1/messages',
      'model': 'claude-3.7-sonnet-latest',
    },
    {
      'name': 'Ollama',
      'apiUrl': 'http://localhost:11434/v1/chat/completions',
      'model': '',
    },
    {
      'name': 'LMStudio',
      'apiUrl': 'http://localhost:1234/v1/chat/completions',
      'model': '',
    },
    {
      'name': 'OpenAPI兼容',
      'apiUrl': 'http://your-openapi-server/v1/chat/completions',
      'model': '',
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
    _maxTokensController.dispose();
    _hostOverrideController.dispose();
    super.dispose();
  }

  /// 异步加载当前provider的API Key
  Future<void> _loadApiKeyAsync() async {
    if (_currentProvider != null) {
      final apiKeyManager = APIKeyManager();
      logDebug('开始加载API Key - Provider ID: ${_currentProvider!.id}');

      final apiKey = await apiKeyManager.getProviderApiKey(
        _currentProvider!.id,
      );

      logDebug(
        '从加密存储读取的API Key: ${apiKey.isNotEmpty ? "${apiKey.length}字符" : "空"}',
      );

      if (mounted) {
        setState(() {
          _apiKeyController.text = apiKey;
        });
        logDebug('已更新API Key输入框: ${_apiKeyController.text.length}字符');
      }
    } else {
      logDebug('加载API Key失败: 当前provider为空');
    }
  }

  void _loadMultiSettings() {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    _multiSettings = settingsService.multiAISettings;
    _currentProvider = _multiSettings.currentProvider;
    logDebug('当前provider: ${_currentProvider?.name ?? "无"}');
    _updateApiKeyStatus();

    // 异步更新API Key状态
    _updateApiKeyStatusAsync();
  }

  void _updateApiKeyStatus() {
    if (_currentProvider != null) {
      // 显示临时状态，等待异步验证
      _apiKeyStatus = '正在验证API Key...';
    } else {
      _apiKeyStatus = '未选择服务商';
    }
  }

  /// 异步更新API Key状态（从安全存储验证）
  Future<void> _updateApiKeyStatusAsync() async {
    logDebug('开始异步更新API Key状态...');
    if (_currentProvider != null) {
      final apiKeyManager = APIKeyManager();
      logDebug('当前Provider ID: ${_currentProvider!.id}');

      final hasValidKey = await apiKeyManager.hasValidProviderApiKey(
        _currentProvider!.id,
      );
      logDebug('API Key有效性检查结果: $hasValidKey');

      if (hasValidKey) {
        final secureApiKey = await apiKeyManager.getProviderApiKey(
          _currentProvider!.id,
        );
        _apiKeyStatus = 'API Key有效 (${secureApiKey.length}字符)';
        logDebug('API Key状态更新: $_apiKeyStatus');
      } else {
        _apiKeyStatus = '未配置有效的API Key';
        logDebug('API Key状态更新: $_apiKeyStatus');
      }
    } else {
      _apiKeyStatus = '未选择服务商';
      logDebug('API Key状态更新: $_apiKeyStatus');
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// 检查当前API Key状态
  Future<void> _checkApiKeyStatus() async {
    setState(() {
      _isCheckingApiKey = true;
    });

    try {
      final settingsService = Provider.of<SettingsService>(
        context,
        listen: false,
      );

      // 获取当前设置
      final multiSettings = settingsService.multiAISettings;

      String statusMessage;
      if (multiSettings.currentProvider == null) {
        statusMessage = '❌ 未选择AI服务商';
      } else {
        final provider = multiSettings.currentProvider!;

        if (!provider.isEnabled) {
          statusMessage = '⚠️ 服务商已禁用';
        } else {
          // 使用简化的API Key检测方法
          final apiKeyManager = APIKeyManager();
          final hasValidKey = await apiKeyManager.hasValidProviderApiKey(
            provider.id,
          );

          if (hasValidKey) {
            statusMessage = '✅ API Key有效 (已验证)';
          } else {
            statusMessage = '❌ 未配置有效的API Key';
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('API Key状态检查: $statusMessage'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingApiKey = false;
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      // 首先加载多provider设置
      _loadMultiSettings();

      // 在异步操作后检查 mounted 状态
      if (!mounted) return;

      setState(() {
        // 优先使用当前provider的设置
        if (_currentProvider != null) {
          _modelController.text = _currentProvider!.model;
          _apiUrlController.text = _currentProvider!.apiUrl;
          _apiKeyController.text = ''; // 不从配置读取API Key
          _maxTokensController.text = _currentProvider!.maxTokens.toString();
          _hostOverride = _currentProvider!.hostOverride;
          _hostOverrideController.text = _hostOverride ?? '';

          // 异步加载API Key
          _loadApiKeyAsync();

          // 尝试匹配预设
          try {
            _selectedPreset =
                aiPresets.firstWhere(
                  (p) => p['apiUrl'] == _apiUrlController.text,
                )['name'];
          } catch (_) {
            _selectedPreset = null;
          }
        } else {
          // 如果没有当前provider，使用默认值
          _modelController.text = '';
          _apiUrlController.text = '';
          _apiKeyController.text = '';
          _maxTokensController.text = '1000';
          _hostOverride = null;
          _hostOverrideController.text = '';
          _selectedPreset = null;
        }
      });
    } catch (e) {
      logDebug('加载AI设置失败: $e');
      // 在异步操作后检查 mounted 状态
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载AI设置失败: $e')));
    }
  }

  Future<void> _saveSettings() async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 验证输入
    if (_apiUrlController.text.trim().isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('请输入API URL')),
      );
      return;
    }

    if (_apiKeyController.text.trim().isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('请输入API Key')),
      );
      return;
    }

    // 验证最大令牌数
    final maxTokensText = _maxTokensController.text.trim();
    int maxTokens = 1000;
    if (maxTokensText.isNotEmpty) {
      final parsed = int.tryParse(maxTokensText);
      if (parsed == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('最大令牌数必须是有效的整数')),
        );
        return;
      }
      maxTokens = parsed;
    }

    try {
      // 创建新的provider
      await _createOrUpdateProvider(
        0.7, // 固定温度值
        maxTokens,
        _hostOverrideController.text.trim(),
        settingsService,
      );

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('新预设已创建并保存')),
      );
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('保存设置失败: $e')));
    }
  }

  // 创建新的provider（每次保存都创建新的，不更新现有的）
  Future<void> _createOrUpdateProvider(
    double temperature,
    int maxTokens,
    String hostOverride,
    SettingsService settingsService,
  ) async {
    // 确定provider名称（基于预设或自定义）
    String providerName = _selectedPreset ?? '自定义配置';

    // 为自定义配置生成唯一名称
    if (providerName == '自定义配置') {
      final uri = Uri.tryParse(_apiUrlController.text);
      if (uri != null && uri.host.isNotEmpty) {
        providerName = '自定义-${uri.host}';
      } else {
        providerName = '自定义-${DateTime.now().millisecondsSinceEpoch}';
      }
    }

    // 始终创建新的provider，不更新现有的
    logDebug('创建新provider: $providerName');

    final newProvider = AIProviderSettings(
      id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      name: providerName,
      apiKey: '', // 不再在配置中保存API Key
      apiUrl: _apiUrlController.text,
      model: _modelController.text,
      temperature: temperature,
      maxTokens: maxTokens,
      hostOverride: hostOverride.isEmpty ? null : hostOverride,
      isEnabled: _apiKeyController.text.isNotEmpty,
    );

    // 先保存API密钥到安全存储（确保成功）
    final apiKeyManager = APIKeyManager();
    logDebug(
      '准备保存API Key: ${_apiKeyController.text.isEmpty ? "空" : "${_apiKeyController.text.length}字符"}',
    );
    logDebug(
      'API Key内容: ${_apiKeyController.text.isEmpty ? "空" : _apiKeyController.text.substring(0, math.min(20, _apiKeyController.text.length))}...',
    );

    // 调试保存过程
    await ApiKeyDebugger.debugApiKeySave(
      newProvider.id,
      _apiKeyController.text,
    );

    await apiKeyManager.saveProviderApiKey(
      newProvider.id,
      _apiKeyController.text,
    );
    logDebug('已保存新provider的API密钥到安全存储: ${_apiKeyController.text.length}字符');

    // 立即验证保存是否成功
    final savedKey = await apiKeyManager.getProviderApiKey(newProvider.id);
    logDebug(
      '验证保存结果: ${savedKey.isEmpty ? "保存失败，读取为空" : "保存成功，读取到${savedKey.length}字符"}',
    );

    // 再添加到provider列表
    final updatedProviders = [..._multiSettings.providers, newProvider];

    // 设置为当前provider
    final updatedMultiSettings = _multiSettings.copyWith(
      providers: updatedProviders,
      currentProviderId: newProvider.id,
    );

    // 保存设置
    await settingsService.saveMultiAISettings(updatedMultiSettings);

    // 更新本地状态
    _multiSettings = updatedMultiSettings;
    _currentProvider = newProvider;

    // 立即更新API Key状态显示（异步验证）
    await _updateApiKeyStatusAsync();

    // 进行完整的生命周期调试
    await ApiKeyDebugger.debugApiKeyLifecycle(settingsService);

    logDebug('新provider已创建并设置为当前provider');

    // 同时保存到传统AI设置作为后备
    await settingsService.updateAISettings(
      AISettings(
        model: _modelController.text,
        apiUrl: _apiUrlController.text,
        apiKey: '', // API Key is saved securely, not here
        temperature: temperature,
        maxTokens: maxTokens,
        hostOverride: hostOverride.isEmpty ? null : hostOverride,
      ),
    );
    logDebug('传统AI设置已更新');
  }

  Future<void> _testConnection() async {
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
        builder:
            (context) => const AlertDialog(
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

      // 测试当前provider或传统AI服务
      if (_currentProvider != null) {
        await _testProvider(_currentProvider!);
      } else {
        // 获取AI服务实例并测试连接
        final aiService = Provider.of<AIService>(context, listen: false);
        await aiService.testConnection();
      }

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

  Future<void> _testProvider(AIProviderSettings provider) async {
    if (provider.apiKey.isEmpty) {
      throw Exception('${provider.name} 需要配置API密钥');
    }

    setState(() {
      _testingStatus[provider.id] = true;
      _testResults[provider.id] = null;
    });

    try {
      // 创建测试消息
      final testMessages = [
        {'role': 'system', 'content': '你是一个AI助手。请简单回复"连接测试成功"。'},
        {'role': 'user', 'content': '测试连接'},
      ]; // 使用指定provider测试连接
      final response = await AINetworkManager.makeRequest(
        url: '',
        data: {'messages': testMessages, 'temperature': 0.1, 'max_tokens': 50},
        provider: provider,
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
      rethrow; // 重新抛出异常供上层处理
    } finally {
      setState(() {
        _testingStatus[provider.id] = false;
      });
    }
  }

  void _setCurrentProvider(AIProviderSettings provider) async {
    setState(() {
      _multiSettings = _multiSettings.copyWith(currentProviderId: provider.id);
      _currentProvider = provider;
    });

    // 立即保存provider切换
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    await settingsService.saveMultiAISettings(_multiSettings);

    // 使用APIKeyManager保存API Key到安全存储
    if (provider.apiKey.isNotEmpty) {
      final apiKeyManager = APIKeyManager();
      await apiKeyManager.saveProviderApiKey(provider.id, provider.apiKey);
      logDebug('已保存 ${provider.name} 的API密钥到安全存储');
    }

    // 更新表单字段为新provider的设置
    setState(() {
      _apiUrlController.text = provider.apiUrl;
      _apiKeyController.text = provider.apiKey;
      _modelController.text = provider.model;
      _maxTokensController.text = provider.maxTokens.toString();
      _hostOverrideController.text = provider.hostOverride ?? '';
    });

    // 异步更新API Key状态
    await _updateApiKeyStatusAsync();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已切换到 ${provider.name}')));
  }

  // 重命名provider
  Future<void> _renameProvider(AIProviderSettings provider) async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final TextEditingController nameController = TextEditingController(
      text: provider.name,
    );

    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('重命名预设'),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '预设名称',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.pop(context, nameController.text.trim()),
                child: const Text('确定'),
              ),
            ],
          ),
    );

    if (result != null && result.isNotEmpty && result != provider.name) {
      // 更新provider名称
      final updatedProviders =
          _multiSettings.providers.map((p) {
            if (p.id == provider.id) {
              return p.copyWith(name: result);
            }
            return p;
          }).toList();

      final updatedMultiSettings = _multiSettings.copyWith(
        providers: updatedProviders,
      );

      await settingsService.saveMultiAISettings(updatedMultiSettings);

      if (!mounted) return;

      setState(() {
        _multiSettings = updatedMultiSettings;
        if (_currentProvider?.id == provider.id) {
          _currentProvider = updatedMultiSettings.currentProvider;
        }
      });

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('预设已重命名为 "$result"')),
      );
    }

    nameController.dispose();
  }

  // 删除provider
  Future<void> _deleteProvider(AIProviderSettings provider) async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除预设'),
            content: Text('确定要删除预设 "${provider.name}" 吗？此操作无法撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final updatedProviders =
          _multiSettings.providers.where((p) => p.id != provider.id).toList();

      // 如果删除的是当前provider，切换到第一个可用的provider或清空
      String? newCurrentProviderId = _multiSettings.currentProviderId;
      if (_currentProvider?.id == provider.id) {
        newCurrentProviderId =
            updatedProviders.isNotEmpty ? updatedProviders.first.id : null;
      }

      final updatedMultiSettings = _multiSettings.copyWith(
        providers: updatedProviders,
        currentProviderId: newCurrentProviderId,
      );

      await settingsService.saveMultiAISettings(updatedMultiSettings);

      if (!mounted) return;

      setState(() {
        _multiSettings = updatedMultiSettings;
        _currentProvider = updatedMultiSettings.currentProvider;

        // 如果删除的是当前provider，清空或更新表单
        if (provider.id == _currentProvider?.id || _currentProvider == null) {
          if (_currentProvider != null) {
            _apiUrlController.text = _currentProvider!.apiUrl;
            _apiKeyController.text = _currentProvider!.apiKey;
            _modelController.text = _currentProvider!.model;
            _maxTokensController.text = _currentProvider!.maxTokens.toString();
            _hostOverrideController.text = _currentProvider!.hostOverride ?? '';
          } else {
            _apiUrlController.clear();
            _apiKeyController.clear();
            _modelController.clear();
            _maxTokensController.text = '1000';
            _hostOverrideController.clear();
          }
        }
      });

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('预设 "${provider.name}" 已删除')),
      );
    }
  }

  Widget _buildProviderSelector() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 服务商选择',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 当前选中的provider（只有在有provider的情况下才显示）
            if (_currentProvider != null && _multiSettings.providers.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前: ${_currentProvider!.name}',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'API: ${_currentProvider!.apiUrl}',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '模型: ${_currentProvider!.model.isEmpty ? "未配置" : _currentProvider!.model}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'API Key: $_apiKeyStatus',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color:
                                  _apiKeyStatus.contains('有效')
                                      ? Colors.green
                                      : _apiKeyStatus.contains('无效')
                                      ? Colors.red
                                      : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // API Key检查按钮
                    IconButton(
                      onPressed: _isCheckingApiKey ? null : _checkApiKeyStatus,
                      icon:
                          _isCheckingApiKey
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.refresh),
                      tooltip: '检查API Key状态',
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            // Provider列表
            Text(
              '已保存的预设 (${_multiSettings.providers.length}):',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            // 如果没有保存的provider，显示提示
            if (_multiSettings.providers.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '还没有保存的预设。配置完API信息后点击"保存设置"来创建第一个预设。',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._multiSettings.providers.map((provider) {
                final isCurrent = provider.id == _currentProvider?.id;
                final isAvailable =
                    provider.isEnabled && provider.apiKey.isNotEmpty;
                final isTesting = _testingStatus[provider.id] ?? false;

                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    leading: Icon(
                      isCurrent
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color:
                          isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : null,
                    ),
                    title: Text(provider.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '模型：${provider.model.isEmpty ? "未配置" : provider.model}',
                        ),
                        if (_testResults[provider.id] != null)
                          Text(
                            _testResults[provider.id]!,
                            style: TextStyle(
                              color:
                                  _testResults[provider.id]!.contains('成功')
                                      ? Colors.green
                                      : Colors.red,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 重命名按钮
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _renameProvider(provider),
                          tooltip: '重命名',
                          iconSize: 20,
                        ),
                        // 删除按钮
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteProvider(provider),
                          tooltip: '删除',
                          iconSize: 20,
                          color: Colors.red,
                        ),
                        // 测试连接按钮
                        if (isTesting)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (isAvailable && isCurrent)
                          IconButton(
                            icon: const Icon(Icons.network_check),
                            onPressed: () => _testProvider(provider),
                            tooltip: '测试连接',
                            iconSize: 20,
                          ),
                      ],
                    ),
                    onTap:
                        !isCurrent ? () => _setCurrentProvider(provider) : null,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider选择器
            _buildProviderSelector(),

            DropdownButtonFormField<String>(
              value: _selectedPreset,
              isExpanded: true,
              items:
                  aiPresets.map((preset) {
                    return DropdownMenuItem(
                      value: preset['name'],
                      child: Text(
                        preset['name']!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedPreset = value;
                  final preset = aiPresets.firstWhere(
                    (p) => p['name'] == value,
                  );
                  _apiUrlController.text = preset['apiUrl']!;
                  _modelController.text = preset['model']!;
                  // 保留当前的API Key，不要清空
                  // _apiKeyController.text 保持不变
                });
                logDebug('切换预设到: $value, 保留现有API Key');
              },
              decoration: const InputDecoration(
                labelText: '快速选择AI服务预设',
                border: OutlineInputBorder(),
              ),
              hint: const Text('选择或手动配置'),
            ),
            const SizedBox(height: 20),
            Text(
              'API 设置 (${_currentProvider?.name ?? _selectedPreset ?? '自定义'})',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
              onChanged:
                  (_) => setState(() {
                    _selectedPreset = null;
                  }),
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
                hintText:
                    _selectedPreset != null &&
                            aiPresets
                                .firstWhere(
                                  (p) => p['name'] == _selectedPreset,
                                )['model']!
                                .isEmpty
                        ? '请输入模型名称'
                        : '使用默认模型或自定义',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.psychology),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxTokensController,
              decoration: const InputDecoration(
                labelText: '最大令牌数',
                hintText: '例如: 2048',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostOverrideController,
              decoration: const InputDecoration(
                labelText: '主机覆盖 (Host Override)',
                hintText: '可选，用于代理设置',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Text(
                    '温度固定为 0.7',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.add),
                        label: const Text('创建新预设'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _testConnection,
                        icon: const Icon(Icons.network_check),
                        label: const Text('测试连接'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
