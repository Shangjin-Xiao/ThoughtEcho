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
  final _formKey = GlobalKey<FormState>();
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  // Max tokens is internal, not exposed to user anymore
  final _maxTokensController = TextEditingController(text: '32000');
  String? _hostOverride;
  final _hostOverrideController = TextEditingController();

  late MultiAISettings _multiSettings;
  AIProviderSettings? _currentProvider;
  final Map<String, bool> _testingStatus = {};
  final Map<String, String?> _testResults = {};

  String _apiKeyStatus = '';
  bool _isCheckingApiKey = false;
  bool _obscureApiKey = true;

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

  // --- Logic Methods (Preserved) ---

  Future<void> _loadApiKeyAsync() async {
    if (_currentProvider != null) {
      final apiKeyManager = APIKeyManager();
      logDebug('Loading API key for provider: ${_currentProvider!.id}');
      final apiKey =
          await apiKeyManager.getProviderApiKey(_currentProvider!.id);
      if (mounted) {
        setState(() {
          _apiKeyController.text = apiKey;
        });
      }
    }
  }

  void _loadMultiSettings() {
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    _multiSettings = settingsService.multiAISettings;
    _currentProvider = _multiSettings.currentProvider;
    _updateApiKeyStatus();
    _updateApiKeyStatusAsync();
  }

  void _updateApiKeyStatus() {
    final l10n = AppLocalizations.of(context);
    if (_currentProvider != null) {
      _apiKeyStatus = l10n.verifyingApiKey;
    } else {
      _apiKeyStatus = l10n.noProviderSelected;
    }
  }

  Future<void> _updateApiKeyStatusAsync() async {
    final l10n = AppLocalizations.of(context);
    if (_currentProvider != null) {
      final apiKeyManager = APIKeyManager();
      final hasValidKey =
          await apiKeyManager.hasValidProviderApiKey(_currentProvider!.id);
      if (hasValidKey) {
        final secureApiKey =
            await apiKeyManager.getProviderApiKey(_currentProvider!.id);
        _apiKeyStatus = l10n.apiKeyValid(secureApiKey.length);
      } else {
        _apiKeyStatus = l10n.apiKeyInvalid;
      }
    } else {
      _apiKeyStatus = l10n.noProviderSelected;
    }
    if (mounted) setState(() {});
  }

  Future<void> _checkApiKeyStatus() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isCheckingApiKey = true);

    try {
      final settingsService =
          Provider.of<SettingsService>(context, listen: false);
      final multiSettings = settingsService.multiAISettings;
      String statusMessage;

      if (multiSettings.currentProvider == null) {
        statusMessage = l10n.noAiProviderSelected;
      } else {
        final provider = multiSettings.currentProvider!;
        if (!provider.isEnabled) {
          statusMessage = l10n.providerDisabled;
        } else {
          final apiKeyManager = APIKeyManager();
          final hasValidKey =
              await apiKeyManager.hasValidProviderApiKey(provider.id);
          statusMessage =
              hasValidKey ? l10n.apiKeyVerified : l10n.apiKeyInvalid;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.apiKeyStatusCheck(statusMessage)),
            duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.checkFailed(e.toString())),
          backgroundColor: Colors.red,
          duration: AppConstants.snackBarDurationError,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCheckingApiKey = false);
    }
  }

  Future<void> _loadSettings() async {
    final l10n = AppLocalizations.of(context);
    try {
      _loadMultiSettings();
      if (!mounted) return;

      setState(() {
        if (_currentProvider != null) {
          _modelController.text = _currentProvider!.model;
          _apiUrlController.text = _currentProvider!.apiUrl;
          _apiKeyController.text = ''; // API Key loaded asynchronously
          _maxTokensController.text = _currentProvider!.maxTokens.toString();
          _hostOverride = _currentProvider!.hostOverride;
          _hostOverrideController.text = _hostOverride ?? '';
          _loadApiKeyAsync();

          try {
            _selectedPreset = _getAiPresets(l10n).firstWhere(
              (p) => p['apiUrl'] == _apiUrlController.text,
            )['name'];
          } catch (_) {
            _selectedPreset = null;
          }
        } else {
          _modelController.text = '';
          _apiUrlController.text = '';
          _apiKeyController.text = '';
          _maxTokensController.text = '32000';
          _hostOverride = null;
          _hostOverrideController.text = '';
          _selectedPreset = null;
        }
      });
    } catch (e) {
      logError(l10n.loadAiSettingsError(e.toString()),
          error: e, source: 'AISettingsPage._loadSettings');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.loadAiSettingsErrorUser),
          backgroundColor: Colors.red,
          action: SnackBarAction(
              label: l10n.retry,
              textColor: Colors.white,
              onPressed: () => _loadSettings()),
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.fixFormErrors), backgroundColor: Colors.red),
      );
      return;
    }

    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    int maxTokens = 32000;

    try {
      await _createOrUpdateProvider(
        maxTokens,
        _hostOverrideController.text.trim(),
        settingsService,
      );

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(l10n.presetCreated), backgroundColor: Colors.green),
      );
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(l10n.saveSettingsError(e.toString())),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createOrUpdateProvider(
    int maxTokens,
    String hostOverride,
    SettingsService settingsService,
  ) async {
    final l10n = AppLocalizations.of(context);
    String providerName = _selectedPreset ?? l10n.customConfig;

    if (providerName == l10n.customConfig) {
      final uri = Uri.tryParse(_apiUrlController.text);
      if (uri != null && uri.host.isNotEmpty) {
        providerName = l10n.customConfigHost(uri.host);
      } else {
        providerName = l10n.customConfigTimestamp(
            DateTime.now().millisecondsSinceEpoch.toString());
      }
    }

    final newProvider = AIProviderSettings(
      id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      name: providerName,
      apiKey: '',
      apiUrl: _apiUrlController.text,
      model: _modelController.text,
      maxTokens: maxTokens,
      hostOverride: hostOverride.isEmpty ? null : hostOverride,
      isEnabled: _apiKeyController.text.isNotEmpty,
    );

    final apiKeyManager = APIKeyManager();
    await ApiKeyDebugger.debugApiKeySave(
        newProvider.id, _apiKeyController.text);
    await apiKeyManager.saveProviderApiKey(
        newProvider.id, _apiKeyController.text);

    final updatedProviders = [..._multiSettings.providers, newProvider];
    final updatedMultiSettings = _multiSettings.copyWith(
      providers: updatedProviders,
      currentProviderId: newProvider.id,
    );

    await settingsService.saveMultiAISettings(updatedMultiSettings);

    _multiSettings = updatedMultiSettings;
    _currentProvider = newProvider;

    await _updateApiKeyStatusAsync();
    await ApiKeyDebugger.debugApiKeyLifecycle(settingsService);

    await settingsService.updateAISettings(
      AISettings(
        model: _modelController.text,
        apiUrl: _apiUrlController.text,
        apiKey: '',
        maxTokens: maxTokens,
        hostOverride: hostOverride.isEmpty ? null : hostOverride,
      ),
    );
  }

  Future<void> _testConnection() async {
    final l10n = AppLocalizations.of(context);
    await _saveSettings();

    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(l10n.testingConnection),
            ],
          ),
        ),
      );

      if (_currentProvider != null) {
        await _testProvider(_currentProvider!);
      } else {
        final aiService = Provider.of<AIService>(context, listen: false);
        await aiService.testConnection();
      }

      if (!mounted) return;
      navigator.pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(l10n.connectionTestSuccess),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(l10n.connectionTestFailed(e.toString())),
            backgroundColor: Colors.red),
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
      final testMessages = [
        {'role': 'system', 'content': l10n.connectionTestSystemMessage},
        {'role': 'user', 'content': l10n.connectionTestUserMessage},
      ];
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
          setState(() => _testResults[provider.id] = l10n.connectionSuccess);
        } else {
          setState(() => _testResults[provider.id] = l10n.responseFormatError);
        }
      } else {
        setState(() => _testResults[provider.id] =
            l10n.connectionFailed(response.statusCode ?? 0));
      }
    } catch (e) {
      setState(() =>
          _testResults[provider.id] = l10n.connectionTestFailed(e.toString()));
      rethrow;
    } finally {
      setState(() => _testingStatus[provider.id] = false);
    }
  }

  void _setCurrentProvider(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _multiSettings = _multiSettings.copyWith(currentProviderId: provider.id);
      _currentProvider = provider;
    });

    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    await settingsService.saveMultiAISettings(_multiSettings);

    if (provider.apiKey.isNotEmpty) {
      final apiKeyManager = APIKeyManager();
      await apiKeyManager.saveProviderApiKey(provider.id, provider.apiKey);
    }

    setState(() {
      _apiUrlController.text = provider.apiUrl;
      _apiKeyController.text = provider.apiKey;
      _modelController.text = provider.model;
      _maxTokensController.text = provider.maxTokens.toString();
      _hostOverrideController.text = provider.hostOverride ?? '';
    });

    await _updateApiKeyStatusAsync();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.switchedTo(provider.name))),
    );
  }

  Future<void> _renameProvider(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final nameController = TextEditingController(text: provider.name);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renamePreset),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
              labelText: l10n.presetName, border: const OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, nameController.text.trim()),
              child: Text(l10n.confirm)),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != provider.name) {
      final updatedProviders = _multiSettings.providers.map((p) {
        return p.id == provider.id ? p.copyWith(name: result) : p;
      }).toList();

      final updatedMultiSettings =
          _multiSettings.copyWith(providers: updatedProviders);
      await settingsService.saveMultiAISettings(updatedMultiSettings);

      if (!mounted) return;
      setState(() {
        _multiSettings = updatedMultiSettings;
        if (_currentProvider?.id == provider.id) {
          _currentProvider = updatedMultiSettings.currentProvider;
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.presetRenamed(result))));
    }
    nameController.dispose();
  }

  Future<void> _deleteProvider(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePreset),
        content: Text(l10n.deletePresetConfirm(provider.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.presetDeleted(provider.name))));
    }
  }

  String? _validateUrl(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) return l10n.apiUrlRequired;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || (!uri.scheme.startsWith('http')))
      return l10n.invalidUrl;
    return null;
  }

  // --- UI Methods (Refactored) ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettingsTitle)),
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_currentProvider != null) ...[
                    _buildSectionTitle(
                        context,
                        l10n
                            .currentProvider(_currentProvider!.name)
                            .split(':')[0]),
                    const SizedBox(height: 8),
                    _buildActiveProviderCard(context),
                    const SizedBox(height: 24),
                  ],
                  _buildSectionTitle(context,
                      l10n.savedPresets(_multiSettings.providers.length)),
                  const SizedBox(height: 8),
                  _buildSavedProvidersList(context),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context, l10n.connectionConfig('')),
                  const SizedBox(height: 8),
                  _buildConfigForm(context),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context,
                      l10n.aiEnhancedGeneration), // Use generic title for features
                  const SizedBox(height: 8),
                  _buildFeatureToggles(context),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildActiveProviderCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
      color: theme.colorScheme.primaryContainer.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentProvider!.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: _isCheckingApiKey ? null : _checkApiKeyStatus,
                  icon: _isCheckingApiKey
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  tooltip: l10n.checkApiKeyStatus,
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow(context, Icons.link,
                l10n.apiUrlLabel(_currentProvider!.apiUrl)),
            const SizedBox(height: 4),
            _buildInfoRow(context, Icons.psychology,
                l10n.modelLabel(_currentProvider!.model)),
            const SizedBox(height: 4),
            _buildInfoRow(
              context,
              Icons.vpn_key,
              l10n.apiKeyLabel(_apiKeyStatus),
              color: _apiKeyStatus.contains('有效') ||
                      _apiKeyStatus.contains('valid')
                  ? Colors.green
                  : Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text,
      {Color? color}) {
    return Row(
      children: [
        Icon(icon,
            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSavedProvidersList(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_multiSettings.providers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(child: Text(l10n.noPresetsSaved)),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(l10n.savedPresets(_multiSettings.providers.length)),
        leading: const Icon(Icons.list),
        children: _multiSettings.providers.map((provider) {
          final isCurrent = provider.id == _currentProvider?.id;
          final isTesting = _testingStatus[provider.id] ?? false;

          return ListTile(
            leading: Icon(
              isCurrent
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isCurrent ? Theme.of(context).colorScheme.primary : null,
            ),
            title: Text(provider.name),
            subtitle: Text(provider.model),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _renameProvider(provider),
                  tooltip: l10n.rename,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () => _deleteProvider(provider),
                  tooltip: l10n.delete,
                  color: Colors.red,
                ),
                if (isTesting)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    icon: const Icon(Icons.network_check, size: 20),
                    onPressed: () => _testProvider(provider),
                    tooltip: l10n.testConnectionButton,
                  ),
              ],
            ),
            onTap: !isCurrent ? () => _setCurrentProvider(provider) : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildConfigForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // Preset Dropdown
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedPreset,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.selectPreset,
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.auto_awesome),
              ),
              items: _getAiPresets(l10n).map((preset) {
                return DropdownMenuItem(
                  value: preset['name'],
                  child: Text(preset['name']!),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedPreset = value;
                  final preset =
                      _getAiPresets(l10n).firstWhere((p) => p['name'] == value);
                  _apiUrlController.text = preset['apiUrl']!;
                  _modelController.text = preset['model']!;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Connection Details
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
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
                  onChanged: (_) => setState(() => _selectedPreset = null),
                  validator: _validateUrl,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: l10n.apiKeyField,
                    hintText: l10n.apiKeyHint,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureApiKey
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                  obscureText: _obscureApiKey,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Model & Advanced
        Card(
          child: ExpansionTile(
            title: Text(l10n.modelAndAdvanced),
            leading: const Icon(Icons.tune),
            childrenPadding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: l10n.modelNameField,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.psychology),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hostOverrideController,
                decoration: InputDecoration(
                  labelText: l10n.hostOverrideField,
                  hintText: l10n.hostOverrideHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.dns),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Actions
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: Text(l10n.createNewPreset),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.network_check),
                label: Text(l10n.testConnectionButton),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureToggles(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsService = Provider.of<SettingsService>(context);

    return Column(
      children: [
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(l10n.aiCardGeneration),
                subtitle: Text(l10n.aiEnhancedGenerationDesc),
                value: settingsService.aiCardGenerationEnabled,
                onChanged: (val) =>
                    settingsService.setAICardGenerationEnabled(val),
                secondary: const Icon(Icons.image_outlined),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: Text(l10n.todayThoughtsUseAi),
                subtitle: Text(l10n.todayThoughtsUseAiDesc),
                value: settingsService.todayThoughtsUseAI,
                onChanged: (val) => settingsService.setTodayThoughtsUseAI(val),
                secondary: const Icon(Icons.today),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: Text(l10n.reportInsightsUseAi),
                subtitle: Text(l10n.reportInsightsUseAiDesc),
                value: settingsService.reportInsightsUseAI,
                onChanged: (val) => settingsService.setReportInsightsUseAI(val),
                secondary: const Icon(Icons.lightbulb_outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
