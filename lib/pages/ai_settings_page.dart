import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/ai_provider_presets.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/ai_provider_settings.dart';
import '../models/multi_ai_settings.dart';
import '../services/agent_memory_service.dart';
import '../services/api_key_manager.dart';
import '../services/settings_service.dart';
import '../theme/app_semantic_colors.dart';
import '../utils/ai_network_manager.dart';
import '../utils/app_logger.dart';
import '../widgets/app_snackbar.dart';
import 'ai_provider_edit_page.dart';
import 'user_guide_page.dart';
import '../theme/theme_style.dart';

/// AI 设置主页：一个「我的 AI 服务」列表 + 功能开关。
///
/// 这里只负责挑选、排序和管理已保存的配置；新建和编辑都交给
/// [AIProviderEditPage]，所以「保存」到底是新增还是覆盖永远是明确的。
class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  late MultiAISettings _multiSettings;

  /// providerId -> 安全存储里是否已有可用的 Key。
  final Map<String, bool> _hasApiKey = {};
  final Set<String> _testing = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _multiSettings = context.read<SettingsService>().multiAISettings;
    _refreshApiKeyStatus();
  }

  Future<void> _refreshApiKeyStatus() async {
    final apiKeyManager = APIKeyManager();
    final results = <String, bool>{};
    for (final provider in _multiSettings.providers) {
      results[provider.id] =
          await apiKeyManager.hasValidProviderApiKey(provider.id);
    }
    if (!mounted) return;
    setState(() {
      _hasApiKey
        ..clear()
        ..addAll(results);
    });
  }

  AIProviderSettings? get _currentProvider => _multiSettings.currentProvider;

  // --- 动作 ---

  Future<void> _openEditor({
    AIProviderSettings? provider,
    AIProviderPreset? initialPreset,
  }) async {
    final l10n = AppLocalizations.of(context);
    final saved = await Navigator.of(context).push<AIProviderSettings>(
      MaterialPageRoute(
        builder: (_) => AIProviderEditPage(
          provider: provider,
          initialPreset: initialPreset,
        ),
      ),
    );

    if (!mounted) return;
    setState(_reload);
    if (saved != null) {
      AppSnackBar.success(context, l10n.aiServiceSaved(saved.name));
    }
  }

  Future<void> _setCurrent(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    final settingsService = context.read<SettingsService>();
    await settingsService.saveMultiAISettings(
      _multiSettings.copyWith(currentProviderId: provider.id),
    );
    if (!mounted) return;
    setState(_reload);
    AppSnackBar.info(context, l10n.switchedTo(provider.name));
  }

  Future<void> _rename(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: provider.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renamePreset),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.presetName,
            border: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(AppShapeTokens.of(context).inputRadius),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || newName == provider.name) return;
    if (!mounted) return;

    await context.read<SettingsService>().saveMultiAISettings(
          _multiSettings.copyWith(
            providers: _multiSettings.providers
                .map(
                  (p) => p.id == provider.id ? p.copyWith(name: newName) : p,
                )
                .toList(growable: false),
          ),
        );
    if (!mounted) return;
    setState(_reload);
    AppSnackBar.success(context, l10n.presetRenamed(newName));
  }

  Future<void> _delete(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await APIKeyManager().removeProviderApiKey(provider.id);

    final remaining = _multiSettings.providers
        .where((p) => p.id != provider.id)
        .toList(growable: false);
    final nextCurrentId = _multiSettings.currentProviderId == provider.id
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _multiSettings.currentProviderId;

    if (!mounted) return;
    await context.read<SettingsService>().saveMultiAISettings(
          _multiSettings.copyWith(
            providers: remaining,
            currentProviderId: nextCurrentId,
          ),
        );

    if (!mounted) return;
    setState(_reload);
    AppSnackBar.info(context, l10n.presetDeleted(provider.name));
  }

  Future<void> _test(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _testing.add(provider.id));
    try {
      final response = await AINetworkManager.makeRequest(
        url: '',
        data: {
          'messages': [
            {'role': 'system', 'content': l10n.connectionTestSystemMessage},
            {'role': 'user', 'content': l10n.connectionTestUserMessage},
          ],
          'temperature': 0.1,
          'max_tokens': 50,
        },
        provider: provider,
        timeout: const Duration(seconds: 30),
      );

      if (!mounted) return;
      final data = response.data;
      final ok = response.statusCode == 200 &&
          data is Map &&
          data['choices'] is List &&
          (data['choices'] as List).isNotEmpty;
      if (ok) {
        AppSnackBar.success(context, l10n.connectionTestSuccess);
      } else {
        AppSnackBar.error(context, l10n.responseFormatError);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, l10n.connectionTestFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _testing.remove(provider.id));
    }
  }

  void _openUserGuide() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UserGuidePage()),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasProviders = _multiSettings.providers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!hasProviders) ...[
            _buildEmptyState(context),
            const SizedBox(height: 12),
            _buildOllamaCloudTip(context),
          ] else ...[
            _buildSectionTitle(context, l10n.aiServicesSectionTitle),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _multiSettings.providers.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _buildProviderTile(context, _multiSettings.providers[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: Text(l10n.addAiService),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildSectionTitle(context, l10n.aiEnhancedGeneration),
          const SizedBox(height: 8),
          _buildFeatureToggles(context),
          const SizedBox(height: 24),
          _buildSectionTitle(context, l10n.agentMemorySectionTitle),
          const SizedBox(height: 8),
          const _AgentMemorySection(),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _openUserGuide,
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(l10n.aiConfigHelpLink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.aiServiceEmptyTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.aiServiceEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: Text(l10n.addAiService),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 首次配置时把推荐入口摆在明面上，省掉「该选哪家」的决策成本。
  Widget _buildOllamaCloudTip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final preset = AIProviderPresets.recommended;

    return Card(
      color: semantic.successContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_outline, color: semantic.onSuccessContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.ollamaCloudTipTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: semantic.onSuccessContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.ollamaCloudTipBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: semantic.onSuccessContainer,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: () => _openEditor(initialPreset: preset),
                icon: const Icon(Icons.bolt),
                label: Text(l10n.ollamaCloudTipAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderTile(
    BuildContext context,
    AIProviderSettings provider,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isCurrent = provider.id == _currentProvider?.id;
    final isTesting = _testing.contains(provider.id);
    final preset = AIProviderPresets.matchApiUrl(provider.apiUrl);
    final needsKey = preset?.requiresApiKey ?? true;
    final keyOk = (_hasApiKey[provider.id] ?? false) || !needsKey;

    return ListTile(
      leading: Icon(
        isCurrent ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isCurrent ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(provider.name, overflow: TextOverflow.ellipsis),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            _Badge(
              label: l10n.inUseBadge,
              background: theme.colorScheme.primaryContainer,
              foreground: theme.colorScheme.onPrimaryContainer,
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider.model.isEmpty ? l10n.noProvider : provider.model,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                keyOk ? Icons.verified_user_outlined : Icons.error_outline,
                size: 14,
                color: keyOk ? semantic.success : theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Text(
                keyOk ? l10n.statusKeyConfigured : l10n.statusKeyMissing,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: keyOk ? semantic.success : theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: isTesting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<_ProviderAction>(
              onSelected: (action) {
                switch (action) {
                  case _ProviderAction.edit:
                    _openEditor(provider: provider);
                  case _ProviderAction.test:
                    _test(provider);
                  case _ProviderAction.rename:
                    _rename(provider);
                  case _ProviderAction.delete:
                    _delete(provider);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ProviderAction.edit,
                  child: ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(l10n.edit),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _ProviderAction.test,
                  child: ListTile(
                    leading: const Icon(Icons.network_check),
                    title: Text(l10n.testConnectionButton),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _ProviderAction.rename,
                  child: ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: Text(l10n.rename),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _ProviderAction.delete,
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      l10n.delete,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
      onTap: isCurrent
          ? () => _openEditor(provider: provider)
          : () => _setCurrent(provider),
    );
  }

  Widget _buildFeatureToggles(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsService = context.watch<SettingsService>();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(l10n.aiCardGeneration),
            subtitle: Text(l10n.aiEnhancedGenerationDesc),
            value: settingsService.aiCardGenerationEnabled,
            onChanged: settingsService.setAICardGenerationEnabled,
            secondary: const Icon(Icons.image_outlined),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(l10n.todayThoughtsUseAi),
            subtitle: Text(l10n.todayThoughtsUseAiDesc),
            value: settingsService.todayThoughtsUseAI,
            onChanged: settingsService.setTodayThoughtsUseAI,
            secondary: const Icon(Icons.today),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(l10n.reportInsightsUseAi),
            subtitle: Text(l10n.reportInsightsUseAiDesc),
            value: settingsService.reportInsightsUseAI,
            onChanged: settingsService.setReportInsightsUseAI,
            secondary: const Icon(Icons.lightbulb_outline),
          ),
        ],
      ),
    );
  }
}

/// Thoughter 记忆的开关与清空入口。
///
/// 开关和清空刻意是两件事：关开关只是暂时不再读写，随时能开回来；删数据不可逆，
/// 必须显式确认。
///
/// 单独拆成 StatefulWidget 是为了把计数的 Future 存住——放在页面的 build 里，
/// 任何一次重建都会重新发起查询，副标题会闪一下空状态。
class _AgentMemorySection extends StatefulWidget {
  const _AgentMemorySection();

  @override
  State<_AgentMemorySection> createState() => _AgentMemorySectionState();
}

class _AgentMemorySectionState extends State<_AgentMemorySection> {
  Future<({int profileCount, int factCount})>? _countsFuture;
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: Provider.of<SettingsService>(context, listen: false).userNickname,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _countsFuture ??= context.read<AgentMemoryService>().counts();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _refreshCounts() {
    setState(() {
      _countsFuture = context.read<AgentMemoryService>().counts();
    });
  }

  String? _pendingNickname;
  bool _nicknameSaving = false;

  /// 串行保存称呼：击键连续触发，写入期间只保留最新值——较早输入不得在
  /// 较新输入之后落盘把它盖回去；只有最后一次写入失败才提示一次。
  ///
  /// 循环不看 `mounted`：写入途中用户返回上一页时，排队中的最新称呼仍然要落盘，
  /// 否则用户看到的最后一次输入会被之前那次写入盖掉。`mounted` 只用来挡 UI 反馈。
  Future<void> _saveNickname(String value) async {
    // 先取出 service：await 之后再摸 context 可能页面已经销毁。
    final settingsService = context.read<SettingsService>();
    _pendingNickname = value;
    if (_nicknameSaving) {
      return;
    }
    _nicknameSaving = true;
    var failed = false;
    try {
      while (true) {
        final next = _pendingNickname;
        if (next == null) {
          break;
        }
        _pendingNickname = null;
        try {
          await settingsService.setUserNickname(next);
          failed = false;
        } catch (e, stack) {
          failed = true;
          logError(
            '保存用户称呼失败',
            error: e,
            stackTrace: stack,
            source: 'AISettingsPage',
          );
        }
      }
    } finally {
      _nicknameSaving = false;
    }
    if (failed && mounted) {
      AppSnackBar.error(
        context,
        AppLocalizations.of(context).agentMemoryNicknameSaveFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsService = context.watch<SettingsService>();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(l10n.agentMemoryEnableTitle),
            subtitle: Text(l10n.agentMemoryEnableDesc),
            value: settingsService.agentMemoryEnabled,
            onChanged: _setMemoryEnabled,
            // 与首次进入的记忆提示弹窗共用同一个图标，见 agent_memory_notice.dart。
            secondary: const Icon(Icons.history_edu_outlined),
            isThreeLine: true,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _nicknameController,
              // 称呼走的是画像块，记忆关掉就整块不注入。让输入框跟着禁用，
              // 否则用户填了称呼、对话里却一直不用，看上去像坏了。
              enabled: settingsService.agentMemoryEnabled,
              // 与注入侧的上限对齐，避免超长称呼在画像块里被静默截断。
              maxLength: AgentMemoryService.nicknameMaxChars,
              decoration: InputDecoration(
                icon: const Icon(Icons.badge_outlined),
                labelText: l10n.agentMemoryNicknameTitle,
                hintText: l10n.agentMemoryNicknameHint,
                helperText: settingsService.agentMemoryEnabled
                    ? l10n.agentMemoryNicknameDesc
                    : l10n.agentMemoryNicknameDisabled,
                counterText: '',
              ),
              textInputAction: TextInputAction.done,
              onChanged: _saveNickname,
            ),
          ),
          const Divider(height: 1),
          FutureBuilder<({int profileCount, int factCount})>(
            future: _countsFuture,
            builder: (context, snapshot) {
              // 读计数失败不能当成「没有记忆」：那会把清空入口禁用掉，
              // 而库里可能正躺着一堆条目。失败时保持可点，让用户还能清。
              final failed = snapshot.hasError;
              final counts = snapshot.data;
              final total =
                  (counts?.profileCount ?? 0) + (counts?.factCount ?? 0);
              final enabled = failed || total > 0;
              final subtitle = failed
                  // 这里失败的是"读数量"，不是"清空"——复用清空失败的文案会让
                  // 用户以为自己刚删了什么。
                  ? l10n.agentMemoryCountsUnavailable
                  : (counts != null && total > 0
                      ? l10n.agentMemoryClearSummary(
                          counts.profileCount,
                          counts.factCount,
                        )
                      : l10n.agentMemoryClearEmpty);
              return ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(l10n.agentMemoryClearTitle),
                subtitle: Text(subtitle),
                enabled: enabled,
                onTap: enabled ? _confirmClear : null,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _setMemoryEnabled(bool value) async {
    final l10n = AppLocalizations.of(context);
    try {
      await context.read<SettingsService>().setAgentMemoryEnabled(value);
    } catch (e, stack) {
      logError(
        'Thoughter 记忆开关保存失败（value=$value）',
        error: e,
        stackTrace: stack,
        source: 'AISettingsPage',
      );
      if (!mounted) return;
      AppSnackBar.error(context, l10n.agentMemorySwitchFailed);
    }
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context);
    final memoryService = context.read<AgentMemoryService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.agentMemoryClearConfirmTitle),
        content: Text(l10n.agentMemoryClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.agentMemoryClearConfirmAction),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await memoryService.clearAll();
      if (!mounted) return;
      _refreshCounts();
      AppSnackBar.success(context, l10n.agentMemoryCleared);
    } catch (e, stack) {
      logError(
        '清空 Thoughter 记忆失败',
        error: e,
        stackTrace: stack,
        source: 'AISettingsPage',
      );
      if (!mounted) return;
      AppSnackBar.error(context, l10n.agentMemoryClearFailed);
    }
  }
}

enum _ProviderAction { edit, test, rename, delete }

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(AppShapeTokens.of(context).buttonRadius),
      ),
      child: Text(
        label,
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
