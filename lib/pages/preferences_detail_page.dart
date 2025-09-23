import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/clipboard_service.dart';
import '../services/settings_service.dart';
import 'ai_settings_page.dart';

/// 二级设置页：整合常用偏好与AI快捷开关
class PreferencesDetailPage extends StatelessWidget {
  const PreferencesDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsService>();
    final clipboard = context.watch<ClipboardService>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('偏好设置'),
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
                          '个性化设置',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '根据您的使用习惯调整应用行为',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.8),
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
            _buildSectionHeader(context, '常用偏好', Icons.settings_outlined),
            const SizedBox(height: 12),
            _buildPreferenceCard(
              context,
              children: [
                _buildSwitchTile(
                  context: context,
                  title: '剪贴板监控',
                  subtitle: '自动检测剪贴板内容并提示添加笔记',
                  icon: Icons.content_paste_outlined,
                  value: clipboard.enableClipboardMonitoring,
                  onChanged: (v) => clipboard.setEnableClipboardMonitoring(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: '显示喜爱按钮',
                  subtitle: '在笔记卡片上显示心形按钮',
                  icon: Icons.favorite_outline,
                  value: settings.showFavoriteButton,
                  onChanged: (v) => settings.setShowFavoriteButton(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: '优先显示加粗内容',
                  subtitle: '折叠时优先显示加粗文字',
                  icon: Icons.format_bold,
                  value: settings.prioritizeBoldContentInCollapse,
                  onChanged: (v) =>
                      settings.setPrioritizeBoldContentInCollapse(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: '仅使用本地笔记',
                  subtitle: '关闭后，无网络时自动使用本地记录',
                  icon: Icons.offline_bolt_outlined,
                  value: settings.useLocalQuotesOnly,
                  onChanged: (v) => settings.setUseLocalQuotesOnly(v),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // AI 快捷开关
            _buildSectionHeader(
                context, 'AI 智能功能', Icons.auto_awesome_outlined),
            const SizedBox(height: 12),
            _buildPreferenceCard(
              context,
              children: [
                _buildSwitchTile(
                  context: context,
                  title: 'AI生成每日提示',
                  subtitle: '主页每日提示使用AI生成',
                  icon: Icons.lightbulb_outline,
                  value: settings.todayThoughtsUseAI,
                  onChanged: (v) async => settings.setTodayThoughtsUseAI(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: '周期报告AI洞察',
                  subtitle: '每周/月报告生成时启用AI洞察',
                  icon: Icons.insights_outlined,
                  value: settings.reportInsightsUseAI,
                  onChanged: (v) async => settings.setReportInsightsUseAI(v),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  context: context,
                  title: 'AI卡片生成',
                  subtitle: '为笔记生成可视化SVG卡片',
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
                  title: const Text('更多AI设置'),
                  subtitle: const Text('配置AI服务商、模型等'),
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

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.primary,
        ),
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

  Widget _buildPreferenceCard(BuildContext context,
      {required List<Widget> children}) {
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
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: value
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: value
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
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onTap: () => onChanged(!value),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      indent: 68,
      endIndent: 20,
    );
  }
}
