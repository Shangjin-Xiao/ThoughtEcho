import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart'; // 确保导入 geolocator
import '../services/clipboard_service.dart'; // 添加剪贴板服务导入
import '../services/settings_service.dart'; // 添加设置服务导入
import 'ai_settings_page.dart';
import 'hitokoto_settings_page.dart';
import 'theme_settings_page.dart';
import 'logs_settings_page.dart'; // 导入新的日志设置页面
import '../services/location_service.dart'; // 包含 CityInfo 定义
import '../services/weather_service.dart';
import 'backup_restore_page.dart';
import '../widgets/city_search_widget.dart';
import 'category_settings_page.dart';

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
        final locationService = Provider.of<LocationService>(
          context,
          listen: false,
        );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
    }
  }
  // --- 启动 URL 辅助函数结束 ---

  // 显示城市搜索对话框
  void _showCitySearchDialog(BuildContext context) {
    // listen: false 因为我们只调用方法，不监听变化
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    showDialog(
      context: context,
      builder:
          (dialogContext) => Dialog(
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
                  // 获取 settings page 的 context，用于显示加载和关闭对话框
                  final settingsContext = context;
                  // 获取 dialog 的 context，用于关闭 dialog
                  final currentDialogContext = dialogContext;

                  // 显示加载指示器（使用 settings page 的 context）
                  showDialog(
                    context: settingsContext,
                    barrierDismissible: false,
                    builder:
                        (context) =>
                            const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    // 1. 设置城市信息
                    await locationService.setSelectedCity(cityInfo);

                    // 2. 获取更新后的位置
                    final position = locationService.currentPosition;

                    // 3. 如果位置有效，获取天气
                    if (position != null) {
                      await weatherService.getWeatherData(
                        position.latitude,
                        position.longitude,
                      );
                      // 检查 settings page 是否仍然 mounted
                      if (!settingsContext.mounted) return;
                      // 根据 weatherService 的状态显示成功或失败提示
                      if (weatherService.currentWeather != '天气数据获取失败') {
                        ScaffoldMessenger.of(
                          settingsContext,
                        ).showSnackBar(const SnackBar(content: Text('天气已更新')));
                      } else {
                        ScaffoldMessenger.of(settingsContext).showSnackBar(
                          const SnackBar(content: Text('天气更新失败，请稍后重试')),
                        );
                      }
                    } else {
                      if (!settingsContext.mounted) return;
                      ScaffoldMessenger.of(settingsContext).showSnackBar(
                        const SnackBar(content: Text('无法获取选中城市的位置信息')),
                      );
                    }

                    // 4. 更新 SettingsPage 的状态
                    // 检查 settings page 是否仍然 mounted
                    if (!settingsContext.mounted) return;
                    // 使用 _SettingsPageState 的 setState
                    if (mounted) {
                      // Check if _SettingsPageState is mounted
                      setState(() {
                        _locationController.text =
                            locationService.getFormattedLocation();
                      });
                    }
                    ScaffoldMessenger.of(settingsContext).showSnackBar(
                      SnackBar(content: Text('已选择城市: ${cityInfo.name}')),
                    );

                    // 5. 关闭加载指示器（使用 settings page context）
                    Navigator.pop(settingsContext);
                    // 6. 关闭城市搜索对话框（使用 dialog context）
                    Navigator.pop(currentDialogContext);
                  } catch (e) {
                    // 捕获 setSelectedCity 或 getWeatherData 中的错误
                    // 检查 settings page 是否仍然 mounted
                    if (!settingsContext.mounted) return;
                    // 关闭加载指示器（如果它仍然存在）
                    Navigator.pop(settingsContext);
                    ScaffoldMessenger.of(
                      settingsContext,
                    ).showSnackBar(SnackBar(content: Text('处理城市选择时出错: $e')));
                    // 不需要关闭 dialogContext，因为错误发生在 dialog 内部的操作中
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
                    color: theme.colorScheme.outline.withAlpha(
                      (0.2 * 255).round(),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('使用位置服务'),
                  subtitle: Text(
                    locationService.hasLocationPermission
                        ? (locationService.isLocationServiceEnabled
                            ? '已获得权限并启用'
                            : '已获得权限但服务未启用')
                        : '未获得位置权限',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          locationService.hasLocationPermission &&
                                  locationService.isLocationServiceEnabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                    ),
                  ),
                  value:
                      locationService.hasLocationPermission &&
                      locationService.isLocationServiceEnabled,
                  onChanged: (value) async {
                    if (value) {
                      bool permissionGranted =
                          await locationService.requestLocationPermission();
                      if (!permissionGranted) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('无法获取位置权限')),
                          );
                        }
                        return;
                      }

                      bool serviceEnabled =
                          await Geolocator.isLocationServiceEnabled();
                      if (!serviceEnabled) {
                        if (mounted) {
                          showDialog(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('请启用位置服务'),
                                  content: const Text(
                                    '心迹需要访问您的位置以提供天气等功能。请在系统设置中启用位置服务。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(context);
                                        // 在可能导致上下文无效的异步操作前保存上下文
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

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('正在获取位置...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      final position =
                          await locationService.getCurrentLocation();
                      if (position != null && mounted) {
                        await weatherService.getWeatherData(
                          position.latitude,
                          position.longitude,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).removeCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('位置服务已启用，位置已更新')),
                        );
                        setState(() {
                          _locationController.text =
                              locationService.getFormattedLocation();
                        });
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).removeCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法获取当前位置')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('位置服务已禁用')));
                    }
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
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
                          color: theme.colorScheme.onSurface.withAlpha(
                            (0.6 * 255).round(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                    ],
                  ),
                ),

                // 天气信息 ListTile，增加 isLoading 判断
                if (locationService.currentAddress != null)
                  weatherService.isLoading
                      ? const ListTile(
                        leading: SizedBox(
                          width: 24, // 与 Icon 大小一致
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text('正在加载天气...'),
                      )
                      : ListTile(
                        title: const Text('当前天气'),
                        subtitle: Text(
                          (weatherService.currentWeather == null &&
                                  weatherService.temperature == null)
                              ? '点击右侧按钮刷新天气'
                              : (weatherService.currentWeather == '天气数据获取失败'
                                  ? '天气获取失败' // 直接显示错误信息
                                  : '${WeatherService.getWeatherDescription(weatherService.currentWeather ?? 'unknown')} ${weatherService.temperature ?? ""}'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        leading: Icon(
                          weatherService.getWeatherIconData(),
                        ), // 图标会根据错误状态变化
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '刷新天气',
                          onPressed:
                              weatherService.isLoading
                                  ? null
                                  : () async {
                                    // 正在加载时禁用按钮
                                    final position =
                                        locationService.currentPosition;
                                    if (position != null) {
                                      // 不需要手动显示 SnackBar，isLoading 会处理 UI
                                      await weatherService.getWeatherData(
                                        position.latitude,
                                        position.longitude,
                                      );
                                      if (mounted &&
                                          weatherService.currentWeather !=
                                              '天气数据获取失败') {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('天气已更新'),
                                          ),
                                        );
                                      } else if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('天气更新失败，请稍后重试'),
                                          ),
                                        );
                                      }
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('无法获取位置信息以刷新天气'),
                                        ),
                                      );
                                    }
                                  },
                        ),
                        onTap: null,
                      ),

                // 添加天气数据来源信息
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    bottom: 8.0,
                  ),
                  child: Text(
                    '天气数据由 OpenMeteo 提供',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withAlpha(
                        (0.6 * 255).round(),
                      ),
                    ),
                  ),
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
                    color: theme.colorScheme.outline.withAlpha(
                      (0.2 * 255).round(),
                    ),
                  ),
                ),
                // 添加剪贴板监控设置
                _buildClipboardMonitoringItem(context),

                // 添加默认启动页面设置
                _buildDefaultStartPageItem(context),

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
                  title: const Text('API设置'),
                  subtitle: const Text('配置AI分析所需的API信息'),
                  leading: const Icon(Icons.api_outlined),
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
                  subtitle: const Text(
                    '自定义"每日一言"的类型',
                  ), // Keep original subtitle
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
                // Add Hitokoto attribution text here
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16.0,
                    top: 4.0,
                    right: 16.0,
                    bottom: 8.0,
                  ), // Added bottom padding
                  child: Text(
                    '一言服务由 Hitokoto 提供',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                    ),
                  ),
                ),
                // End of Hitokoto attribution text
                // Add Logs Settings entry below
                ListTile(
                  title: const Text('日志设置'),
                  subtitle: const Text('配置应用日志记录级别'),
                  leading: const Icon(
                    Icons.article_outlined,
                  ), // 或者 Icons.bug_report_outlined
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LogsSettingsPage(),
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
                    color: theme.colorScheme.outline.withAlpha(
                      (0.2 * 255).round(),
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('标签管理'),
                  subtitle: const Text('添加、编辑或删除笔记标签'),
                  leading: const Icon(Icons.label_outline),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CategorySettingsPage(),
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
                  title: const Text('关于 心迹 (ThoughtEcho)'),
                  leading: const Icon(Icons.info_outline),
                  trailing: const Icon(Icons.chevron_right), // 添加箭头指示可点击
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: '心迹 (ThoughtEcho)',
                      // 不再显示版本号
                      // applicationVersion: _appVersion,
                      applicationIcon: Image.asset(
                        'assets/icon.png',
                        width: 48,
                        height: 48,
                      ), // 路径修正，兼容所有平台
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
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ), // 图标稍大一点
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

  // 构建剪贴板监控设置项
  Widget _buildClipboardMonitoringItem(BuildContext context) {
    final clipboardService = Provider.of<ClipboardService>(context);
    return SwitchListTile(
      title: const Text('剪贴板监控'),
      subtitle: const Text('自动检测剪贴板内容并提示添加笔记'),
      value: clipboardService.enableClipboardMonitoring,
      onChanged: (value) {
        clipboardService.setEnableClipboardMonitoring(value);
      },
    );
  }

  // 构建默认启动页面设置项
  Widget _buildDefaultStartPageItem(BuildContext context) {
    // 从 SettingsService 获取设置
    final settingsService = Provider.of<SettingsService>(context);
    final currentValue = settingsService.appSettings.defaultStartPage;

    return ListTile(
      title: const Text('默认启动页面'),
      subtitle: Text(currentValue == 0 ? '首页（每日一言）' : '记录（笔记列表）'),
      leading: const Icon(Icons.home_outlined),
      onTap: () {
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('选择默认启动页面'),
                content: StatefulBuilder(
                  builder: (context, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<int>(
                          title: const Text('首页（每日一言）'),
                          value: 0,
                          groupValue: currentValue,
                          onChanged: (value) {
                            if (value != null) {
                              settingsService.updateAppSettings(
                                settingsService.appSettings.copyWith(
                                  defaultStartPage: value,
                                ),
                              );
                              Navigator.pop(context);
                            }
                          },
                        ),
                        RadioListTile<int>(
                          title: const Text('记录（笔记列表）'),
                          value: 1,
                          groupValue: currentValue,
                          onChanged: (value) {
                            if (value != null) {
                              settingsService.updateAppSettings(
                                settingsService.appSettings.copyWith(
                                  defaultStartPage: value,
                                ),
                              );
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
        );
      },
    );
  }
}
