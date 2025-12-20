import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/local_ai_settings.dart';
import '../services/settings_service.dart';

/// 本地 AI 功能设置页面
/// 
/// 显示并管理所有设备端 AI 功能的开关设置
class LocalAISettingsPage extends StatefulWidget {
  const LocalAISettingsPage({super.key});

  @override
  State<LocalAISettingsPage> createState() => _LocalAISettingsPageState();
}

class _LocalAISettingsPageState extends State<LocalAISettingsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsService = Provider.of<SettingsService>(context);
    final localAISettings = settingsService.localAISettings;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.localAISettings),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.localAIPreviewBadge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          // 主开关
          SwitchListTile(
            title: Text(l10n.localAIEnabled),
            subtitle: Text(l10n.localAIEnabledDesc),
            value: localAISettings.enabled,
            onChanged: (value) {
              _updateSettings(
                settingsService,
                localAISettings.copyWith(enabled: value),
              );
            },
          ),
          const Divider(),

          // 只有启用后才显示具体功能
          if (localAISettings.enabled) ...[
            // 输入增强组
            _buildSectionHeader(l10n.localAIInputEnhancement, theme),
            SwitchListTile(
              title: Text(l10n.localAISpeechToText),
              subtitle: Text(l10n.localAISpeechToTextDesc),
              value: localAISettings.speechToTextEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(speechToTextEnabled: value),
                );
              },
            ),
            SwitchListTile(
              title: Text(l10n.localAIOCR),
              subtitle: Text(l10n.localAIOCRDesc),
              value: localAISettings.ocrEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(ocrEnabled: value),
                );
              },
            ),
            SwitchListTile(
              title: Text(l10n.localAICorrection),
              subtitle: Text(l10n.localAICorrectionDesc),
              value: localAISettings.aiCorrectionEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(aiCorrectionEnabled: value),
                );
              },
            ),
            SwitchListTile(
              title: Text(l10n.localAISourceRecognition),
              subtitle: Text(l10n.localAISourceRecognitionDesc),
              value: localAISettings.sourceRecognitionEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(sourceRecognitionEnabled: value),
                );
              },
            ),
            const Divider(),

            // 搜索与发现组
            _buildSectionHeader(l10n.localAISearchDiscovery, theme),
            SwitchListTile(
              title: Text(l10n.localAISemanticSearch),
              subtitle: Text(l10n.localAISemanticSearchDesc),
              value: localAISettings.aiSearchEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(aiSearchEnabled: value),
                );
              },
            ),
            SwitchListTile(
              title: Text(l10n.localAIRelatedNotes),
              subtitle: Text(l10n.localAIRelatedNotesDesc),
              value: localAISettings.relatedNotesEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(relatedNotesEnabled: value),
                );
              },
            ),
            const Divider(),

            // 内容分析组
            _buildSectionHeader(l10n.localAIContentAnalysis, theme),
            SwitchListTile(
              title: Text(l10n.localAISmartTags),
              subtitle: Text(l10n.localAISmartTagsDesc),
              value: localAISettings.smartTagsEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(smartTagsEnabled: value),
                );
              },
            ),
            SwitchListTile(
              title: Text(l10n.localAINoteClassification),
              subtitle: Text(l10n.localAINoteClassificationDesc),
              value: localAISettings.noteClassificationEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(noteClassificationEnabled: value),
                );
              },
            ),
            SwitchListTile(
              title: Text(l10n.localAIEmotionDetection),
              subtitle: Text(l10n.localAIEmotionDetectionDesc),
              value: localAISettings.emotionDetectionEnabled,
              onChanged: (value) {
                _updateSettings(
                  settingsService,
                  localAISettings.copyWith(emotionDetectionEnabled: value),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  /// 更新设置
  Future<void> _updateSettings(
    SettingsService service,
    LocalAISettings settings,
  ) async {
    await service.updateLocalAISettings(settings);
  }
}
