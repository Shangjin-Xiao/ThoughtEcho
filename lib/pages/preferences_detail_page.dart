import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../services/biometric_service.dart';
import '../services/clipboard_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import 'ai_settings_page.dart';

/// 二级设置页：整合常用偏好与AI快捷开关
class PreferencesDetailPage extends StatefulWidget {
  const PreferencesDetailPage({super.key});

  @override
  State<PreferencesDetailPage> createState() => _PreferencesDetailPageState();
}

class _PreferencesDetailPageState extends State<PreferencesDetailPage> {
  final BiometricService _biometricService = BiometricService();
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await _biometricService.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsService>();
    final clipboard = context.watch<ClipboardService>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.prefSettingsTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部说明
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tune,
                      color: colorScheme.onPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.personalizationSettings,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.personalizationSettingsDesc,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 常用偏好
            _buildSectionHeader(
              context,
              l10n.commonPreferences,
              Icons.settings_outlined,
            ),
            const SizedBox(height: 12),
            _buildPreferenceCard(
              context,
              children: [
                _buildSwitchTile(
                  context: context,
                  title: l10n.clipboardMonitoring,
                  subtitle: l10n.clipboardMonitoringDesc,
                  icon: Icons.content_paste_outlined,
                  value: clipboard.enableClipboardMonitoring,
                  onChanged: (v) => clipboard.setEnableClipboardMonitoring(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.showFavoriteButton,
                  subtitle: l10n.showFavoriteButtonDesc,
                  icon: Icons.favorite_outline,
                  value: settings.showFavoriteButton,
                  onChanged: (v) => settings.setShowFavoriteButton(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.showExactTime,
                  subtitle: l10n.showExactTimeDesc,
                  icon: Icons.access_time,
                  value: settings.showExactTime,
                  onChanged: (v) => settings.setShowExactTime(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.prioritizeBoldContent,
                  subtitle: l10n.prioritizeBoldContentDesc,
                  icon: Icons.format_bold,
                  value: settings.prioritizeBoldContentInCollapse,
                  onChanged: (v) =>
                      settings.setPrioritizeBoldContentInCollapse(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.useLocalNotesOnly,
                  subtitle: l10n.useLocalNotesOnlyDesc,
                  icon: Icons.offline_bolt_outlined,
                  value: settings.useLocalQuotesOnly,
                  onChanged: (v) => settings.setUseLocalQuotesOnly(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.settingsAutoAttachLocation,
                  subtitle: l10n.settingsAutoAttachLocationDesc,
                  icon: Icons.location_on_outlined,
                  value: settings.autoAttachLocation,
                  onChanged: (v) => settings.setAutoAttachLocation(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.settingsAutoAttachWeather,
                  subtitle: l10n.settingsAutoAttachWeatherDesc,
                  icon: Icons.cloud_outlined,
                  value: settings.autoAttachWeather,
                  onChanged: (v) => settings.setAutoAttachWeather(v),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 笔记默认填充
            _buildSectionHeader(
              context,
              l10n.noteAutoFillSection,
              Icons.edit_note_outlined,
            ),
            const SizedBox(height: 12),
            _buildPreferenceCard(
              context,
              children: [
                _buildTextSettingTile(
                  context: context,
                  title: l10n.defaultAuthor,
                  subtitle: settings.defaultAuthor?.isNotEmpty == true
                      ? settings.defaultAuthor!
                      : l10n.defaultAuthorDesc,
                  icon: Icons.person_outline,
                  currentValue: settings.defaultAuthor,
                  hintText: l10n.defaultAuthorHint,
                  onSave: (value) => settings.setDefaultAuthor(value),
                ),
                _buildDivider(),
                _buildTextSettingTile(
                  context: context,
                  title: l10n.defaultSource,
                  subtitle: settings.defaultSource?.isNotEmpty == true
                      ? settings.defaultSource!
                      : l10n.defaultSourceDesc,
                  icon: Icons.book_outlined,
                  currentValue: settings.defaultSource,
                  hintText: l10n.defaultSourceHint,
                  onSave: (value) => settings.setDefaultSource(value),
                ),
                _buildDivider(),
                _buildTagSettingTile(
                  context: context,
                  settings: settings,
                  l10n: l10n,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // AI 快捷开关
            _buildSectionHeader(
              context,
              l10n.aiSmartFeatures,
              Icons.auto_awesome_outlined,
            ),
            const SizedBox(height: 12),
            _buildPreferenceCard(
              context,
              children: [
                _buildSwitchTile(
                  context: context,
                  title: l10n.aiGenerateDailyPrompt,
                  subtitle: l10n.aiGenerateDailyPromptDesc,
                  icon: Icons.lightbulb_outline,
                  value: settings.todayThoughtsUseAI,
                  onChanged: (v) async => settings.setTodayThoughtsUseAI(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.periodicReportAiInsights,
                  subtitle: l10n.periodicReportAiInsightsDesc,
                  icon: Icons.insights_outlined,
                  value: settings.reportInsightsUseAI,
                  onChanged: (v) async => settings.setReportInsightsUseAI(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: l10n.aiCardGenerationLabel,
                  subtitle: l10n.aiCardGenerationLabelDesc,
                  icon: Icons.image_outlined,
                  value: settings.aiCardGenerationEnabled,
                  onChanged: (v) async =>
                      settings.setAICardGenerationEnabled(v),
                ),
                _buildDivider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: theme.colorScheme.onSecondaryContainer,
                      size: 20,
                    ),
                  ),
                  title: Text(l10n.moreAiSettings),
                  subtitle: Text(l10n.moreAiSettingsDesc),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AISettingsPage()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 隐私与安全
            _buildSectionHeader(
              context,
              l10n.privacyAndSecurity,
              Icons.security_outlined,
            ),
            const SizedBox(height: 12),
            _buildPreferenceCard(
              context,
              children: [
                _buildSwitchTile(
                  context: context,
                  title: l10n.requireBiometricForHidden,
                  subtitle: _biometricAvailable
                      ? l10n.requireBiometricForHiddenDesc
                      : l10n.biometricNotAvailable,
                  icon: Icons.fingerprint,
                  value: settings.requireBiometricForHidden,
                  onChanged: _biometricAvailable
                      ? (v) => _handleBiometricToggle(context, v)
                      : null,
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 处理生物识别验证开关
  Future<void> _handleBiometricToggle(
      BuildContext context, bool enabled) async {
    final settings = context.read<SettingsService>();
    final l10n = AppLocalizations.of(context);

    if (enabled) {
      // 启用前先验证一次，确保用户有能力通过验证
      final authenticated = await _biometricService.authenticate(
        localizedReason: l10n.biometricAuthReason,
      );

      if (authenticated) {
        await settings.setRequireBiometricForHidden(true);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.biometricAuthFailed)),
          );
        }
      }
    } else {
      await settings.setRequireBiometricForHidden(false);
    }
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildPreferenceCard(
    BuildContext context, {
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final theme = Theme.of(context);
    final isEnabled = onChanged != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: value && isEnabled
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: value && isEnabled
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
          color: isEnabled
              ? null
              : theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface
              .withValues(alpha: isEnabled ? 0.7 : 0.4),
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onTap: isEnabled ? () => onChanged(!value) : null,
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, indent: 68, endIndent: 20);
  }

  /// 构建文本设置项（点击弹出编辑对话框）
  Widget _buildTextSettingTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String? currentValue,
    required String hintText,
    required Future<void> Function(String?) onSave,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasValue = currentValue != null && currentValue.isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: hasValue
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: hasValue
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: hasValue
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
          fontWeight: hasValue ? FontWeight.w500 : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      onTap: () => _showTextEditDialog(
        context: context,
        title: title,
        hintText: hintText,
        currentValue: currentValue,
        onSave: onSave,
        l10n: l10n,
      ),
    );
  }

  /// 显示文本编辑对话框
  Future<void> _showTextEditDialog({
    required BuildContext context,
    required String title,
    required String hintText,
    required String? currentValue,
    required Future<void> Function(String?) onSave,
    required AppLocalizations l10n,
  }) async {
    final controller = TextEditingController(text: currentValue ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hintText,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.text = '';
                Navigator.pop(ctx, '');
              },
              child: Text(l10n.clearDefaultValue),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l10n.saveDefaultValue),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await onSave(result.isEmpty ? null : result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isEmpty ? l10n.defaultValueCleared : l10n.defaultValueSaved,
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    controller.dispose();
  }

  /// 构建标签设置项（点击弹出多选对话框）
  Widget _buildTagSettingTile({
    required BuildContext context,
    required SettingsService settings,
    required AppLocalizations l10n,
  }) {
    final theme = Theme.of(context);
    final selectedIds = settings.defaultTagIds;
    final hasValue = selectedIds.isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: hasValue
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.label_outline,
          color: hasValue
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        l10n.defaultTags,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        hasValue
            ? l10n.defaultTagsCount(selectedIds.length)
            : l10n.defaultTagsDesc,
        style: theme.textTheme.bodySmall?.copyWith(
          color: hasValue
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
          fontWeight: hasValue ? FontWeight.w500 : null,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      onTap: () => _showTagSelectionDialog(context, settings, l10n),
    );
  }

  /// 显示标签多选对话框
  Future<void> _showTagSelectionDialog(
    BuildContext context,
    SettingsService settings,
    AppLocalizations l10n,
  ) async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    final categories = await db.getCategories();
    final selectedIds = List<String>.from(settings.defaultTagIds);

    if (!context.mounted) return;

    final result = await showDialog<List<String>?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(l10n.selectDefaultTags),
              content: SizedBox(
                width: double.maxFinite,
                child: categories.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          l10n.defaultTagsNone,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: categories.length,
                        itemBuilder: (_, index) {
                          final tag = categories[index];
                          final isSelected = selectedIds.contains(tag.id);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(tag.name),
                            secondary: tag.iconName != null
                                ? Icon(
                                    _getIconData(tag.iconName!),
                                    size: 20,
                                  )
                                : null,
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selectedIds.add(tag.id);
                                } else {
                                  selectedIds.remove(tag.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx, <String>[]);
                  },
                  child: Text(l10n.clearDefaultValue),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selectedIds),
                  child: Text(l10n.saveDefaultValue),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await settings.setDefaultTagIds(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isEmpty ? l10n.defaultValueCleared : l10n.defaultValueSaved,
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 从图标名称获取 IconData
  IconData _getIconData(String iconName) {
    // 简单映射常用图标
    const iconMap = <String, IconData>{
      'favorite': Icons.favorite,
      'star': Icons.star,
      'bookmark': Icons.bookmark,
      'label': Icons.label,
      'folder': Icons.folder,
      'movie': Icons.movie,
      'music_note': Icons.music_note,
      'book': Icons.book,
      'games': Icons.games,
      'brush': Icons.brush,
      'language': Icons.language,
      'psychology': Icons.psychology,
      'emoji_emotions': Icons.emoji_emotions,
      'auto_stories': Icons.auto_stories,
    };
    return iconMap[iconName] ?? Icons.label_outline;
  }
}
