import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // 确保导入 url_launcher
import 'package:file_selector/file_selector.dart';
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
  // --- 定义链接地址 ---
  final String _projectUrl = 'https://github.com/Shangjin-Xiao/ThoughtEcho';
  final String _websiteUrl = 'https://echo.shangjinyun.cn/';
  // --- 链接地址结束 ---
  final TextEditingController _locationController = TextEditingController();

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

    // 初始化位置控制器文本
    _locationController.text = locationService.getFormattedLocation();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 位置和天气设置 Card (保持不变)
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
                         // 如果用户拒绝了权限，将开关状态重置为 false
                        setState(() {}); // 触发UI更新以反映正确的开关状态
                      }
                    } else {
                       // 用户手动关闭开关，可以考虑是否需要清除位置信息或提示
                       // locationService.clearLocation(); // 示例：清除位置
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('位置服务已禁用')),
                       );
                       setState(() {}); // 确保UI更新
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
                            tooltip: '确认手动输入的位置',
                            onPressed: () {
                              final locationString = _locationController.text.trim();
                              if (locationString.isNotEmpty) {
                                locationService.parseLocationString(locationString);
                                // 触发天气更新
                                final position = locationService.currentPosition;
                                if(position != null) {
                                   weatherService.getWeatherData(position.latitude, position.longitude);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('位置已更新')),
                                );
                                // 收起键盘
                                FocusScope.of(context).unfocus();
                              } else {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                   const SnackBar(content: Text('请输入有效的位置信息')),
                                 );
                              }
                            },
                          ),
                        ),
                        onSubmitted: (value) { // 用户按回车时也确认
                           final locationString = value.trim();
                           if (locationString.isNotEmpty) {
                             locationService.parseLocationString(locationString);
                             final position = locationService.currentPosition;
                             if(position != null) {
                                weatherService.getWeatherData(position.latitude, position.longitude);
                             }
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text('位置已更新')),
                             );
                           }
                         },
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
                      '${weatherService.currentWeather ?? "点击刷新"} ${weatherService.temperature ?? ""}',
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    leading: Icon(weatherService.getWeatherIconData()),
                    trailing: const Icon(Icons.refresh),
                    onTap: () async {
                      final position = locationService.currentPosition;
                      if (position != null) {
                         // 显示加载指示
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('正在刷新天气...'), duration: Duration(seconds: 1)),
                         );
                        await weatherService.getWeatherData(
                          position.latitude,
                          position.longitude
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).removeCurrentSnackBar(); // 移除加载提示
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

                const SizedBox(height: 8.0),
              ],
            ),
          ),

          // 应用设置 Card (保持不变)
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
                  subtitle: const Text('自定义\"每日一言\"的类型'),
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

          // --- 修改后的关于信息 Card ---
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const ListTile(
                  title: Text('关于'),
                  leading: Icon(Icons.info_outline),
                ),
                 Padding( // 添加分割线
                   padding: const EdgeInsets.symmetric(horizontal: 16.0),
                   child: Divider(
                     color: theme.colorScheme.outline.withOpacity(0.2),
                   ),
                 ),
                 // 项目地址 (GitHub)
                 ListTile(
                   leading: const Icon(Icons.code), // 代码图标
                   title: const Text('项目地址 (GitHub)'),
                   subtitle: Text(_projectUrl, maxLines: 1, overflow: TextOverflow.ellipsis), // 显示 URL
                   trailing: const Icon(Icons.open_in_new),
                   onTap: () => _launchUrl(_projectUrl), // 点击打开链接
                 ),
                 // 官网
                 ListTile(
                   leading: const Icon(Icons.language), // 网页图标
                   title: const Text('官网'),
                   subtitle: Text(_websiteUrl, maxLines: 1, overflow: TextOverflow.ellipsis), // 显示 URL
                   trailing: const Icon(Icons.open_in_new),
                   onTap: () => _launchUrl(_websiteUrl), // 点击打开链接
                 ),
                 // 应用版本信息 ListTile (保持原 showAboutDialog)
                 ListTile(
                    leading: const Icon(Icons.verified_outlined), // 版本图标
                    title: const Text('应用版本'),
                    subtitle: const Text('1.0.0+1'), // TODO: 动态获取版本号
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: '心记 (ThoughtEcho)', // 应用名称统一
                        applicationVersion: '1.0.0+1', // TODO: 动态获取版本号
                        applicationIcon: Image.asset('icon.png', width: 48, height: 48), // 使用你的应用图标
                        applicationLegalese: '© 2024 Shangjin Xiao', // 版权年份更新
                        children: <Widget>[
                          const SizedBox(height: 16),
                          const Text('一款帮助你记录和分析思想的应用。'),
                          // 这里不再需要手动添加 GitHub 链接了
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          // --- 关于信息 Card 结束 ---

          const SizedBox(height: 20), // 底部增加一些间距
        ],
      ),
    );
  }

  // _handleExport 和 _handleImport 函数保持不变 (省略以减少篇幅)
  // ... (您原有的 _handleExport 和 _handleImport 函数代码) ...
    Future<void> _handleExport() async {
      if (!mounted) return;
      final context = this.context;

      // 显示加载指示器
      final overlay = OverlayEntry(
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

      try {
        final dbService = Provider.of<DatabaseService>(context, listen: false);

        // 使用文件选择器让用户选择保存位置
        final String fileName = '心记备份_${DateTime.now().toIso8601String().split('T').first}.json';
        final FileSaveLocation? result = await getSaveLocation(suggestedName: fileName);

        if (result == null) {
          // 用户取消了保存
          overlay.remove();
          return;
        }

        final String path = await dbService.exportAllData(customPath: result.path);

        overlay.remove(); // 移除加载指示器

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
        overlay.remove(); // 确保在出错时移除加载指示器
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
        // 使用file_selector替代file_picker
        final XTypeGroup jsonTypeGroup = XTypeGroup(
          label: 'JSON Backup File',
          extensions: ['json'],
        );
        final List<XFile>? files = await openFiles(acceptedTypeGroups: [jsonTypeGroup]);

        if (files == null || files.isEmpty) {
           // 用户取消了选择
           return;
         }

        final XFile selectedFile = files.first; // 获取选中的第一个文件

        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认导入'),
            content: const Text('导入数据将清空当前所有数据，确定要继续吗？此操作不可撤销。'), // 强调不可撤销
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), // 突出确定按钮的危险性
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确定导入'),
              ),
            ],
          ),
        );

        if (confirmed != true || !mounted) return;

        // 显示加载指示器
        final overlay = OverlayEntry(
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

        // 先验证文件
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
          if (!mounted) return;
          _showErrorDialog(context, '导入失败', '所选文件不是有效的备份文件: $validationError');
          return;
        }


        // 验证通过后执行导入
        await dbService.importData(selectedFile.path, clearExisting: true); // 明确使用 clearExisting: true

        overlay.remove(); // 移除加载指示器

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据已恢复。请重启应用以查看更改。'), // 提示用户需要重启
            duration: Duration(seconds: 3), // 稍微延长提示时间
          ),
        );

        // 延迟一小段时间确保 SnackBar 显示
        await Future.delayed(const Duration(milliseconds: 500));

        // 这里可以选择不自动重启，让用户手动操作
        // 或者保留之前的重启逻辑
        // if (!mounted) return;
        // Navigator.pushAndRemoveUntil(
        //   context,
        //   MaterialPageRoute(builder: (_) => const HomePage()),
        //   (route) => false,
        // );

      } catch (e) {
        // 确保在任何导入步骤出错时都移除 overlay
        // ignore: unnecessary_null_comparison
        if (Overlay.of(context) != null && Overlay.of(context).mounted) {
           // 尝试移除 overlay，需要找到对应的 Entry 或更好的管理方式
           // 简单处理：假设 overlay 变量仍然有效
           try {
             // overlay.remove(); // 这可能因为 overlay 已经被移除而出错
           } catch (removeError) {
             debugPrint("移除导入加载指示器时出错: $removeError");
           }
        }

        if (!mounted) return;
        _showErrorDialog(context, '恢复失败', '导入过程中发生错误: $e');

      }
    }

    // 辅助函数：显示错误对话框
    void _showErrorDialog(BuildContext context, String title, String content) {
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
}
