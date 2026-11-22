import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/ai_provider_presets.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/ai_provider_settings.dart';
import '../models/ai_task.dart';
import '../models/multi_ai_settings.dart';
import '../services/api_key_manager.dart';
import '../services/settings_service.dart';
import '../theme/app_semantic_colors.dart';
import '../theme/theme_style.dart';
import '../utils/ai_connection_tester.dart';
import '../utils/app_logger.dart';
import '../utils/aptabase_helper.dart';
import '../widgets/app_snackbar.dart';
import 'ai_provider_edit_page.dart';
import 'user_guide_page.dart';

/// AI 服务与模型管理页：管理服务列表、主力切换与模型分配策略（基础分配 / 按功能自选）。
class AIServiceConfigPage extends StatefulWidget {
  const AIServiceConfigPage({super.key});

  @override
  State<AIServiceConfigPage> createState() => _AIServiceConfigPageState();
}

class _AIServiceConfigPageState extends State<AIServiceConfigPage> {
  late MultiAISettings _multiSettings;

  /// providerId -> 安全存储里是否已有可用的 Key。
  final Map<String, bool> _hasApiKey = {};
  final Set<String> _testing = {};

  @override
  void initState() {
    super.initState();
    AptabaseHelper.trackPageView('ai_service_config');
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
      results[provider.id] = provider.apiKey.trim().isNotEmpty ||
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
    if (provider.id == _currentProvider?.id) return;
    final l10n = AppLocalizations.of(context);
    final settingsService = context.read<SettingsService>();
    try {
      await settingsService.saveMultiAISettings(
        _multiSettings.copyWith(currentProviderId: provider.id),
      );
    } catch (e, stack) {
      logError(
        '切换主力 AI 服务失败: $e',
        error: e,
        stackTrace: stack,
        source: 'AIServiceConfigPage._setCurrent',
      );
      if (!mounted) return;
      AppSnackBar.error(context, l10n.saveSettingsError(e.toString()));
      return;
    }
    if (!mounted) return;
    setState(_reload);
    AppSnackBar.info(context, l10n.switchedTo(provider.name));
  }

  Future<void> _setRoutingMode(AIRoutingMode mode) async {
    if (mode == _multiSettings.routingMode) return;
    final l10n = AppLocalizations.of(context);
    try {
      await context.read<SettingsService>().saveMultiAISettings(
            _multiSettings.withRoutingMode(mode),
          );
    } catch (e, stack) {
      logError(
        '切换模型分配模式失败: $e',
        error: e,
        stackTrace: stack,
        source: 'AIServiceConfigPage._setRoutingMode',
      );
      if (!mounted) return;
      AppSnackBar.error(context, l10n.saveSettingsError(e.toString()));
      return;
    }

    AptabaseHelper.trackEvent('feature_used', {
      'action': 'ai_routing_mode_select',
      'mode': mode.name,
    });

    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _selectPrimaryProvider() async {
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<AIProviderSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PrimaryProviderPickerSheet(
        title: l10n.aiTierPrimarySelectSheetTitle,
        multiSettings: _multiSettings,
        hasApiKey: _hasApiKey,
        selectedProviderId: _currentProvider?.id,
      ),
    );
    if (selected == null || !mounted) return;
    await _setCurrent(selected);
  }

  Future<void> _selectLightProvider() async {
    final l10n = AppLocalizations.of(context);
    final currentExplicitLightId = _multiSettings.lightProvider?.id;
    final selected = await showModalBottomSheet<_ProviderSlotSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProviderSlotPickerSheet(
        sheetTitle: l10n.aiTierLightSelectSheetTitle,
        followOptionKey: const ValueKey('ai_light_option_primary'),
        followOptionTitle: l10n.aiTierFollowPrimaryOption,
        followOptionSubtitle: _currentProvider != null
            ? l10n.aiTierFollowPrimarySubtitle(
                _currentProvider!.name,
                _currentProvider!.model.isEmpty
                    ? l10n.noProvider
                    : _currentProvider!.model,
              )
            : l10n.aiTierFollowPrimaryUnsetSubtitle,
        optionKeyPrefix: 'ai_light_option_',
        multiSettings: _multiSettings,
        hasApiKey: _hasApiKey,
        selectedExplicitId: currentExplicitLightId,
      ),
    );
    if (selected == null || !mounted) return;

    final nextProviderId = selected.useDefault ? null : selected.providerId;
    if (nextProviderId == _multiSettings.lightProviderId) return;

    try {
      await context.read<SettingsService>().saveMultiAISettings(
            _multiSettings.withLightProvider(nextProviderId),
          );
    } catch (e, stack) {
      logError(
        '保存轻量模型配置失败: $e',
        error: e,
        stackTrace: stack,
        source: 'AIServiceConfigPage._selectLightProvider',
      );
      if (!mounted) return;
      AppSnackBar.error(context, l10n.saveSettingsError(e.toString()));
      return;
    }

    AptabaseHelper.trackEvent('feature_used', {
      'action': 'ai_light_provider_select',
      'uses_primary': nextProviderId == null,
    });

    if (!mounted) return;
    setState(_reload);
    if (nextProviderId == null) {
      AppSnackBar.info(context, l10n.aiTierLightSwitchedToPrimary);
    } else {
      final assigned = _multiSettings.lightProvider;
      if (assigned != null) {
        AppSnackBar.info(
          context,
          l10n.aiTierLightSwitchedToProvider(assigned.name),
        );
      }
    }
  }

  Future<void> _selectProviderForTask(AITask task) async {
    final l10n = AppLocalizations.of(context);
    final currentExplicitId = _multiSettings.explicitProviderIdForTask(task);
    final taskLabel = _taskTitle(l10n, task);
    final selected = await showModalBottomSheet<_ProviderSlotSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProviderSlotPickerSheet(
        sheetTitle: l10n.aiTaskSelectSheetTitle(taskLabel),
        followOptionKey: const ValueKey('ai_task_option_default'),
        followOptionTitle: l10n.aiTaskFollowDefaultOption,
        followOptionSubtitle: _currentProvider != null
            ? l10n.aiTaskFollowDefaultSubtitle(
                _currentProvider!.name,
                _currentProvider!.model.isEmpty
                    ? l10n.noProvider
                    : _currentProvider!.model,
              )
            : l10n.aiTaskFollowDefaultUnsetSubtitle,
        optionKeyPrefix: 'ai_task_option_',
        multiSettings: _multiSettings,
        hasApiKey: _hasApiKey,
        selectedExplicitId: currentExplicitId,
      ),
    );
    if (selected == null || !mounted) return;

    final nextProviderId = selected.useDefault ? null : selected.providerId;
    final persistedProviderId = _multiSettings.taskProviderIds[task];
    if (nextProviderId == persistedProviderId) return;

    try {
      await context.read<SettingsService>().saveMultiAISettings(
            _multiSettings.withTaskProvider(task, nextProviderId),
          );
    } catch (e, stack) {
      logError(
        '保存任务模型配置失败: $e',
        error: e,
        stackTrace: stack,
        source: 'AIServiceConfigPage._selectProviderForTask',
      );
      if (!mounted) return;
      AppSnackBar.error(context, l10n.saveSettingsError(e.toString()));
      return;
    }

    AptabaseHelper.trackEvent('feature_used', {
      'action': 'ai_task_provider_select',
      'task': task.name,
      'uses_default': nextProviderId == null,
    });

    if (!mounted) return;
    setState(_reload);
    if (nextProviderId == null) {
      AppSnackBar.info(context, l10n.aiTaskSwitchedToDefault(taskLabel));
    } else {
      final assigned = _multiSettings.explicitProviderForTask(task);
      if (assigned != null) {
        AppSnackBar.info(
          context,
          l10n.aiTaskSwitchedToProvider(taskLabel, assigned.name),
        );
      }
    }
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

    if (!mounted) return;
    await context.read<SettingsService>().saveMultiAISettings(
          _multiSettings.withoutProvider(provider.id),
        );

    if (!mounted) return;
    setState(_reload);
    AppSnackBar.info(context, l10n.presetDeleted(provider.name));
  }

  Future<void> _test(AIProviderSettings provider) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _testing.add(provider.id));
    try {
      // 只为列表中的已保存配置取密钥，并保留它的已保存地址；tester 不替草稿取密钥。
      final resolved = provider.apiKey.isNotEmpty
          ? provider
          : provider.copyWith(
              apiKey: await APIKeyManager().getProviderApiKey(provider.id),
            );
      await AIConnectionTester.test(
        provider: resolved,
        systemPrompt: l10n.connectionTestSystemMessage,
        userMessage: l10n.connectionTestUserMessage,
      );
      AptabaseHelper.trackEvent('feature_used', {
        'action': 'ai_test_connection',
        'provider_preset':
            AIProviderPresets.matchApiUrl(provider.apiUrl)?.id ?? 'custom',
      });

      if (!mounted) return;
      AppSnackBar.success(context, l10n.connectionTestSuccess);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(
        context,
        l10n.connectionTestFailed(AIConnectionTester.formatError(e, l10n)),
      );
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
    final theme = Theme.of(context);
    final hasProviders = _multiSettings.providers.isNotEmpty;
    final isTieredMode = _multiSettings.routingMode == AIRoutingMode.tiered;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiServiceConfigTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!hasProviders) ...[
            _buildEmptyState(context),
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
            const SizedBox(height: 24),
            _buildSectionTitle(context, l10n.aiModelAllocationSectionTitle),
            const SizedBox(height: 10),
            SegmentedButton<AIRoutingMode>(
              key: const ValueKey('ai_routing_mode_segmented'),
              segments: [
                ButtonSegment<AIRoutingMode>(
                  value: AIRoutingMode.tiered,
                  icon: const Icon(Icons.layers_outlined),
                  label: Text(l10n.aiRoutingModeTiered),
                ),
                ButtonSegment<AIRoutingMode>(
                  value: AIRoutingMode.custom,
                  icon: const Icon(Icons.tune_outlined),
                  label: Text(l10n.aiRoutingModeCustom),
                ),
              ],
              selected: {_multiSettings.routingMode},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  _setRoutingMode(selection.first);
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              isTieredMode
                  ? l10n.aiRoutingTieredDesc
                  : l10n.aiTaskRoutingSectionDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (isTieredMode)
              _buildTieredRoutingCard(context)
            else
              _buildCustomTaskRoutingCard(context),
          ],
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

  Widget _buildProviderTile(
    BuildContext context,
    AIProviderSettings provider,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isCurrent = provider.id == _currentProvider?.id;
    final isTesting = _testing.contains(provider.id);
    final preset = AIProviderPresets.bySlugOrId(provider.providerSlug) ??
        AIProviderPresets.matchApiUrl(provider.apiUrl);
    final needsKey = preset?.requiresApiKey ?? true;
    final keyOk = (_hasApiKey[provider.id] ?? false) || !needsKey;

    final isTieredMode = _multiSettings.routingMode == AIRoutingMode.tiered;
    final isTieredLight = isTieredMode &&
        !isCurrent &&
        _multiSettings.lightProvider?.id == provider.id;
    final assignedTasks = isTieredMode
        ? const <AITask>[]
        : _multiSettings.tasksAssignedTo(provider.id);

    return ListTile(
      key: ValueKey('ai_provider_tile_${provider.id}'),
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
          if (isTieredLight) ...[
            const SizedBox(width: 8),
            _Badge(
              key: ValueKey('provider_light_badge_${provider.id}'),
              label: l10n.lightModelBadge,
              background: theme.colorScheme.secondaryContainer,
              foreground: theme.colorScheme.onSecondaryContainer,
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
          if (assignedTasks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final task in assignedTasks)
                  _Badge(
                    key: ValueKey(
                      'provider_task_badge_${provider.id}_${task.name}',
                    ),
                    label: _taskBadgeLabel(l10n, task),
                    background: theme.colorScheme.secondaryContainer,
                    foreground: theme.colorScheme.onSecondaryContainer,
                  ),
              ],
            ),
          ],
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
          : MenuAnchor(
              builder: (context, controller, child) {
                return IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: l10n.moreOptions,
                  onPressed: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                );
              },
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openEditor(provider: provider),
                  child: Text(l10n.edit),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.network_check),
                  onPressed: () => _test(provider),
                  child: Text(l10n.testConnectionButton),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: () => _rename(provider),
                  child: Text(l10n.rename),
                ),
                MenuItemButton(
                  leadingIcon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _delete(provider),
                  child: Text(
                    l10n.delete,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
      onTap: isCurrent
          ? () => _openEditor(provider: provider)
          : () => _setCurrent(provider),
    );
  }

  Widget _buildTieredRoutingCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final primary = _currentProvider;
    final explicitLight = _multiSettings.lightProvider;
    final hasDistinctLight =
        explicitLight != null && explicitLight.id != primary?.id;

    final String primaryStatus = primary != null
        ? l10n.aiTaskExplicitSummary(
            primary.name,
            primary.model.isEmpty ? l10n.noProvider : primary.model,
          )
        : l10n.noProvider;

    final String lightStatus;
    if (hasDistinctLight) {
      lightStatus = l10n.aiTaskExplicitSummary(
        explicitLight.name,
        explicitLight.model.isEmpty ? l10n.noProvider : explicitLight.model,
      );
    } else if (primary != null) {
      lightStatus = l10n.aiTierFollowingPrimary(primary.name);
    } else {
      lightStatus = l10n.aiTierFollowingPrimaryUnset;
    }

    return Card(
      key: const ValueKey('ai_tiered_routing_card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            key: const ValueKey('ai_tier_primary_tile'),
            leading: Icon(
              Icons.auto_awesome_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.aiTierPrimaryTitle),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  primaryStatus,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aiTierPrimaryTasksHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _selectPrimaryProvider,
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('ai_tier_light_tile'),
            leading: Icon(
              Icons.bolt_outlined,
              color: hasDistinctLight
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(l10n.aiTierLightTitle),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  lightStatus,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasDistinctLight
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aiTierLightTasksHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _selectLightProvider,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTaskRoutingCard(BuildContext context) {
    const orderedTasks = AITask.customDisplayOrder;
    return Card(
      key: const ValueKey('ai_task_routing_card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < orderedTasks.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _buildTaskRoutingTile(context, orderedTasks[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskRoutingTile(BuildContext context, AITask task) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final explicitProvider = _multiSettings.explicitProviderForTask(task);
    final defaultProvider = _currentProvider;

    final String statusText;
    if (explicitProvider != null) {
      final modelLabel = explicitProvider.model.isEmpty
          ? l10n.noProvider
          : explicitProvider.model;
      statusText = l10n.aiTaskExplicitSummary(
        explicitProvider.name,
        modelLabel,
      );
    } else if (defaultProvider != null) {
      statusText = l10n.aiTaskFollowingDefault(defaultProvider.name);
    } else {
      statusText = l10n.aiTaskFollowingDefaultUnset;
    }

    return ListTile(
      key: ValueKey('ai_task_tile_${task.name}'),
      leading: Icon(
        _iconForTask(task),
        color: explicitProvider != null
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(_taskTitle(l10n, task)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            statusText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: explicitProvider != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _taskHint(l10n, task),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _selectProviderForTask(task),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
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

String _taskTitle(AppLocalizations l10n, AITask task) {
  return switch (task) {
    AITask.dailyInsight => l10n.aiTaskDailyInsightTitle,
    AITask.periodicInsight => l10n.aiTaskPeriodicInsightTitle,
    AITask.dreaming => l10n.aiTaskDreamingTitle,
    AITask.agent => l10n.aiTaskAgentTitle,
    AITask.cardGeneration => l10n.aiTaskCardGenerationTitle,
    AITask.sessionTitle => l10n.aiTaskSessionTitleTitle,
  };
}

String _taskBadgeLabel(AppLocalizations l10n, AITask task) {
  return switch (task) {
    AITask.dailyInsight => l10n.aiTaskBadgeDailyInsight,
    AITask.periodicInsight => l10n.aiTaskBadgePeriodicInsight,
    AITask.dreaming => l10n.aiTaskBadgeDreaming,
    AITask.agent => l10n.aiTaskBadgeAgent,
    AITask.cardGeneration => l10n.aiTaskBadgeCardGeneration,
    AITask.sessionTitle => l10n.aiTaskBadgeSessionTitle,
  };
}

String _taskHint(AppLocalizations l10n, AITask task) {
  return switch (task) {
    AITask.dailyInsight => l10n.aiTaskDailyInsightHint,
    AITask.periodicInsight => l10n.aiTaskPeriodicInsightHint,
    AITask.dreaming => l10n.aiTaskDreamingHint,
    AITask.agent => l10n.aiTaskAgentHint,
    AITask.cardGeneration => l10n.aiTaskCardGenerationHint,
    AITask.sessionTitle => l10n.aiTaskSessionTitleHint,
  };
}

IconData _iconForTask(AITask task) {
  return switch (task) {
    AITask.dailyInsight => Icons.wb_sunny_outlined,
    AITask.periodicInsight => Icons.insights_outlined,
    AITask.dreaming => Icons.bedtime_outlined,
    AITask.agent => Icons.chat_bubble_outline,
    AITask.cardGeneration => Icons.image_outlined,
    AITask.sessionTitle => Icons.short_text_outlined,
  };
}

class _ProviderSlotSelection {
  const _ProviderSlotSelection.followDefault()
      : useDefault = true,
        providerId = null;

  const _ProviderSlotSelection.explicit(this.providerId) : useDefault = false;

  final bool useDefault;
  final String? providerId;
}

class _PrimaryProviderPickerSheet extends StatelessWidget {
  const _PrimaryProviderPickerSheet({
    required this.title,
    required this.multiSettings,
    required this.hasApiKey,
    required this.selectedProviderId,
  });

  final String title;
  final MultiAISettings multiSettings;
  final Map<String, bool> hasApiKey;
  final String? selectedProviderId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.76,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            for (final provider in multiSettings.providers)
              _buildProviderOptionTile(
                context: context,
                l10n: l10n,
                theme: theme,
                semantic: semantic,
                provider: provider,
                hasApiKey: hasApiKey,
                isSelected: selectedProviderId == provider.id,
                optionKey: ValueKey('ai_primary_option_${provider.id}'),
                onTap: () => Navigator.pop(context, provider),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderSlotPickerSheet extends StatelessWidget {
  const _ProviderSlotPickerSheet({
    required this.sheetTitle,
    required this.followOptionKey,
    required this.followOptionTitle,
    required this.followOptionSubtitle,
    required this.optionKeyPrefix,
    required this.multiSettings,
    required this.hasApiKey,
    required this.selectedExplicitId,
  });

  final String sheetTitle;
  final Key followOptionKey;
  final String followOptionTitle;
  final String followOptionSubtitle;
  final String optionKeyPrefix;
  final MultiAISettings multiSettings;
  final Map<String, bool> hasApiKey;
  final String? selectedExplicitId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isFollowingDefault = selectedExplicitId == null;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.76,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(sheetTitle, style: theme.textTheme.titleLarge),
            ),
            ListTile(
              key: followOptionKey,
              leading: Icon(
                Icons.sync_alt,
                color: isFollowingDefault ? theme.colorScheme.primary : null,
              ),
              title: Text(followOptionTitle),
              subtitle: Text(followOptionSubtitle),
              trailing: isFollowingDefault
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(
                context,
                const _ProviderSlotSelection.followDefault(),
              ),
            ),
            const Divider(height: 1),
            for (final provider in multiSettings.providers)
              _buildProviderOptionTile(
                context: context,
                l10n: l10n,
                theme: theme,
                semantic: semantic,
                provider: provider,
                hasApiKey: hasApiKey,
                isSelected: selectedExplicitId == provider.id,
                optionKey: ValueKey('$optionKeyPrefix${provider.id}'),
                onTap: () => Navigator.pop(
                  context,
                  _ProviderSlotSelection.explicit(provider.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _buildProviderOptionTile({
  required BuildContext context,
  required AppLocalizations l10n,
  required ThemeData theme,
  required AppSemanticColors semantic,
  required AIProviderSettings provider,
  required Map<String, bool> hasApiKey,
  required bool isSelected,
  required Key optionKey,
  required VoidCallback onTap,
}) {
  final preset = AIProviderPresets.bySlugOrId(provider.providerSlug) ??
      AIProviderPresets.matchApiUrl(provider.apiUrl);
  final needsKey = preset?.requiresApiKey ?? true;
  final keyOk = (hasApiKey[provider.id] ?? false) ||
      provider.apiKey.trim().isNotEmpty ||
      !needsKey;

  return ListTile(
    key: optionKey,
    leading: Icon(
      Icons.dns_outlined,
      color: isSelected ? theme.colorScheme.primary : null,
    ),
    title: Text(
      provider.name,
      overflow: TextOverflow.ellipsis,
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
    trailing:
        isSelected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
    enabled: provider.isEnabled,
    onTap: provider.isEnabled ? onTap : null,
  );
}
