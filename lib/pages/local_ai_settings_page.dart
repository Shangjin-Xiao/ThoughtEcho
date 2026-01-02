import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/local_ai_settings.dart';
import '../services/ai/cactus_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// 本地 AI 功能设置页面
///
/// 显示并管理所有设备端 AI 功能的开关设置。
///
/// 注意：模型下载/管理仍在迭代中；当前页面的首要目标是恢复原有开关管理能力，
/// 并在用户启用本地AI后尝试初始化本地服务，让语音识别/OCR/语义搜索入口可用。
class LocalAISettingsPage extends StatefulWidget {
  const LocalAISettingsPage({super.key});

  @override
  State<LocalAISettingsPage> createState() => _LocalAISettingsPageState();
}

class _LocalAISettingsPageState extends State<LocalAISettingsPage> {
  bool _isInitializing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsService = Provider.of<SettingsService>(context);
    final localAISettings = settingsService.localAISettings;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: theme.colorScheme.surface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.localAiFeatures),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.secondaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.science_rounded,
                    size: 12,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.localAiFeaturesPreview,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 顶部说明卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer.withOpacity(0.3),
                    theme.colorScheme.secondaryContainer.withOpacity(0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.info_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            l10n.localAiPreviewNote,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isInitializing) ...[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor:
                            theme.colorScheme.primary.withOpacity(0.12),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.onboardingInitializing,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // 主开关卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                side: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: localAISettings.enabled
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primaryContainer.withOpacity(0.5),
                            theme.colorScheme.surface,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: localAISettings.enabled
                          ? theme.colorScheme.primary.withOpacity(0.15)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      localAISettings.enabled
                          ? Icons.psychology_rounded
                          : Icons.psychology_outlined,
                      color: localAISettings.enabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                  ),
                  title: Text(
                    l10n.enableLocalAi,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.enableLocalAiDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                  value: localAISettings.enabled,
                  onChanged: (value) {
                    _updateSettings(
                      settingsService,
                      localAISettings.copyWith(enabled: value),
                    );
                  },
                ),
              ),
            ),
          ),

          // 功能分组
          if (localAISettings.enabled) ...[
            const SizedBox(height: 16),

            // 输入增强组
            _buildFeatureGroup(
              context: context,
              theme: theme,
              title: l10n.localAIInputEnhancement,
              icon: Icons.input_rounded,
              iconColor: Colors.blue,
              children: [
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.mic_rounded,
                  title: l10n.localAISpeechToText,
                  subtitle: l10n.localAISpeechToTextDesc,
                  value: localAISettings.speechToTextEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(speechToTextEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.document_scanner_rounded,
                  title: l10n.localAIOCR,
                  subtitle: l10n.localAIOCRDesc,
                  value: localAISettings.ocrEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(ocrEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.auto_fix_high_rounded,
                  title: l10n.localAICorrection,
                  subtitle: l10n.localAICorrectionDesc,
                  value: localAISettings.aiCorrectionEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(aiCorrectionEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.source_rounded,
                  title: l10n.localAISourceRecognition,
                  subtitle: l10n.localAISourceRecognitionDesc,
                  value: localAISettings.sourceRecognitionEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(sourceRecognitionEnabled: value),
                  ),
                  isLast: true,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 搜索与发现组
            _buildFeatureGroup(
              context: context,
              theme: theme,
              title: l10n.localAISearchDiscovery,
              icon: Icons.explore_rounded,
              iconColor: Colors.purple,
              children: [
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.search_rounded,
                  title: l10n.localAISemanticSearch,
                  subtitle: l10n.localAISemanticSearchDesc,
                  value: localAISettings.aiSearchEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(aiSearchEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.link_rounded,
                  title: l10n.localAIRelatedNotes,
                  subtitle: l10n.localAIRelatedNotesDesc,
                  value: localAISettings.relatedNotesEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(relatedNotesEnabled: value),
                  ),
                  isLast: true,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 内容分析组
            _buildFeatureGroup(
              context: context,
              theme: theme,
              title: l10n.localAIContentAnalysis,
              icon: Icons.analytics_rounded,
              iconColor: Colors.orange,
              children: [
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.label_rounded,
                  title: l10n.smartTags,
                  subtitle: l10n.smartTagsDesc,
                  value: localAISettings.smartTagsEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(smartTagsEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.category_rounded,
                  title: l10n.localAINoteClassification,
                  subtitle: l10n.localAINoteClassificationDesc,
                  value: localAISettings.noteClassificationEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(noteClassificationEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.sentiment_satisfied_rounded,
                  title: l10n.localAIEmotionDetection,
                  subtitle: l10n.localAIEmotionDetectionDesc,
                  value: localAISettings.emotionDetectionEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(emotionDetectionEnabled: value),
                  ),
                  isLast: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 构建功能分组
  Widget _buildFeatureGroup({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              side: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建功能开关项
  Widget _buildFeatureTile({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ),
          title: Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
          value: value,
          onChanged: onChanged,
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 72,
            endIndent: 16,
            color: theme.colorScheme.outline.withOpacity(0.1),
          ),
      ],
    );
  }

  /// 更新设置，并在必要时尝试初始化本地服务
  Future<void> _updateSettings(
    SettingsService service,
    LocalAISettings settings,
  ) async {
    await service.updateLocalAISettings(settings);

    // 启用本地AI后，尽早尝试初始化本地模型服务。
    // 初始化失败不阻塞开关保存，但会给出可诊断提示。
    if (!mounted) return;
    if (!settings.enabled) return;

    // 如果只启用OCR，不强行初始化 Cactus；
    // 语音识别/语义搜索依赖 Cactus。
    final needCactus = settings.speechToTextEnabled ||
        settings.aiSearchEnabled ||
        settings.relatedNotesEnabled;
    if (!needCactus) return;

    final cactus = context.read<CactusService>();
    if (_isInitializing) return;

    setState(() {
      _isInitializing = true;
    });

    try {
      await cactus.ensureInitialized(
        lm: true,
        stt: settings.speechToTextEnabled,
        rag: settings.aiSearchEnabled || settings.relatedNotesEnabled,
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.startFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    }
  }
}
