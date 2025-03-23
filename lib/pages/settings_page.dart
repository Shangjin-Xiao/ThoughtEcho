import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../models/note_tag.dart';
import '../models/ai_settings.dart';
import 'ai_settings_page.dart';
import 'tag_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _tagController = TextEditingController();
  bool _isLoading = false;
  final String _projectUrl = 'https://github.com/yourusername/mind-trace';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          _buildSettingSection('应用设置', [
            _buildSettingItem(
              icon: Icons.language,
              title: '语言',
              subtitle: '简体中文',
              onTap: () {
                // 暂未实现语言切换功能
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('语言设置功能即将上线')),
                );
              },
            ),
            _buildSettingItem(
              icon: Icons.dark_mode,
              title: '主题',
              subtitle: '跟随系统',
              onTap: () {
                // 暂未实现主题切换功能
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('主题设置功能即将上线')),
                );
              },
            ),
          ]),
          _buildSettingSection('笔记设置', [
            _buildSettingItem(
              icon: Icons.local_offer,
              title: '标签管理',
              subtitle: '管理笔记标签',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TagSettingsPage(),
                  ),
                );
              },
            ),
          ]),
          _buildSettingSection('AI 设置', [
            _buildSettingItem(
              icon: Icons.api,
              title: 'API 设置',
              subtitle: '配置 AI 服务',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AISettingsPage(),
                  ),
                );
              },
            ),
          ]),
          _buildSettingSection('关于', [
            _buildSettingItem(
              icon: Icons.info_outline,
              title: '版本',
              subtitle: 'v1.0.0',
              onTap: null,
            ),
            _buildSettingItem(
              icon: Icons.code,
              title: '项目地址',
              subtitle: 'GitHub',
              onTap: () => _launchUrl(_projectUrl),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSettingSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }


}