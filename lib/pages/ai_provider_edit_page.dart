import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/ai_provider_presets.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/ai_provider_settings.dart';
import '../models/ai_settings.dart';
import '../services/api_key_manager.dart';
import '../services/settings_service.dart';
import '../utils/ai_connection_tester.dart';
import '../utils/ai_endpoint_security.dart';
import '../utils/app_logger.dart';
import '../widgets/app_snackbar.dart';
import '../theme/theme_style.dart';

/// 新建或编辑一个 AI 服务配置。
///
/// [provider] 为 null 表示新建；不为 null 表示编辑该条配置。这个区分是页面的
/// 全部状态来源——设置页不再靠「当前选中的服务商」推断要新建还是覆盖，
/// 那正是过去新建预设总是覆盖旧配置的原因。
///
/// 保存成功后 pop 出保存好的 [AIProviderSettings]，调用方据此刷新列表。
class AIProviderEditPage extends StatefulWidget {
  const AIProviderEditPage({
    super.key,
    this.provider,
    this.initialPreset,
  });

  final AIProviderSettings? provider;

  /// 新建时预选的服务商模板（例如从「一键添加 Ollama 云端」进来）。
  final AIProviderPreset? initialPreset;

  bool get isEditing => provider != null;

  @override
  State<AIProviderEditPage> createState() => _AIProviderEditPageState();
}

class _AIProviderEditPageState extends State<AIProviderEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _hostOverrideController = TextEditingController();

  AIProviderPreset? _preset;

  /// 进入页面时安全存储里已有的 Key，用来判断保存时到底动没动过密钥。
  String _storedApiKey = '';
  bool _obscureApiKey = true;
  bool _isTesting = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    if (provider != null) {
      _nameController.text = provider.name;
      _apiUrlController.text = provider.apiUrl;
      _modelController.text = provider.model;
      _hostOverrideController.text = provider.hostOverride ?? '';
      _preset = AIProviderPresets.matchApiUrl(provider.apiUrl);
      _loadStoredApiKey(provider.id);
    } else {
      _preset = widget.initialPreset;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _hostOverrideController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 模板的展示名依赖 l10n，只有拿到 context 之后才能填表单。
    if (!widget.isEditing && _preset != null && _nameController.text.isEmpty) {
      _applyPreset(_preset!);
    }
  }

  /// 把模板填进表单。名称只在用户没自定义过时才覆盖。
  void _applyPreset(AIProviderPreset preset) {
    final l10n = AppLocalizations.of(context);
    final previousPresetName = _preset?.nameOf(l10n);
    final nameIsUntouched = _nameController.text.trim().isEmpty ||
        _nameController.text.trim() == previousPresetName;

    setState(() {
      _preset = preset;
      _apiUrlController.text = preset.apiUrl;
      _modelController.text = preset.defaultModel;
      if (nameIsUntouched) {
        _nameController.text = preset.nameOf(l10n);
      }
    });
  }

  Future<void> _loadStoredApiKey(String providerId) async {
    final apiKey = await APIKeyManager().getProviderApiKey(providerId);
    if (!mounted) return;
    setState(() {
      _storedApiKey = apiKey;
      _apiKeyController.text = apiKey;
    });
  }

  // --- 校验 ---

  String? _validateUrl(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.apiUrlRequired;
    final uri = Uri.tryParse(value.trim());
    // 判据和运行时那三处**必须是同一条**（[isSecureAiEndpoint]），否则又会出现
    // 「表单放行、发请求时才炸、报错还指不回是哪个设置项」的裂缝——原来这里写的
    // 是 `startsWith('http')`，对 `http` 和 `https` 都成立，正是那道裂缝。
    //
    // 校验属于输入这一层：在能解释、能指着输入框说话的地方拦住它。
    if (uri == null || !uri.hasScheme || !isSecureAiEndpoint(uri)) {
      return l10n.invalidUrl;
    }
    return null;
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppLocalizations.of(context).fieldRequired;
    }
    return null;
  }

  // --- 动作 ---

  /// 用表单当前内容拼一个临时配置，供「测试连接」使用。
  ///
  /// 这里显式带上输入框里的 Key，[AINetworkManager] 会优先用它，因此不需要
  /// 先保存就能测。
  AIProviderSettings _buildDraftProvider() {
    final base = widget.provider;
    return AIProviderSettings(
      id: base?.id ?? 'draft_provider',
      name: _nameController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      apiUrl: _apiUrlController.text.trim(),
      model: _modelController.text.trim(),
      temperature: base?.temperature ?? 0.7,
      maxTokens: base?.maxTokens ?? 32000,
      hostOverride: _hostOverrideController.text.trim().isEmpty
          ? null
          : _hostOverrideController.text.trim(),
      enableThinking: base?.enableThinking,
    );
  }

  Future<void> _testConnection() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) {
      AppSnackBar.error(context, l10n.fixFormErrors);
      return;
    }

    setState(() => _isTesting = true);
    try {
      // 走和真正聊天完全相同的链路，测试结论才等于实际可用性。请求正常返回即算
      // 通过：正文可能是空的（思考模型会把预算花在推理上），但能走到这一步就说明
      // URL、密钥和模型三样都对。
      await AIConnectionTester.test(
        provider: _buildDraftProvider(),
        systemPrompt: l10n.connectionTestSystemMessage,
        userMessage: l10n.connectionTestUserMessage,
      );

      if (!mounted) return;
      AppSnackBar.success(context, l10n.connectionTestSuccess);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, l10n.connectionTestFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) {
      AppSnackBar.error(context, l10n.fixFormErrors);
      return;
    }

    setState(() => _isSaving = true);
    final settingsService = context.read<SettingsService>();
    final navigator = Navigator.of(context);

    try {
      final existing = widget.provider;
      final providerId =
          existing?.id ?? 'provider_${DateTime.now().millisecondsSinceEpoch}';
      final enteredApiKey = _apiKeyController.text.trim();

      // 只在密钥真的变了的时候碰安全存储：没改过就别写，省得在存储不可用的
      // 设备上把整条配置的保存一起拖垮。
      if (enteredApiKey != _storedApiKey) {
        final apiKeyManager = APIKeyManager();
        if (enteredApiKey.isNotEmpty) {
          await apiKeyManager.saveProviderApiKey(providerId, enteredApiKey);
        } else {
          // 用户清空了输入框，视为主动删除密钥。
          await apiKeyManager.removeProviderApiKey(providerId);
        }
        _storedApiKey = enteredApiKey;
      }

      final requiresApiKey = _preset?.requiresApiKey ?? true;
      final saved = AIProviderSettings(
        id: providerId,
        name: _nameController.text.trim(),
        apiUrl: _apiUrlController.text.trim(),
        model: _modelController.text.trim(),
        temperature: existing?.temperature ?? 0.7,
        maxTokens: existing?.maxTokens ?? 32000,
        hostOverride: _hostOverrideController.text.trim().isEmpty
            ? null
            : _hostOverrideController.text.trim(),
        isEnabled: enteredApiKey.isNotEmpty || !requiresApiKey,
        enableThinking: existing?.enableThinking,
      );

      final multiSettings = settingsService.multiAISettings;
      final providers = existing == null
          ? [...multiSettings.providers, saved]
          : multiSettings.providers
              .map((p) => p.id == saved.id ? saved : p)
              .toList(growable: false);

      await settingsService.saveMultiAISettings(
        multiSettings.copyWith(
          providers: providers,
          currentProviderId: saved.id,
        ),
      );

      // 旧版单配置字段仍被部分调用方读取，保持同步。
      await settingsService.updateAISettings(
        AISettings(
          model: saved.model,
          apiUrl: saved.apiUrl,
          apiKey: '',
          maxTokens: saved.maxTokens,
          hostOverride: saved.hostOverride,
        ),
      );

      if (!mounted) return;
      navigator.pop(saved);
    } catch (e) {
      logError(
        '保存 AI 服务配置失败: $e',
        error: e,
        source: 'AIProviderEditPage._save',
      );
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackBar.error(context, l10n.saveSettingsError(e.toString()));
    }
  }

  Future<void> _openConsole(String url) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!opened && mounted) {
      AppSnackBar.error(context, l10n.openLinkFailed);
    }
  }

  Future<void> _pickPreset() async {
    final selected = await showModalBottomSheet<AIProviderPreset>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PresetPickerSheet(selectedId: _preset?.id),
    );
    if (selected != null && mounted) {
      _applyPreset(selected);
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final busy = _isSaving || _isTesting;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? l10n.editAiServiceTitle : l10n.newAiServiceTitle,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildPresetCard(context),
            const SizedBox(height: 12),
            _buildConnectionCard(context),
            const SizedBox(height: 12),
            _buildAdvancedCard(context),
            const SizedBox(height: 8),
            Text(
              l10n.testBeforeSaveHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(l10n.testConnectionButton),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preset = _preset;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          preset == null ? Icons.help_outline : _iconForKind(preset.kind),
          color: theme.colorScheme.primary,
        ),
        title: Text(
          preset?.nameOf(l10n) ?? l10n.selectProviderTemplate,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: preset == null
            ? null
            : Text(preset.descriptionOf(l10n),
                maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: TextButton(
          onPressed: _pickPreset,
          child: Text(
            preset == null
                ? l10n.selectProviderTemplate
                : l10n.changeProviderTemplate,
          ),
        ),
        onTap: _pickPreset,
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preset = _preset;
    final border = OutlineInputBorder(
      borderRadius:
          BorderRadius.circular(AppShapeTokens.of(context).inputRadius),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.configNameField,
                border: border,
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
              validator: _validateRequired,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiUrlController,
              decoration: InputDecoration(
                labelText: l10n.apiUrlField,
                hintText: l10n.apiUrlHint,
                helperText: l10n.apiUrlHelper,
                helperMaxLines: 2,
                border: border,
                prefixIcon: const Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              validator: _validateUrl,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: l10n.apiKeyField,
                hintText: l10n.apiKeyHint,
                helperText: preset != null && !preset.requiresApiKey
                    ? l10n.apiKeyNotNeededHint
                    : null,
                helperMaxLines: 2,
                border: border,
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureApiKey = !_obscureApiKey),
                  tooltip: _obscureApiKey ? l10n.show : l10n.hide,
                ),
              ),
            ),
            if (preset?.consoleUrl != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _openConsole(preset!.consoleUrl!),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(l10n.getApiKeyLink),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: l10n.modelNameField,
                border: border,
                prefixIcon: const Icon(Icons.psychology),
              ),
              validator: _validateRequired,
            ),
            if (preset != null && preset.suggestedModels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.suggestedModelsLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: preset.suggestedModels.map((model) {
                  return ActionChip(
                    label: Text(model),
                    onPressed: () =>
                        setState(() => _modelController.text = model),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(l10n.advancedOptions),
        leading: const Icon(Icons.tune),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _hostOverrideController,
            decoration: InputDecoration(
              labelText: l10n.hostOverrideField,
              hintText: l10n.hostOverrideHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                    AppShapeTokens.of(context).inputRadius),
              ),
              prefixIcon: const Icon(Icons.dns),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForKind(AIPresetKind kind) {
  switch (kind) {
    case AIPresetKind.cloud:
      return Icons.cloud_outlined;
    case AIPresetKind.local:
      return Icons.computer_outlined;
    case AIPresetKind.custom:
      return Icons.tune;
  }
}

/// 分组展示内置服务商模板的选择面板。
class _PresetPickerSheet extends StatelessWidget {
  const _PresetPickerSheet({this.selectedId});

  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.selectProviderTemplate,
                style: theme.textTheme.titleLarge,
              ),
            ),
            for (final kind in AIPresetKind.values) ...[
              _buildGroupHeader(context, kind),
              ...AIProviderPresets.ofKind(kind).map(
                (preset) => _buildPresetTile(context, preset),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGroupHeader(BuildContext context, AIPresetKind kind) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = switch (kind) {
      AIPresetKind.cloud => l10n.providerGroupCloud,
      AIPresetKind.local => l10n.providerGroupLocal,
      AIPresetKind.custom => l10n.providerGroupCustom,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildPresetTile(BuildContext context, AIProviderPreset preset) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isSelected = preset.id == selectedId;

    return ListTile(
      leading: Icon(
        _iconForKind(preset.kind),
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(preset.nameOf(l10n))),
          if (preset.recommended) ...[
            const SizedBox(width: 8),
            _RecommendedBadge(label: l10n.recommendedBadge),
          ],
        ],
      ),
      subtitle: Text(preset.descriptionOf(l10n)),
      trailing: isSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () => Navigator.pop(context, preset),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius:
            BorderRadius.circular(AppShapeTokens.of(context).buttonRadius),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
