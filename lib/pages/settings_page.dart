import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'home_page.dart';
import '../services/database_service.dart';
import 'ai_settings_page.dart';
import 'tag_settings_page.dart';
import 'hitokoto_settings_page.dart';
import 'theme_settings_page.dart';
import '../services/settings_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import 'backup_restore_page.dart';
import '../widgets/city_search_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final String _projectUrl = 'https://github.com/Shangjin-Xiao//';
  final TextEditingController _locationController = TextEditingController();

  @override
  void dispose() {
    _locationController.dispose();
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
  
  // 显示城市搜索对话框
  void _showCitySearchDialog(BuildContext context) {
    final locationService = Provider.of<LocationService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.all(8.0),
          child: CitySearchWidget(
            initialCity: locationService.city,
            onCitySelected: (city) {
              setState(() {
                // 更新位置信息显示
                _locationController.text = locationService.getFormattedLocation();
              });
              
              // 显示成功消息
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已选择城市: ${city.name}')),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final locationService = Provider.of<LocationService>(context);
    final weatherService = Provider.of<WeatherService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 位置和天气设置
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('位置与天气设置'),
                  leading: const Icon(Icons.location_on),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                SwitchListTile(
                  title: const Text('使用位置服务'),
                  subtitle: Text(
                    locationService.hasLocationPermission 
                        ? '已获得位置权限' 
                        : '未获得位置权限',
                    style: TextStyle(
                      fontSize: 12,
                      color: locationService.hasLocationPermission
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                  value: locationService.hasLocationPermission,
                  onChanged: (value) async {
                    if (value) {
                      // 请求位置权限
                      final granted = await locationService.requestLocationPermission();
                      if (granted) {
                        // 获取当前位置
                        final position = await locationService.getCurrentLocation();
                        if (position != null && mounted) {
                          // 更新天气
                          await weatherService.getWeatherData(
                            position.latitude, 
                            position.longitude
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('位置服务已启用')),
                          );
                        }
                      } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法获取位置权限')),
                        );
                      }
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置位置',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      // 城市搜索按钮
                      ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('搜索城市'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          _showCitySearchDialog(context);
                        },
                      ),
                      const SizedBox(height: 16.0),
                      // 手动输入位置（保留原功能）
                      Text(
                        '或手动输入位置',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      TextField(
                        controller: _locationController,
                        decoration: InputDecoration(
                          hintText: '国家,省份,城市,区县 (使用逗号分隔)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12.0, 
                            vertical: 12.0,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: () {
                              final locationString = _locationController.text.trim();
                              if (locationString.isNotEmpty) {
                                locationService.parseLocationString(locationString);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('位置已更新')),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        '当前位置: ${locationService.currentAddress ?? '未设置'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                
                if (locationService.currentAddress != null)
                  ListTile(
                    title: const Text('刷新天气'),
                    subtitle: Text(
                      '${weatherService.currentWeather ?? ""} ${weatherService.temperature ?? ""}',
                      style: TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    leading: Icon(weatherService.getWeatherIconData()),
                    trailing: const Icon(Icons.refresh),
                    onTap: () async {
                      final position = locationService.currentPosition;
                      if (position != null) {
                        await weatherService.getWeatherData(
                          position.latitude, 
                          position.longitude
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('天气已更新')),
                          );
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法获取位置信息')),
                        );
                      }
                    },
                  ),
                
                const SizedBox(height: 8.0),
              ],
            ),
          ),
          
          // 应用设置
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('应用设置'),
                  leading: const Icon(Icons.settings),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                // 主题设置
                ListTile(
                  title: const Text('主题设置'),
                  subtitle: const Text('自定义应用的外观主题'),
                  leading: const Icon(Icons.color_lens_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ThemeSettingsPage(),
                      ),
                    );
                  },
                ),
                // AI设置
                ListTile(
                  title: const Text('AI设置'),
                  subtitle: const Text('配置AI分析功能'),
                  leading: const Icon(Icons.psychology_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AISettingsPage(),
                      ),
                    );
                  },
                ),
                // 一言设置
                ListTile(
                  title: const Text('一言设置'),
                  subtitle: const Text('自定义"每日一言"的类型'),
                  leading: const Icon(Icons.format_quote_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HitokotoSettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          // 内容管理
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
      children: [
                ListTile(
                  title: const Text('内容管理'),
                  leading: const Icon(Icons.category),
                ),
        Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                // 标签管理
                ListTile(
                  title: const Text('标签管理'),
                  subtitle: const Text('添加和编辑标签'),
                  leading: const Icon(Icons.tag),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TagSettingsPage(),
                      ),
                    );
                  },
                ),
                // 备份与恢复
                ListTile(
                  title: const Text('备份与恢复'),
                  subtitle: const Text('备份数据或从备份中恢复'),
                  leading: const Icon(Icons.backup_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackupRestorePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          // 关于信息
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('关于'),
                  leading: const Icon(Icons.info_outline),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: '心记',
                      applicationVersion: '1.0.0',
                      applicationIcon: const FlutterLogo(),
                      applicationLegalese: '© 2023 心记团队\n一款帮助你记录和分析思想的应用',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleExport() async {
    if (!mounted) return;
    final context = this.context;
    
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
    }
  }
}