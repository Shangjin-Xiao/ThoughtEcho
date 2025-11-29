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
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  final _formKey = GlobalKey<FormState>(); // 添加表单Key
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  // 最大令牌数不再对用户暴露，内部使用较大默认值
  final _maxTokensController = TextEditingController(text: '32000');
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
  bool _obscureApiKey = true; // API Key显示切换

  // Updated presets list based on verification
  List<Map<String, String>> _getAiPresets(AppLocalizations l10n) {
    return [
      {
        'name': l10n.aiProviderOpenAI,
        'apiUrl': 'https://api.openai.com/v1/chat/completions',
        'model': 'gpt-4o',
      },
      {
        'name': l10n.aiProviderOpenRouter,
        'apiUrl': 'https://openrouter.ai/api/v1/chat/completions',
        'model': 'openai/gpt-4o',
      },
      {
        'name': l10n.siliconflow,
        'apiUrl': 'https://api.siliconflow.cn/v1/chat/completions',
        'model': '',
      },
      {
        'name': l10n.aiProviderDeepSeek,
        'apiUrl': 'https://api.deepseek.com/v1/chat/completions',
        'model': 'deepseek-chat',
      },
      {
        'name': l10n.aiProviderAnthropic,
        'apiUrl': 'https://api.anthropic.com/v1/messages',
        'model': 'claude-3.7-sonnet-latest',
      },
      {
        'name': l10n.aiProviderOllama,
        'apiUrl': 'http://localhost:11434/v1/chat/completions',
        'model': '',
      },
      {
        'name': l10n.aiProviderLMStudio,
        'apiUrl': 'http://localhost:1234/v1/chat/completions',
        'model': '',
      },
      {
        'name': l10n.openapiCompatible,
        'apiUrl': 'http://your-openapi-server/v1/chat/completions',
        'model': '',
      },
    ];
  }
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
    final l10n = AppLocalizations.of(context);
    if (_currentProvider != null) {
      final apiKeyManager = APIKeyManager();
      logDebug('Loading API key for provider: ${_currentProvider!.id}');

      final apiKey = await apiKeyManager.getProviderApiKey(
        _currentProvider!.id,
      );

      logDebug(
          'API key read from storage: ${apiKey.isNotEmpty ? 'not empty (${apiKey.length} chars)' : 'empty'}');

      if (mounted) {
        setState(() {
          _apiKeyController.text = apiKey;
        });
        logDebug(
            'API key text controller updated, length: ${_apiKeyController.text.length}');
      }
    } else {
      logDebug('Cannot load API key, current provider is null.');
    }
  }

  void _loadMultiSettings() {
    final l10n = AppLocalizations.of(context);
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    _multiSettings = settingsService.multiAISettings;
    _currentProvider = _multiSettings.currentProvider;
    logDebug(
        'Current provider from multi-settings: ${_currentProvider?.name ?? "none"}');
    _updateApiKeyStatus();

    // 异步更新API Key状态
    _updateApiKeyStatusAsync();
  }

  void _updateApiKeyStatus() {
    final l10n = AppLocalizations.of(context);
    if (_currentProvider != null) {
      // 显示临时状态，等待异步验证
      _apiKeyStatus = l10n.verifyingApiKey;
    } else {
      _apiKeyStatus = l10n.noProviderSelected;
    }
  }

  /// 异步更新API Key状态（从安全存储验证）
  Future<void> _updateApiKeyStatusAsync() async {
    final l10n = AppLocalizations.of(context);
    logDebug('Updating API key status asynchronously...');
    if (_currentProvider != null) {
      final apiKeyManager = APIKeyManager();
      logDebug('Current provider ID: ${_currentProvider!.id}');

      final hasValidKey = await apiKeyManager.hasValidProviderApiKey(
        _currentProvider!.id,
      );
      logDebug('API key validation result from secure storage: $hasValidKey');

      if (hasValidKey) {
        final secureApiKey = await apiKeyManager.getProviderApiKey(
          _currentProvider!.id,
        );
        _apiKeyStatus = l10n.apiKeyValid(secureApiKey.length);
        logDebug('API key status updated: $_apiKeyStatus');
      } else {
        _apiKeyStatus = l10n.apiKeyInvalid;
        logDebug('API key status updated: $_apiKeyStatus');
      }
    } else {
      _apiKeyStatus = l10n.noProviderSelected;
      logDebug('API key status updated: $_apiKeyStatus');
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// 检查当前API Key状态
  Future<void> _checkApiKeyStatus() async {
    final l10n = AppLocalizations.of(context);
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
        statusMessage = l10n.noAiProviderSelected;
      } else {
        final provider = multiSettings.currentProvider!;

        if (!provider.isEnabled) {
          statusMessage = l10n.providerDisabled;
        } else {
          // 使用简化的API Key检测方法
          final apiKeyManager = APIKeyManager();
          final hasValidKey = await apiKeyManager.hasValidProviderApiKey(
            provider.id,
          );

          if (hasValidKey) {
            statusMessage = l10n.apiKeyVerified;
          } else {
            statusMessage = l10n.apiKeyInvalid;
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.apiKeyStatusCheck(statusMessage)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.checkFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError),
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
    final l10n = AppLocalizations.of(context);
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
            _selectedPreset = _getAiPresets(l10n).firstWhere(
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
          _maxTokensController.text = '32000';
          _hostOverride = null;
          _hostOverrideController.text = '';
          _selectedPreset = null;
        }
      });

      // 预加载一次reportInsightsUseAI状态，确保UI响应
      // 使用SettingsService提供的getter
    } catch (e) {
      logError(l10n.loadAiSettingsError(e.toString()),
          error: e, source: 'AISettingsPage._loadSettings');
      // 在异步操作后检查 mounted 状态
      if (!mounted) return;

      // 显示用户友好的错误信息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.loadAiSettingsErrorUser),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: l10n.retry,
            textColor: Colors.white,
            onPressed: () => _loadSettings(),
          ),
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    final l10n = AppLocalizations.of(context);
    // 首先验证表单
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.fixFormErrors)),
            ],
          ),
          backgroundColor: Colors.red,
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 解析最大令牌数
    // 统一采用较大安全上限，底层会按provider能力裁剪
    int maxTokens = 32000;

    try {
      // 创建新的provider
      await _createOrUpdateProvider(
        maxTokens,
        _hostOverrideController.text.trim(),
        settingsService,
      );

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.presetCreated)),
            ],
          ),
          backgroundColor: Colors.green,
          duration: AppConstants.snackBarDurationNormal,
        ),
      );
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.saveSettingsError(e.toString()))),
            ],
          ),
          backgroundColor: Colors.red,
          duration: AppConstants.snackBarDurationError,
        ),
      );
    }
  }

  // 创建新的provider（每次保存都创建新的，不更新现有的）
  Future<void> _createOrUpdateProvider(
    int maxTokens,
    String hostOverride,
    SettingsService settingsService,
  ) async {
    final l10n = AppLocalizations.of(context);
    // 确定provider名称（基于预设或自定义）
    String providerName = _selectedPreset ?? l10n.customConfig;

    // 为自定义配置生成唯一名称
    if (providerName == l10n.customConfig) {
      final uri = Uri.tryParse(_apiUrlController.text);
      if (uri != null && uri.host.isNotEmpty) {
        providerName = l10n.customConfigHost(uri.host);
      } else {
        providerName =
            l10n.customConfigTimestamp(DateTime.now().millisecondsSinceEpoch);
      }
    }

    // 始终创建新的provider，不更新现有的
    logDebug('Creating new provider: $providerName');

    final newProvider = AIProviderSettings(
      id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      name: providerName,
      apiKey: '', // 不再在配置中保存API Key
      apiUrl: _apiUrlController.text,
      model: _modelController.text,
      // 温度不再默认固定；此字段仅存储于预设，不会自动注入请求体
      maxTokens: maxTokens,
      hostOverride: hostOverride.isEmpty ? null : hostOverride,
      isEnabled: _apiKeyController.text.isNotEmpty,
    );

    // 先保存API密钥到安全存储（确保成功）
    final apiKeyManager = APIKeyManager();
    logDebug(
        'Preparing to save API key, length: ${_apiKeyController.text.length}');
    logDebug(
        'API key content prefix: ${_apiKeyController.text.substring(0, math.min(20, _apiKeyController.text.length))}...');

    // 调试保存过程
    await ApiKeyDebugger.debugApiKeySave(
      newProvider.id,
      _apiKeyController.text,
    );

    await apiKeyManager.saveProviderApiKey(
      newProvider.id,
      _apiKeyController.text,
    );
    logDebug(
        'API key saved to secure storage for provider ${newProvider.id}, length: ${_apiKeyController.text.length}');

    // 立即验证保存是否成功
    final savedKey = await apiKeyManager.getProviderApiKey(newProvider.id);
    logDebug(
        'Verified saved API key, read back length: ${savedKey.length}. Save successful: ${savedKey == _apiKeyController.text}');

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

    logDebug('New provider created and saved: ${newProvider.name}');

    // 同时保存到传统AI设置作为后备
    await settingsService.updateAISettings(
      AISettings(
        model: _modelController.text,
        apiUrl: _apiUrlController.text,
        apiKey: '', // API Key is saved securely, not here
        maxTokens: maxTokens,
        hostOverride: hostOverride.isEmpty ? null : hostOverride,
      ),
    );
    logDebug('Legacy AI settings updated as a fallback.');
  }

  Future<void> _testConnection() async {
    final l10n = AppLocalizations.of(context);
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
        builder: (context) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(l10n.testingConnection),
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
        SnackBar(
          content: Text(l10n.connectionTestSuccess),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭加载对话框

      // 显示错误消息
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.connectionTestFailed(e.toString())),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _testProvider(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    if (provider.apiKey.isEmpty) {
      throw Exception(l10n.apiKeyRequired(provider.name));
    }

    setState(() {
      _testingStatus[provider.id] = true;
      _testResults[provider.id] = null;
    });

    try {
      // 创建测试消息
      final testMessages = [
        {'role': 'system', 'content': l10n.connectionTestSystemMessage},
        {'role': 'user', 'content': l10n.connectionTestUserMessage},
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
            _testResults[provider.id] = l10n.connectionSuccess;
          });
        } else {
          setState(() {
            _testResults[provider.id] = l10n.responseFormatError;
          });
        }
      } else {
        setState(() {
          _testResults[provider.id] =
              l10n.connectionFailed(response.statusCode.toString());
        });
      }
    } catch (e) {
      setState(() {
        _testResults[provider.id] = l10n.connectionTestFailed(e.toString());
      });
      rethrow; // 重新抛出异常供上层处理
    } finally {
      setState(() {
        _testingStatus[provider.id] = false;
      });
    }
  }

  void _setCurrentProvider(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
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
      logDebug(l10n.apiKeySavedForProvider(provider.name));
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
    ).showSnackBar(SnackBar(
        content: Text(l10n.switchedTo(provider.name)),
        duration: AppConstants.snackBarDurationNormal));
  }

  // 重命名provider
  Future<void> _renameProvider(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
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
      builder: (context) => AlertDialog(
        title: Text(l10n.renamePreset),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.presetName,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != provider.name) {
      // 更新provider名称
      final updatedProviders = _multiSettings.providers.map((p) {
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
        SnackBar(
            content: Text(l10n.presetRenamed(result)),
            duration: AppConstants.snackBarDurationNormal),
      );
    }

    nameController.dispose();
  }

  // 删除provider
  Future<void> _deleteProvider(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePreset),
        content: Text(l10n.deletePresetConfirm(provider.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
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
            _maxTokensController.text = '32000';
            _hostOverrideController.clear();
          }
        }
      });

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(l10n.presetDeleted(provider.name)),
            duration: AppConstants.snackBarDurationNormal),
      );
    }
  }

  Widget _buildProviderSelector() {
    final l10n = AppLocalizations.of(context);
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
                  l10n.aiProviderSelection,
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
                            l10n.currentProvider(_currentProvider!.name),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            l10n.apiUrlLabel(_currentProvider!.apiUrl),
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            l10n.modelLabel(_currentProvider!.model.isEmpty
                                ? l10n.modelNotConfigured
                                : _currentProvider!.model),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            l10n.apiKeyLabel(_apiKeyStatus),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                                  color: _apiKeyStatus.contains('有效') ||
                                          _apiKeyStatus.contains('valid')
                                      ? Colors.green
                                      : _apiKeyStatus.contains('无效') ||
                                              _apiKeyStatus.contains('invalid')
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
                      icon: _isCheckingApiKey
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      tooltip: l10n.checkApiKeyStatus,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            // Provider列表
            Text(
              l10n.savedPresets(_multiSettings.providers.length),
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
                        l10n.noPresetsSaved,
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
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(provider.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.modelLabel(provider.model.isEmpty
                              ? l10n.modelNotConfigured
                              : provider.model),
                        ),
                        if (_testResults[provider.id] != null)
                          Text(
                            _testResults[provider.id]!,
                            style: TextStyle(
                              color: _testResults[provider.id]!
                                      .contains(l10n.connectionSuccess)
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
                          tooltip: l10n.rename,
                          iconSize: 20,
                        ),
                        // 删除按钮
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteProvider(provider),
                          tooltip: l10n.delete,
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
                            tooltip: l10n.testConnectionButton,
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

  Widget _buildReportInsightSwitch() {
    final l10n = AppLocalizations.of(context);
    final settingsService = Provider.of<SettingsService>(context);
    final enabled = settingsService.reportInsightsUseAI;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile(
        title: Text(l10n.reportInsightsUseAi),
        subtitle: Text(l10n.reportInsightsUseAiDesc),
        value: enabled,
        onChanged: (val) async {
          await settingsService.setReportInsightsUseAI(val);
        },
        secondary: const Icon(Icons.lightbulb_outline),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiSettingsTitle),
        actions: const [
          // 隐藏年度报告功能
          // IconButton(
          //   icon: const Icon(Icons.analytics_outlined),
          //   tooltip: '年度报告',
          //   onPressed: () {
          //     Navigator.of(context).pushNamed('/ai_analysis_history');
          //   },
          // ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey, // 添加表单Key
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Provider选择器
              _buildProviderSelector(),
              // 预设选择
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            l10n.quickPresets,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedPreset,
                        isExpanded: true,
                        items: _getAiPresets(l10n).map((preset) {
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
                            final preset = _getAiPresets(l10n).firstWhere(
                              (p) => p['name'] == value,
                            );
                            _apiUrlController.text = preset['apiUrl']!;
                            _modelController.text = preset['model']!;
                            // 保留当前的API Key，不要清空
                          });
                          logDebug('切换预设到: $value, 保留现有API Key');
                        },
                        decoration: InputDecoration(
                          labelText: l10n.selectPreset,
                          hintText: l10n.selectPresetHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 连接配置
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud_outlined,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            l10n.connectionConfig(_currentProvider?.name ??
                                _selectedPreset ??
                                l10n.custom),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _apiUrlController,
                        decoration: InputDecoration(
                          labelText: l10n.apiUrlField,
                          hintText: l10n.apiUrlHint,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.link),
                          helperText: l10n.apiUrlHelper,
                        ),
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setState(() {
                          _selectedPreset = null;
                        }),
                        validator: _validateUrl,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _apiKeyController,
                        decoration: InputDecoration(
                          labelText: l10n.apiKeyField,
                          hintText: l10n.apiKeyHint,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            tooltip: _obscureApiKey ? l10n.show : l10n.hide,
                            icon: Icon(
                              _obscureApiKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(() {
                              _obscureApiKey = !_obscureApiKey;
                            }),
                          ),
                        ),
                        obscureText: _obscureApiKey,
                      ),
                    ],
                  ),
                ),
              ),

              // 模型与高级
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tune,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            l10n.modelAndAdvanced,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _modelController,
                        decoration: InputDecoration(
                          labelText: l10n.modelNameField,
                          hintText: _selectedPreset != null &&
                                  _getAiPresets(l10n)
                                      .firstWhere(
                                        (p) => p['name'] == _selectedPreset,
                                      )['model']!
                                      .isEmpty
                              ? l10n.modelNameHint
                              : l10n.modelNameHintDefault,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.psychology),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _hostOverrideController,
                        decoration: InputDecoration(
                          labelText: l10n.hostOverrideField,
                          hintText: l10n.hostOverrideHint,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.dns),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              // 操作按钮（与连接配置/模型设置关联）
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.createNewPreset),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _testConnection,
                      icon: const Icon(Icons.network_check),
                      label: Text(l10n.testConnectionButton),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 将设置项移动到页面底部：AI 卡片生成 & 周期报告洞察使用AI
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.image_outlined,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            l10n.aiCardGeneration,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.aiCardGenerationDesc,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.aiCardGenerationTip,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.orange[600], fontSize: 11),
                      ),
                      const SizedBox(height: 12),
                      Consumer<SettingsService>(
                        builder: (context, settingsService, child) {
                          return SwitchListTile(
                            title: Text(l10n.aiEnhancedGeneration),
                            subtitle: Text(l10n.aiEnhancedGenerationDesc),
                            value: settingsService.aiCardGenerationEnabled,
                            onChanged: (value) {
                              settingsService.setAICardGenerationEnabled(value);
                            },
                            contentPadding: EdgeInsets.zero,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 今日思考使用AI
              Consumer<SettingsService>(
                builder: (context, settingsService, child) {
                  return Card(
                    child: SwitchListTile(
                      title: Text(l10n.todayThoughtsUseAi),
                      subtitle: Text(l10n.todayThoughtsUseAiDesc),
                      value: settingsService.todayThoughtsUseAI,
                      onChanged: (val) async {
                        await settingsService.setTodayThoughtsUseAI(val);
                      },
                      secondary: const Icon(Icons.today),
                    ),
                  );
                },
              ),

              _buildReportInsightSwitch(),
            ],
          ),
        ),
      ),
    );
  }

  // 验证URL格式
  String? _validateUrl(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) {
      return l10n.apiUrlRequired;
    }

    // 基本URL格式验证
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || (!uri.scheme.startsWith('http'))) {
      return l10n.invalidUrl;
    }

    return null;
  }

  // 最大令牌数校验已移除（不再暴露给用户）
}
