import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/ai_provider_settings.dart';
import '../models/ai_task.dart';
import '../models/multi_ai_settings.dart';
import '../services/agent_memory_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/aptabase_helper.dart';
import '../widgets/app_snackbar.dart';
import 'agent_memory/agent_memory_page.dart';
import 'ai_provider_edit_page.dart';
import 'ai_service_config_page.dart';

/// AI 设置主页：聚焦于「AI 服务与模型摘要入口」「AI 功能开关」与「Thoughter 记忆」。
///
/// 服务列表增删改与模型分配细节统一收纳进 [AIServiceConfigPage]，让日常偏好开关
/// 保持清晰呼吸感。
class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  @override
  void initState() {
    super.initState();
    AptabaseHelper.trackPageView('ai_settings');
  }

  Future<void> _openFirstProviderEditor() async {
    final l10n = AppLocalizations.of(context);
    final saved = await Navigator.of(context).push<AIProviderSettings>(
      MaterialPageRoute(
        builder: (_) => const AIProviderEditPage(),
      ),
    );
    if (!mounted || saved == null) return;
    AppSnackBar.success(context, l10n.aiServiceSaved(saved.name));
  }

  Future<void> _openServiceConfigPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const AIServiceConfigPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsService = context.watch<SettingsService>();
    final multiSettings = settingsService.multiAISettings;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildSectionTitle(context, l10n.aiServiceEntrySectionTitle),
          const SizedBox(height: 8),
          if (multiSettings.providers.isEmpty)
            _buildEmptyServiceEntryCard(context, l10n)
          else
            _buildActiveServiceEntryCard(context, l10n, multiSettings),
          const SizedBox(height: 24),
          _buildSectionTitle(context, l10n.aiFeaturesSectionTitle),
          const SizedBox(height: 8),
          _buildFeatureToggles(context, l10n, settingsService),
          const SizedBox(height: 24),
          _buildSectionTitle(context, l10n.agentMemorySectionTitle),
          const SizedBox(height: 8),
          const _AgentMemorySection(),
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

  Widget _buildEmptyServiceEntryCard(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('ai_service_entry_card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openFirstProviderEditor,
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
                  onPressed: _openFirstProviderEditor,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addAiService),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveServiceEntryCard(
    BuildContext context,
    AppLocalizations l10n,
    MultiAISettings multiSettings,
  ) {
    final theme = Theme.of(context);
    final primary = multiSettings.currentProvider;
    final headline = primary != null
        ? l10n.aiTaskExplicitSummary(
            primary.name,
            primary.model.isEmpty ? l10n.noProvider : primary.model,
          )
        : l10n.noProvider;
    final routingSummary = _buildRoutingSummary(l10n, multiSettings);

    return Card(
      key: const ValueKey('ai_service_entry_card'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(
          Icons.auto_awesome_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          headline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            routingSummary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openServiceConfigPage,
      ),
    );
  }

  String _buildRoutingSummary(
    AppLocalizations l10n,
    MultiAISettings multiSettings,
  ) {
    final primary = multiSettings.currentProvider;
    switch (multiSettings.routingMode) {
      case AIRoutingMode.tiered:
        final light = multiSettings.lightProvider;
        if (light != null && light.id != primary?.id) {
          return l10n.aiServiceEntrySummaryTieredLight(light.name);
        }
        return l10n.aiServiceEntrySummaryDefault;
      case AIRoutingMode.custom:
        final customCount = AITask.customDisplayOrder
            .where(
                (task) => multiSettings.explicitProviderForTask(task) != null)
            .length;
        if (customCount > 0) {
          return l10n.aiServiceEntrySummaryCustom(customCount);
        }
        return l10n.aiServiceEntrySummaryDefault;
    }
  }

  /// 功能开关按日常感知与使用频率从高到低排列：
  /// 1. 今日思考使用 AI → 2. 周期报告洞察使用 AI → 3. AI 卡片生成。
  Widget _buildFeatureToggles(
    BuildContext context,
    AppLocalizations l10n,
    SettingsService settingsService,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
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
          const Divider(height: 1),
          SwitchListTile(
            title: Text(l10n.aiCardGeneration),
            subtitle: Text(l10n.aiEnhancedGenerationDesc),
            value: settingsService.aiCardGenerationEnabled,
            onChanged: settingsService.setAICardGenerationEnabled,
            secondary: const Icon(Icons.image_outlined),
          ),
        ],
      ),
    );
  }
}

/// Thoughter 记忆的开关、称呼、查看入口、自动整理与清空入口。
///
/// 排序遵循用户直觉：先改个人相关设置（总开关 → 称呼 → 查看记忆），再设后台自动整理，
/// 最后放置低频不可逆的清空操作。
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
  Future<void> _saveNickname(String value) async {
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
            secondary: const Icon(Icons.history_edu_outlined),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _nicknameController,
              enabled: settingsService.agentMemoryEnabled,
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
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(l10n.agentMemoryManageTitle),
            subtitle: Text(l10n.agentMemoryManageSubtitle),
            trailing: const Icon(Icons.chevron_right),
            enabled: settingsService.agentMemoryEnabled,
            onTap: () {
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (_) => const AgentMemoryPage(),
                ),
              )
                  .then((_) {
                if (mounted) {
                  setState(() {
                    _countsFuture = context.read<AgentMemoryService>().counts();
                  });
                }
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(l10n.dreamingEnableTitle),
            subtitle: Text(l10n.dreamingEnableDesc),
            value: settingsService.dreamingEnabled,
            onChanged:
                settingsService.agentMemoryEnabled ? _setDreamingEnabled : null,
            secondary: const Icon(Icons.auto_awesome_outlined),
          ),
          SwitchListTile(
            title: Text(l10n.dreamingOnIdleTitle),
            subtitle: Text(l10n.dreamingOnIdleDesc),
            value: settingsService.dreamingOnIdleEnabled,
            onChanged: settingsService.agentMemoryEnabled &&
                    settingsService.dreamingEnabled
                ? _setDreamingOnIdleEnabled
                : null,
            secondary: const Icon(Icons.hourglass_empty_outlined),
          ),
          SwitchListTile(
            title: Text(l10n.dreamingAfterInsightTitle),
            subtitle: Text(l10n.dreamingAfterInsightDesc),
            value: settingsService.dreamingAfterInsightEnabled,
            onChanged: settingsService.agentMemoryEnabled &&
                    settingsService.dreamingEnabled
                ? _setDreamingAfterInsightEnabled
                : null,
            secondary: const Icon(Icons.insights_outlined),
          ),
          const Divider(height: 1),
          FutureBuilder<({int profileCount, int factCount})>(
            future: _countsFuture,
            builder: (context, snapshot) {
              final failed = snapshot.hasError;
              final counts = snapshot.data;
              final total =
                  (counts?.profileCount ?? 0) + (counts?.factCount ?? 0);
              final enabled = failed || total > 0;
              final subtitle = failed
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

  Future<void> _setDreamingEnabled(bool value) async {
    final l10n = AppLocalizations.of(context);
    await _setDreamingSetting(
      value,
      context.read<SettingsService>().setDreamingEnabled,
      l10n.dreamingSwitchFailed,
    );
  }

  Future<void> _setDreamingOnIdleEnabled(bool value) async {
    final l10n = AppLocalizations.of(context);
    await _setDreamingSetting(
      value,
      context.read<SettingsService>().setDreamingOnIdleEnabled,
      l10n.dreamingSwitchFailed,
    );
  }

  Future<void> _setDreamingAfterInsightEnabled(bool value) async {
    final l10n = AppLocalizations.of(context);
    await _setDreamingSetting(
      value,
      context.read<SettingsService>().setDreamingAfterInsightEnabled,
      l10n.dreamingSwitchFailed,
    );
  }

  Future<void> _setDreamingSetting(
    bool value,
    Future<void> Function(bool) save,
    String errorMessage,
  ) async {
    try {
      await save(value);
    } catch (error, stack) {
      logError(
        'Dreaming 设置保存失败（value=$value）',
        error: error,
        stackTrace: stack,
        source: 'AISettingsPage',
      );
      if (!mounted) return;
      AppSnackBar.error(context, errorMessage);
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
