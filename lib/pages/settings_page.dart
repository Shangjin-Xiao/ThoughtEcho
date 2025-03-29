import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart' show FilePicker, FileType; // 明确导入需要的类
import 'package:path_provider/path_provider.dart';
import 'home_page.dart';
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
  bool _isLoading = false;
  final String _projectUrl = 'https://github.com/Shangjin-Xiao/mind-trace/';

  @override
  void dispose() {
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
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _buildSettingSection('应用设置', [
            _buildSettingItem(
              icon: Icons.language,
              title: '语言',
              subtitle: '简体中文',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('语言设置功能即将上线')),
                );
              },
            ),
            Builder(
              builder: (context) {
                final themeMode = MediaQuery.of(context).platformBrightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light;
                return SwitchListTile(
                  secondary: const Icon(Icons.dark_mode, color: Colors.blue),
                  title: const Text('深色模式'),
                  subtitle: Text(
                    themeMode == ThemeMode.dark ? '已开启' : '已关闭',
                  ),
                  value: themeMode == ThemeMode.dark,
                  onChanged: (value) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('主题切换功能需要额外实现持久化')),
                    );
                  },
                );
              },
            ),
          ]),
          _buildSettingSection('笔记设置', [
            _buildSettingItem(
              icon: Icons.local_offer,
              title: '标签管理',
              subtitle: '管理笔记标签',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TagSettingsPage()),
              ),
            ),
          ]),
          _buildSettingSection('AI 设置', [
            _buildSettingItem(
              icon: Icons.api,
              title: 'API 设置',
              subtitle: '配置 AI 服务',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AISettingsPage()),
              ),
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
          _buildSettingSection('数据管理', [
            _buildSettingItem(
              icon: Icons.backup,
              title: '备份数据',
              subtitle: '导出所有数据到文件',
              onTap: () => _handleExport(),
            ),
            _buildSettingItem(
              icon: Icons.restore,
              title: '恢复数据',
              subtitle: '从备份文件导入数据',
              onTap: () => _handleImport(),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), // 减小上下间距
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14, // 减小字号
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
        ...children,
        const Divider(height: 1), // 减小分割线高度
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
      visualDensity: VisualDensity.compact, // 使用紧凑布局
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4, // 减小垂直间距
      ),
      leading: Icon(icon, color: Colors.blue, size: 20), // 减小图标大小
      title: Text(
        title,
        style: const TextStyle(fontSize: 14), // 减小标题字号
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12), // 减小副标题字号
      ),
      trailing: onTap != null 
        ? const Icon(Icons.chevron_right, size: 18)  // 减小箭头图标大小
        : null,
      onTap: onTap,
    );
  }

  Future<void> _handleExport() async {
    if (!mounted) return;
    final context = this.context;
    
    setState(() => _isLoading = true);
    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final path = await dbService.exportAllData();
      
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('备份成功'),
          content: SelectableText('文件路径:\n$path'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleImport() async {
    if (!mounted) return;
    final context = this.context;
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
      
      if (result == null) return;
      
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认导入'),
          content: const Text('导入数据将清空当前所有数据，确定要继续吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      
      if (confirmed != true || !mounted) return;
      
      setState(() => _isLoading = true);
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      await dbService.importData(result.files.single.path!);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('数据已恢复，重启应用以完成导入'),
          duration: Duration(seconds: 2),
        ),
      );
      
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 2));
      
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}