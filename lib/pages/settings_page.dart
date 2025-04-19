import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';
import 'package:geolocator/geolocator.dart'; // 确保导入 geolocator
import '../services/database_service.dart';
import 'ai_settings_page.dart';
import 'tag_settings_page.dart';
import 'hitokoto_settings_page.dart';
import 'theme_settings_page.dart';
import '../services/location_service.dart'; // 包含 CityInfo 定义
import '../services/weather_service.dart';
import 'backup_restore_page.dart';
import '../widgets/city_search_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // --- 定义链接地址 ---
  final String _projectUrl = 'https://github.com/Shangjin-Xiao/ThoughtEcho';
  final String _websiteUrl = 'https://echo.shangjinyun.cn/';
  // --- 链接地址结束 ---
  final TextEditingController _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 初始化位置控制器
    _initLocationController();
  }

  void _initLocationController() {
     // 延迟初始化，确保 Provider 可用
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (mounted) {
         final locationService = Provider.of<LocationService>(context, listen: false);
         _locationController.text = locationService.getFormattedLocation();
       }
     });
   }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  // --- 辅助函数：启动 URL ---
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接: $url')),
      );
    }
  }
  // --- 启动 URL 辅助函数结束 ---

  // 显示城市搜索对话框
  void _showCitySearchDialog(BuildContext context) {
    // listen: false 因为我们只调用方法，不监听变化
    final locationService = Provider.of<LocationService>(context, listen: false);
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.all(8.0),
          child: CitySearchWidget(
            initialCity: locationService.city,
            onCitySelected: (cityInfo) async {
              locationService.setSelectedCity(cityInfo);

              final position = locationService.currentPosition;
              if (position != null) {
                 weatherService.getWeatherData(position.latitude, position.longitude)
                    .then((_) {
                       if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('天气已更新')),
                           );
                       }
                    }).catchError((error) {
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('天气更新失败: $error')),
                           );
                         }
                    });
              }

              if (mounted) {
                 setState(() {
                   _locationController.text = locationService.getFormattedLocation();
                 });
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text('已选择城市: ${cityInfo.name}')),
                 );
                 Navigator.pop(dialogContext);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final weatherService = context.watch<WeatherService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 位置和天气设置 Card
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const ListTile(
                  title: Text('位置与天气设置'),
                  leading: Icon(Icons.location_on),
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
                        ? (locationService.isLocationServiceEnabled ? '已获得权限并启用' : '已获得权限但服务未启用')
                        : '未获得位置权限',
                    style: TextStyle(
                      fontSize: 12,
                      color: locationService.hasLocationPermission && locationService.isLocationServiceEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                  value: locationService.hasLocationPermission && locationService.isLocationServiceEnabled,
                  onChanged: (value) async {
                    if (value) {
                      bool permissionGranted = await locationService.requestLocationPermission();
                      if (!permissionGranted) {
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('无法获取位置权限')),
                           );
                         }
                         return;
                      }

                      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                      if (!serviceEnabled) {
                         if (mounted) {
                           showDialog(
                             context: context,
                             builder: (context) => AlertDialog(
                               title: const Text('请启用位置服务'),
                               content: const Text('心记需要访问您的位置以提供天气等功能。请在系统设置中启用位置服务。'),
                               actions: [
                                 TextButton(
                                   onPressed: () => Navigator.pop(context),
                                   child: const Text('取消'),
                                 ),
                                 TextButton(
                                   onPressed: () async {
                                     Navigator.pop(context);
                                     await Geolocator.openLocationSettings();
                                   },
                                   child: const Text('去设置'),
                                 ),
                               ],
                             ),
                           );
                         }
                         return;
                      }

                       if(mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('正在获取位置...'), duration: Duration(seconds: 2)),
                           );
                       }
                       final position = await locationService.getCurrentLocation();
                       if (position != null && mounted) {
                         await weatherService.getWeatherData(
                           position.latitude,
                           position.longitude
                         );
                         ScaffoldMessenger.of(context).removeCurrentSnackBar();
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('位置服务已启用，位置已更新')),
                         );
                         setState(() {
                           _locationController.text = locationService.getFormattedLocation();
                         });
                       } else if (mounted) {
                         ScaffoldMessenger.of(context).removeCurrentSnackBar();
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('无法获取当前位置')),
                         );
                       }

                    } else {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('位置服务已禁用')),
                       );
                    }
                     if (mounted) {
                       setState(() {});
                     }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置显示位置',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('搜索并选择城市'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          _showCitySearchDialog(context);
                        },
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        '当前显示位置: ${locationService.currentAddress ?? '未设置'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                       const SizedBox(height: 8.0),
                    ],
                  ),
                ),

                if (locationService.currentAddress != null)
                  ListTile(
                    title: const Text('当前天气'),
                    subtitle: Text(
                      (weatherService.currentWeather == null && weatherService.temperature == null)
                          ? '点击右侧按钮刷新天气'
                          : '${weatherService.currentWeather ?? ""} ${weatherService.temperature ?? ""}',
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    leading: Icon(weatherService.getWeatherIconData()),
                    trailing: IconButton(
                       icon: const Icon(Icons.refresh),
                       tooltip: '刷新天气',
                       onPressed: () async {
                         final position = locationService.currentPosition;
                         if (position != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('正在刷新天气...'), duration: Duration(seconds: 1)),
                            );
                           await weatherService.getWeatherData(
                             position.latitude,
                             position.longitude
                           );
                           if (mounted) {
                             ScaffoldMessenger.of(context).removeCurrentSnackBar();
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text('天气已更新')),
                             );
                           }
                         } else {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('无法获取位置信息以刷新天气')),
                           );
                         }
                       },
                    ),
                    onTap: null,
                  ),

                const SizedBox(height: 8.0),
              ],
            ),
          ),

          // 应用设置 Card (保持不变)
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const ListTile(
                  title: Text('应用设置'),
                  leading: Icon(Icons.settings),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
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

          // 内容管理 Card (保持不变)
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const ListTile(
                  title: Text('内容管理'),
                  leading: Icon(Icons.category),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
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

          // --- 修改后的关于信息 Card ---
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                 // --- 修改：关于标题 ListTile，点击弹出包含链接的对话框 ---
                 ListTile(
                   title: const Text('关于 心记 (ThoughtEcho)'),
                   leading: const Icon(Icons.info_outline),
                   trailing: const Icon(Icons.chevron_right), // 添加箭头指示可点击
                   onTap: () {
                     showAboutDialog(
                       context: context,
                       applicationName: '心记 (ThoughtEcho)',
                       // 不再显示版本号
                       // applicationVersion: _appVersion,
                       applicationIcon: Image.asset('icon.png', width: 48, height: 48), // 确保 icon.png 在 assets 中
                       applicationLegalese: '© 2024 Shangjin Xiao',
                       children: <Widget>[
                         const SizedBox(height: 16),
                         const Text('一款帮助你记录和分析思想的应用。'),
                         const SizedBox(height: 24), // 增加间距

                         // --- 在对话框中添加链接 ---
                         _buildAboutLink(
                           context: context,
                           icon: Icons.code_outlined,
                           text: '查看项目源码 (GitHub)',
                           url: _projectUrl,
                         ),
                         const SizedBox(height: 8), // 链接间距
                         _buildAboutLink(
                           context: context,
                           icon: Icons.language_outlined,
                           text: '访问官网',
                           url: _websiteUrl,
                         ),
                         // --- 链接添加结束 ---
                       ],
                     );
                   },
                 ),
                 // --- 关于标题 ListTile 结束 ---

                 // --- 移除主列表中的链接 ListTile ---
                 // Padding(...), ListTile(...), ListTile(...)
                 // --- 移除结束 ---
              ],
            ),
          ),
          // --- 关于信息 Card 结束 ---

          const SizedBox(height: 20), // 底部增加一些间距
        ],
      ),
    );
  }

  // --- 新增：构建关于对话框中链接的辅助方法 ---
  Widget _buildAboutLink({
    required BuildContext context,
    required IconData icon,
    required String text,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchUrl(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // 居中显示
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary), // 图标稍大一点
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                // decoration: TextDecoration.underline, // 可选：添加下划线强调链接
              ),
            ),
          ],
        ),
      ),
    );
  }
  // --- 辅助方法结束 ---


  // _handleExport 和 _handleImport 函数保持不变 (省略以减少篇幅)
    Future<void> _handleExport() async {
      if (!mounted) return;
      final context = this.context;
      OverlayEntry? overlay;

      try {
        overlay = OverlayEntry(
          builder: (context) => const Material(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在导出...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        );
        Overlay.of(context).insert(overlay);

        final dbService = Provider.of<DatabaseService>(context, listen: false);

        final String fileName = '心记备份_${DateTime.now().toIso8601String().split('T').first}.json';
        final FileSaveLocation? result = await getSaveLocation(suggestedName: fileName);

        if (result == null) {
          overlay.remove();
          overlay = null;
          return;
        }

        final String path = await dbService.exportAllData(customPath: result.path);

        overlay.remove();
        overlay = null;

        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('备份成功'),
            content: SelectableText('备份文件已保存到:\n$path'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } catch (e) {
        overlay?.remove();
        overlay = null;
        if (!mounted) return;
        _showErrorDialog(context, '备份失败', '导出过程中发生错误: $e');
      }
    }

    Future<void> _handleImport() async {
      if (!mounted) return;
      final context = this.context;
      OverlayEntry? overlay;

      try {
        const XTypeGroup jsonTypeGroup = XTypeGroup(
          label: 'JSON Backup File',
          extensions: ['json'],
        );
        final List<XFile> files = await openFiles(acceptedTypeGroups: [jsonTypeGroup]);

        if (files.isEmpty) {
           return;
         }

        final XFile selectedFile = files.first;

        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认导入'),
            content: const Text('导入数据将清空当前所有数据，确定要继续吗？此操作不可撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确定导入'),
              ),
            ],
          ),
        );

        if (confirmed != true || !mounted) return;

        overlay = OverlayEntry(
          builder: (context) => const Material(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在导入...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        );
        Overlay.of(context).insert(overlay);


        final dbService = Provider.of<DatabaseService>(context, listen: false);

        bool isValid = false;
        String validationError = '';
        try {
          isValid = await dbService.validateBackupFile(selectedFile.path);
        } catch (e) {
           validationError = e.toString();
           debugPrint('备份文件验证失败: $validationError');
        }

        if (!isValid) {
          overlay.remove();
          overlay = null;
          if (!mounted) return;
          _showErrorDialog(context, '导入失败', '所选文件不是有效的备份文件: $validationError');
          return;
        }

        await dbService.importData(selectedFile.path, clearExisting: true);

        overlay.remove();
        overlay = null;

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据已恢复。请重启应用以查看更改。'),
            duration: Duration(seconds: 3),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));

      } catch (e) {
        overlay?.remove();
        overlay = null;

        if (!mounted) return;
        _showErrorDialog(context, '恢复失败', '导入过程中发生错误: $e');

      }
    }

    // 辅助函数：显示错误对话框
    void _showErrorDialog(BuildContext context, String title, String content) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           showDialog(
             context: context,
             builder: (context) => AlertDialog(
               title: Text(title),
               content: Text(content),
               actions: [
                 TextButton(
                   onPressed: () => Navigator.pop(context),
                   child: const Text('确定'),
                 ),
               ],
             ),
           );
         }
       });
     }
}
