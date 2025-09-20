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
    final settings = context.watch<SettingsService>();
    final clipboard = context.watch<ClipboardService>();

    return Scaffold(
      appBar: AppBar(title: const Text('偏好设置')),
      body: ListView(
        children: [
          // 常用偏好
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('常用偏好', style: theme.textTheme.titleSmall),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('剪贴板监控'),
                  subtitle: const Text('自动检测剪贴板内容并提示添加笔记'),
                  value: clipboard.enableClipboardMonitoring,
                  onChanged: (v) => clipboard.setEnableClipboardMonitoring(v),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('显示喜爱按钮'),
                  subtitle: const Text('在笔记卡片上显示心形按钮，轻触即可表达喜爱并记录次数'),
                  trailing: Switch(
                    value: settings.showFavoriteButton,
                    onChanged: (v) => settings.setShowFavoriteButton(v),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('优先显示加粗内容'),
                  subtitle: const Text('在笔记卡片折叠时优先显示加粗的文字内容'),
                  value: settings.prioritizeBoldContentInCollapse,
                  onChanged: (v) => settings.setPrioritizeBoldContentInCollapse(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('仅使用本地笔记'),
                  subtitle: const Text('关闭后，无网络时自动使用本地记录'),
                  secondary: const Icon(Icons.offline_bolt_outlined),
                  value: settings.useLocalQuotesOnly,
                  onChanged: (v) => settings.setUseLocalQuotesOnly(v),
                ),
              ],
            ),
          ),

          // AI 快捷开关
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('AI 快捷开关', style: theme.textTheme.titleSmall),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('使用AI生成每日提示'),
                  subtitle: const Text('在主页每日提示处使用AI进行生成'),
                  value: settings.todayThoughtsUseAI,
                  onChanged: (v) async => settings.setTodayThoughtsUseAI(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('周期报告洞察使用AI'),
                  subtitle: const Text('每周/月报告生成时启用AI洞察'),
                  value: settings.reportInsightsUseAI,
                  onChanged: (v) async => settings.setReportInsightsUseAI(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('启用AI卡片生成 (SVG)'),
                  subtitle: const Text('为笔记生成可视化SVG卡片'),
                  value: settings.aiCardGenerationEnabled,
                  onChanged: (v) async => settings.setAICardGenerationEnabled(v),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('更多AI设置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AISettingsPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
