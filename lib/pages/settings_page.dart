import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';
// --- 添加 geolocator 导入 ---
import 'package:geolocator/geolocator.dart';
// --- 导入结束 ---
import 'home_page.dart';
import '../services/database_service.dart';
import 'ai_settings_page.dart';
import 'tag_settings_page.dart';
import 'hitokoto_settings_page.dart';
import 'theme_settings_page.dart';
import '../services/settings_service.dart';
import '../services/location_service.dart'; // 包含 CityInfo 定义
import '../services/weather_service.dart';
import 'backup_restore_page.dart';
import '../widgets/city_search_widget.dart';
// 导入 package_info_plus 来动态获取版本信息 (如果已添加依赖)
// import 'package:package_info_plus/package_info_plus.dart';

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

  // 应用版本信息 (暂时硬编码，可以考虑动态获取)
  String _appVersion = '1.0.0+1';

  @override
  void initState() {
    super.initState();
    // _loadAppVersion(); // 如果需要动态加载版本，取消此行注释
    // 初始化位置控制器
    _initLocationController();
  }

  // 如果需要动态获取版本，使用此方法
  // Future<void> _loadAppVersion() async {
  //   try {
  //     PackageInfo packageInfo = await PackageInfo.fromPlatform();
  //     setState(() {
  //       _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
  //     });
  //   } catch (e) {
  //     debugPrint("获取应用版本失败: $e");
  //     // 保留默认值
  //   }
  // }

  void _initLocationController() {
     // 延迟初始化，确保 Provider 可用
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (mounted) {
         final locationService = Provider.of<LocationService>(context, listen: false);
         // 使用 getFormattedLocation 初始化文本框
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
      builder: (dialogContext) => Dialog( // 使用 dialogContext 避免歧义
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.all(8.0),
          child: CitySearchWidget(
            initialCity: locationService.city, // 传递当��城市名用于可能的高亮或默认显示
            onCitySelected: (cityInfo) async { // 参数类型为 CityInfo
              // --- 修正：调用 LocationService 的现有方法 ---
              locationService.setSelectedCity(cityInfo);
              // --- 修正结束 ---

              // setSelectedCity 内部会更新 _currentPosition
              final position = locationService.currentPosition;
              if (position != null) {
                 // 异步获取天气，不需要 await，让 UI 先响应
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

              // 更新文本框显示 (在 setState 中确保 UI 刷新)
              if (mounted) {
                 setState(() {
                   _locationController.text = locationService.getFormattedLocation();
                 });
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text('已选择城市: ${cityInfo.name}')),
                 );
                 // 关闭对话框
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
    // 使用 watch 监听 LocationService 和 WeatherService 的变化以更新UI
    final locationService = context.watch<LocationService>();
    final weatherService = context.watch<WeatherService>();
    final theme = Theme.of(context);

    // 考虑是否在此处同步 Controller，取决于 LocationService 是否会在别处被修改
    // _locationController.text = locationService.getFormattedLocation();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 位置和天气设置 Card
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
                        ? (locationService.isLocationServiceEnabled ? '已获得权限并启用' : '已获得权限但服务未启用')
                        : '未获得位置权限',
                    style: TextStyle(
                      fontSize: 12,
                      color: locationService.hasLocationPermission && locationService.isLocationServiceEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                  // 开关状态取决于权限和服务是否都启用
                  value: locationService.hasLocationPermission && locationService.isLocationServiceEnabled,
                  onChanged: (value) async {
                    if (value) {
                      // 尝试启用服务
                      bool permissionGranted = await locationService.requestLocationPermission();
                      if (!permissionGranted) {
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('无法获取位置权限')),
                           );
                         }
                         // 权限未获取，开关状态应保持关闭 (SwitchListTile 会自动处理视觉状态)
                         return;
                      }

                      // 检查位置服务是否启用
                      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                      if (!serviceEnabled) {
                         if (mounted) {
                           // 提示用户打开位置服务
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
                                     // --- 修正：调用 Geolocator ---
                                     await Geolocator.openLocationSettings(); // 尝试打开系统位置设置
                                     // --- 修正结束 ---
                                   },
                                   child: const Text('去设置'),
                                 ),
                               ],
                             ),
                           );
                         }
                         // 服务未启用，开关状态应保持关闭
                         return;
                      }

                       // 权限和服务都已启用，获取当前位置并更新天气
                       // 显示加载提示
                       if(mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('正在获取位置...'), duration: Duration(seconds: 2)),
                           );
                       }
                       final position = await locationService.getCurrentLocation(); // 内部会处理地址解析
                       if (position != null && mounted) {
                         // getCurrentLocation 内部会调用 getAddressFromLatLng 更新地址
                         // 触发天气更新
                         await weatherService.getWeatherData(
                           position.latitude,
                           position.longitude
                         );
                         ScaffoldMessenger.of(context).removeCurrentSnackBar(); // 移除加载提示
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('位置服务已启用，位置已更新')),
                         );
                         // 更新文本框
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
                       // 用户手动关闭开关
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('位置服务已禁用')),
                       );
                       // 这里可以考虑清除位置信息
                       // locationService.clearLocation(); // 假设有此方法
                    }
                     // 强制刷新UI以确保开关状态正确反映
                     // (虽然 SwitchListTile 通常会自己更新，但保险起见)
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
                      // 城市搜索按钮
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
                      const SizedBox(height: 8.0), // 减小间距
                      // 显示当前选择的位置
                      Text(
                        '当前显示位置: ${locationService.currentAddress ?? '未设置'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                       const SizedBox(height: 8.0), // 增加底部间距
                    ],
                  ),
                ),

                // 当前天气显示与刷新
                if (locationService.currentAddress != null)
                  ListTile(
                    title: const Text('当前天气'),
                    subtitle: Text(
                      // 如果天气为空，提示用户刷新
                      (weatherService.currentWeather == null && weatherService.temperature == null)
                          ? '点击右侧按钮刷新天气'
                          : '${weatherService.currentWeather ?? ""} ${weatherService.temperature ?? ""}',
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    leading: Icon(weatherService.getWeatherIconData()), // 显示天气图标
                    trailing: IconButton(
                       icon: const Icon(Icons.refresh),
                       tooltip: '刷新天气',
                       onPressed: () async {
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
                    onTap: null, // 禁用 ListTile 的 onTap
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

          // 关于信息 Card (已修正)
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                 // 关于标题 ListTile，点击弹出对话框
                 ListTile(
                   title: const Text('关于 心记 (ThoughtEcho)'),
                   leading: const Icon(Icons.info_outline),
                   trailing: const Icon(Icons.chevron_right),
                   onTap: () {
                     showAboutDialog(
                       context: context,
                       applicationName: '心记 (ThoughtEcho)',
                       applicationVersion: _appVersion, // 使用变量
                       // 确保 icon.png 在 pubspec.yaml 的 assets 中声明
                       applicationIcon: Image.asset('icon.png', width: 48, height: 48),
                       applicationLegalese: '© 2024 Shangjin Xiao',
                       children: <Widget>[
                         const SizedBox(height: 16),
                         const Text('一款帮助你记录和分析思想的应用。'),
                         const SizedBox(height: 16),
                         // 在对话框中添加 GitHub 链接
                         InkWell(
                           onTap: () => _launchUrl(_projectUrl),
                           child: Padding(
                             padding: const EdgeInsets.symmetric(vertical: 8.0),
                             child: Row(
                               mainAxisAlignment: MainAxisAlignment.center,
                               children: [
                                 Icon(Icons.code, size: 16, color: Theme.of(context).colorScheme.primary),
                                 const SizedBox(width: 8),
                                 Text(
                                   '查看项目源码 (GitHub)',
                                   style: TextStyle(
                                     color: Theme.of(context).colorScheme.primary,
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         ),
                       ],
                     );
                   },
                 ),
                 Padding( // 添加分割线
                   padding: const EdgeInsets.symmetric(horizontal: 16.0),
                   child: Divider(
                     color: theme.colorScheme.outline.withOpacity(0.2),
                   ),
                 ),
                 // 项目地址 (GitHub) - 直接显示
                 ListTile(
                   leading: const Icon(Icons.code_outlined),
                   title: const Text('项目地址 (GitHub)'),
                   subtitle: Text(_projectUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                   trailing: const Icon(Icons.open_in_new),
                   onTap: () => _launchUrl(_projectUrl),
                 ),
                 // 官网 - 直接显示
                 ListTile(
                   leading: const Icon(Icons.language_outlined),
                   title: const Text('官网'),
                   subtitle: Text(_websiteUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                   trailing: const Icon(Icons.open_in_new),
                   onTap: () => _launchUrl(_websiteUrl),
                 ),
              ],
            ),
          ),

          const SizedBox(height: 20), // 底部增加一些间距
        ],
      ),
    );
  }

  // _handleExport 和 _handleImport 函数保持不变 (省略以减少篇幅)
  // ... (您原有的 _handleExport 和 _handleImport 函数代码，包含加载指示器等改进) ...
    Future<void> _handleExport() async {
      if (!mounted) return;
      final context = this.context;
      OverlayEntry? overlay;

      try {
        // 显示加载指示器
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

        // 使用文件选择器让用户选择保存位置
        final String fileName = '心记备份_${DateTime.now().toIso8601String().split('T').first}.json';
        final FileSaveLocation? result = await getSaveLocation(suggestedName: fileName);

        if (result == null) {
          // 用户取消了保存
          overlay?.remove();
          overlay = null;
          return;
        }

        final String path = await dbService.exportAllData(customPath: result.path);

        overlay?.remove(); // 移除加载指示器
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
        overlay?.remove(); // 确保在出错时移除加载指示器
        overlay = null;
        if (!mounted) return;
        _showErrorDialog(context, '备份失败', '导出过程中发生错误: $e');
      }
    }

    Future<void> _handleImport() async {
      if (!mounted) return;
      final context = this.context;
      OverlayEntry? overlay; // 将 overlay 声明在 try 外部

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
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), // 突出确定按钮的危��性
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确定导入'),
              ),
            ],
          ),
        );

        if (confirmed != true || !mounted) return;

        // 显示加载指示器
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
          overlay?.remove(); // 移除加载指示器
          overlay = null; // 清空引用
          if (!mounted) return;
          _showErrorDialog(context, '导入失败', '所选文件不是有效的备份文件: $validationError');
          return;
        }


        // 验证通过后执行导入
        await dbService.importData(selectedFile.path, clearExisting: true); // 明确使用 clearExisting: true

        overlay?.remove(); // 移除加载指示器
        overlay = null; // 清空引用

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据已恢复。请重启应用以查看更改。'), // 提示用户需要重启
            duration: Duration(seconds: 3), // 稍微延长提示时间
          ),
        );

        // 延迟一小段时间确保 SnackBar 显示
        await Future.delayed(const Duration(milliseconds: 500));

        // 可以考虑添加一个按钮让用户手动重启，或者保留之前的自动导航逻辑
        // if (!mounted) return;
        // Navigator.pushAndRemoveUntil(
        //   context,
        //   MaterialPageRoute(builder: (_) => const HomePage()),
        //   (route) => false,
        // );

      } catch (e) {
        // 确保在任何导入步骤出错时都移除 overlay
        overlay?.remove();
        overlay = null;

        if (!mounted) return;
        _showErrorDialog(context, '恢复失败', '导入过程中发生错误: $e');

      }
    }

    // 辅助函数：显示错误对话框
    void _showErrorDialog(BuildContext context, String title, String content) {
       // 确保在UI线程上显示对话框
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) { // 再次检查 mounted 状态
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
