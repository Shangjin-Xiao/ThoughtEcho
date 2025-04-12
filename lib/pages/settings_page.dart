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
            onCitySelected: (city) async { // 改为 async
              // 更新 LocationService 中的城市信息
              locationService.updateCity(city);

              // 尝试获取新城市的经纬度并更新天气
              final position = await locationService.getPositionForCity(city);
              if (position != null && mounted) {
                 final weatherService = Provider.of<WeatherService>(context, listen: false);
                 await weatherService.getWeatherData(position.latitude, position.longitude);
              }

              setState(() {
                // 更新文本框显示
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
    // 注意：在 build 方法中直接读取 listen: false 可能导致 UI 不更新
    // 对于需要响应变化的 Provider，使用 context.watch 或 Consumer
    final locationService = context.watch<LocationService>(); // 使用 watch 监听变化
    final weatherService = context.watch<WeatherService>(); // 使用 watch 监听变化
    final theme = Theme.of(context);

    // 确保控制器文本与 Service 同步 (如果 Service 在别处更新)
    // 放在这里可能导致每次 build 都重设，但对于显示是安全的
    // _locationController.text = locationService.getFormattedLocation();

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
                      // 请求位置权限
                      bool permissionGranted = await locationService.requestLocationPermission();
                      if (!permissionGranted) {
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('无法获取位置权限')),
                           );
                           // 保持开关关闭状态
                         }
                         return; // 权限未获取，直接返回
                      }

                      // 检查位置服务是否启用
                      if (!locationService.isLocationServiceEnabled) {
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
                                     await Geolocator.openLocationSettings(); // 尝试打开系统位置设置
                                   },
                                   child: const Text('去设置'),
                                 ),
                               ],
                             ),
                           );
                         }
                         return; // 位置服务未启用，直接返回
                      }

                       // 获取当前位置并更新天气
                       final position = await locationService.getCurrentLocation();
                       if (position != null && mounted) {
                         final weatherService = Provider.of<WeatherService>(context, listen: false);
                         await weatherService.getWeatherData(
                           position.latitude,
                           position.longitude
                         );
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('位置服务已启用')),
                         );
                       } else if (mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('无法获取当前位置')),
                         );
                       }

                    } else {
                       // 用户手动关闭开关
                       // 这里可以考虑是否清除位置信息，取决于产品逻辑
                       // locationService.clearLocation();
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('位置服务已禁用')),
                       );
                       // 无需调用 setState，因为 SwitchListTile 会自动更新其视觉状态
                    }
                     // 确保UI在权限或服务状态变化后更新
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
                        '设置显示位置', // 修改标题更清晰
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      // 城市搜索按钮
                      ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('搜索并选择城市'), // 修改按钮文字
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          _showCitySearchDialog(context);
                        },
                      ),
                      const SizedBox(height: 16.0),
                      // 手动输入位置（保留原功能，但可能与城市选择冲突，考虑是否移除或改进）
                      // Text(
                      //   '或手动输入位置',
                      //   style: TextStyle(
                      //     fontSize: 14,
                      //     color: theme.colorScheme.onSurface.withOpacity(0.8),
                      //   ),
                      // ),
                      // const SizedBox(height: 8.0),
                      // TextField(
                      //   controller: _locationController,
                      //   decoration: InputDecoration(
                      //     hintText: '国家,省份,城市,区县 (使用逗号分隔)',
                      //     border: OutlineInputBorder(
                      //       borderRadius: BorderRadius.circular(8.0),
                      //     ),
                      //     contentPadding: const EdgeInsets.symmetric(
                      //       horizontal: 12.0,
                      //       vertical: 12.0,
                      //     ),
                      //     suffixIcon: IconButton(
                      //       icon: const Icon(Icons.check),
                      //       tooltip: '确认手动输入的位置',
                      //       onPressed: () {
                      //         final locationString = _locationController.text.trim();
                      //         if (locationString.isNotEmpty) {
                      //           // 注意：手动输入会覆盖城市选择，需要明确逻辑
                      //           locationService.parseLocationString(locationString);
                      //           // 触发天气更新
                      //           final position = locationService.currentPosition;
                      //           if(position != null) {
                      //              weatherService.getWeatherData(position.latitude, position.longitude);
                      //           }
                      //           ScaffoldMessenger.of(context).showSnackBar(
                      //             const SnackBar(content: Text('位置已更新')),
                      //           );
                      //           // 收起键盘
                      //           FocusScope.of(context).unfocus();
                      //         } else {
                      //            ScaffoldMessenger.of(context).showSnackBar(
                      //              const SnackBar(content: Text('请输入有效的位置信息')),
                      //            );
                      //         }
                      //       },
                      //     ),
                      //   ),
                      //   onSubmitted: (value) { // 用户按回车时也确认
                      //      final locationString = value.trim();
                      //      if (locationString.isNotEmpty) {
                      //        locationService.parseLocationString(locationString);
                      //        final position = locationService.currentPosition;
                      //        if(position != null) {
                      //           weatherService.getWeatherData(position.latitude, position.longitude);
                      //        }
                      //        ScaffoldMessenger.of(context).showSnackBar(
                      //          const SnackBar(content: Text('位置已更新')),
                      //        );
                      //      }
                      //    },
                      // ),
                      // const SizedBox(height: 8.0),
                      Text( // 显示当前选择的位置
                        '当前显示位置: ${locationService.currentAddress ?? '未设置'}',
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
                    title: const Text('当前天气'), // 修改标题
                    subtitle: Text(
                      '${weatherService.currentWeather ?? "点击刷新"} ${weatherService.temperature ?? ""}',
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    leading: Icon(weatherService.getWeatherIconData()),
                    trailing: IconButton( // 使用 IconButton 增加点击区域
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
                    onTap: null, // 因为使用了 trailing IconButton，禁用 ListTile 的 onTap
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
                 // --- 修改：关于标题 ListTile，添加 onTap ---
                 ListTile(
                   title: const Text('关于 心记 (ThoughtEcho)'), // 标题更明确
                   leading: const Icon(Icons.info_outline),
                   trailing: const Icon(Icons.chevron_right), // 添加箭头指示可点击
                   onTap: () {
                     showAboutDialog(
                       context: context,
                       applicationName: '心记 (ThoughtEcho)',
                       applicationVersion: _appVersion, // 使用变量
                       applicationIcon: Image.asset('icon.png', width: 48, height: 48), // 确保 icon.png 在 assets 中
                       applicationLegalese: '© 2024 Shangjin Xiao',
                       children: <Widget>[
                         const SizedBox(height: 16),
                         const Text('一款帮助你记录和分析思想的应用。'),
                         const SizedBox(height: 16),
                         // 在对话框中添加 GitHub 链接
                         InkWell(
                           onTap: () => _launchUrl(_projectUrl),
                           child: Padding( // 增加内边距使更容易点击
                             padding: const EdgeInsets.symmetric(vertical: 8.0),
                             child: Row(
                               mainAxisAlignment: MainAxisAlignment.center,
                               children: [
                                 Icon(Icons.code, size: 16, color: Theme.of(context).colorScheme.primary),
                                 const SizedBox(width: 8),
                                 Text(
                                   '查看项目源码 (GitHub)', // 更清晰的文本
                                   style: TextStyle(
                                     color: Theme.of(context).colorScheme.primary,
                                     // decoration: TextDecoration.underline, // 可选：添加下划线
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
                 // --- 关于标题 ListTile 结束 ---

                 Padding( // 添加分割线
                   padding: const EdgeInsets.symmetric(horizontal: 16.0),
                   child: Divider(
                     color: theme.colorScheme.outline.withOpacity(0.2),
                   ),
                 ),
                 // 项目地址 (GitHub) - 直接显示
                 ListTile(
                   leading: const Icon(Icons.code_outlined), // 使用 outlined 图标统一风格
                   title: const Text('项目地址 (GitHub)'),
                   subtitle: Text(_projectUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                   trailing: const Icon(Icons.open_in_new),
                   onTap: () => _launchUrl(_projectUrl),
                 ),
                 // 官网 - 直接显示
                 ListTile(
                   leading: const Icon(Icons.language_outlined), // 使用 outlined 图标统一风格
                   title: const Text('官网'),
                   subtitle: Text(_websiteUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                   trailing: const Icon(Icons.open_in_new),
                   onTap: () => _launchUrl(_websiteUrl),
                 ),
                 // --- 移除单独的应用版本 ListTile ---
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
  // ... (您原有的 _handleExport 和 _handleImport 函数代码，包含加载指示器等改进) ...
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
      OverlayEntry? overlay; // 将 overlay 声明在 try 外部，以便在 catch 中访问

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
