import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../services/clipboard_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../utils/app_logger.dart';
import 'ai_settings_page.dart';
import 'hitokoto_settings_page.dart';
import 'theme_settings_page.dart';
import 'logs_settings_page.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import 'backup_restore_page.dart';
import '../widgets/city_search_widget.dart';
import '../controllers/weather_search_controller.dart';
import 'category_settings_page.dart';
import 'annual_report_page.dart';
import 'ai_annual_report_webview.dart';

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
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
    }
  }
  // --- 启动 URL 辅助函数结束 ---

  // 显示城市搜索对话框
  void _showCitySearchDialog(BuildContext context) {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    // 创建天气搜索控制器
    final weatherController = WeatherSearchController(
      locationService,
      weatherService,
    );

    showDialog(
      context: context,
      builder:
          (dialogContext) => ChangeNotifierProvider.value(
            value: weatherController,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(8.0),
                child: CitySearchWidget(
                  weatherController: weatherController,
                  initialCity: locationService.city,
                  onSuccess: () {
                    // 刷新设置页面的状态
                    if (mounted) {
                      setState(() {
                        _locationController.text =
                            locationService.getFormattedLocation();
                      });
                    }
                  },
                ),
              ),
            ),
          ),
    ).then((_) {
      // 对话框关闭后，释放控制器
      weatherController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final weatherService = context.watch<WeatherService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: '年度报告',
            onSelected: (value) {
              if (value == 'native') {
                _showNativeAnnualReport();
              } else if (value == 'ai') {
                _showAIAnnualReport();
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'native',
                    child: Row(
                      children: [
                        Icon(Icons.bar_chart),
                        SizedBox(width: 8),
                        Text('原生数据报告'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'ai',
                    child: Row(
                      children: [
                        Icon(Icons.psychology),
                        SizedBox(width: 8),
                        Text('AI 年度总结'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
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
                      if (!mounted) return; // Add this check
                      if (!serviceEnabled) {
                        if (mounted) {
                          final currentContext =
                              context; // Capture context before async gap
                          showDialog(
                            context: currentContext,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('请启用位置服务'),
                                  content: const Text(
                                    '心迹需要访问您的位置以提供天气等功能。请在系统设置中启用位置服务。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(currentContext),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        if (!currentContext.mounted) {
                                          return; // Check mounted before pop
                                        }
                                        Navigator.pop(currentContext);
                                        await Geolocator.openLocationSettings();
                                        if (!mounted) return; // Add this check
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
                      if (!mounted) return; // Add this check
                      if (position != null) {
                        // Removed extra mounted check here, as context is already checked above
                        await weatherService.getWeatherData(
                          position.latitude,
                          position.longitude,
                        );
                        if (!mounted) return;
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        scaffoldMessenger.removeCurrentSnackBar();
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('位置服务已启用，位置已更新')),
                        );
                        setState(() {
                          _locationController.text =
                              locationService.getFormattedLocation();
                        });
                      } else {
                        if (!mounted) return;
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        scaffoldMessenger.removeCurrentSnackBar();
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('无法获取当前位置')),
                        );
                      }
                    } else {
                      if (!mounted) return;
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('位置服务已禁用')),
                      );
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
                                      if (context.mounted &&
                                          weatherService.currentWeather !=
                                              '天气数据获取失败') {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('天气已更新'),
                                          ),
                                        );
                                      } else if (context.mounted) {
                                        final currentScaffoldMessenger =
                                            ScaffoldMessenger.of(context);
                                        currentScaffoldMessenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('天气更新失败，请稍后重试'),
                                          ),
                                        );
                                      }
                                    } else {
                                      if (!context.mounted) return;
                                      final currentScaffoldMessenger =
                                          ScaffoldMessenger.of(context);
                                      currentScaffoldMessenger.showSnackBar(
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
                  subtitle: const Text('配置AI分析所需的API信息和多服务商管理'),
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

  /// 显示原生年度报告
  Future<void> _showNativeAnnualReport() async {
    try {
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final quotes = await databaseService.getUserQuotes();
      final currentYear = DateTime.now().year;

      final thisYearQuotes =
          quotes.where((quote) {
            final quoteDate = DateTime.parse(quote.date);
            return quoteDate.year == currentYear;
          }).toList();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    AnnualReportPage(year: currentYear, quotes: thisYearQuotes),
          ),
        );
      }
    } catch (e) {
      AppLogger.e('显示原生年度报告失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成年度报告失败')));
      }
    }
  }

  /// 显示AI年度报告
  Future<void> _showAIAnnualReport() async {
    try {
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final quotes = await databaseService.getUserQuotes();
      final currentYear = DateTime.now().year;

      final thisYearQuotes =
          quotes.where((quote) {
            final quoteDate = DateTime.parse(quote.date);
            return quoteDate.year == currentYear;
          }).toList();

      if (mounted) {
        // 显示加载对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => const AlertDialog(
                content: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('正在生成AI年度报告...'),
                  ],
                ),
              ),
        );

        try {
          final aiService = Provider.of<AIService>(context, listen: false);

          // 准备数据摘要
          final totalNotes = thisYearQuotes.length;
          final totalWords = thisYearQuotes.fold<int>(
            0,
            (sum, quote) => sum + quote.content.length,
          );
          final averageWordsPerNote =
              totalNotes > 0 ? (totalWords / totalNotes).round() : 0;

          // 获取标签统计
          final Map<String, int> tagCounts = {};
          for (final quote in thisYearQuotes) {
            for (final tagId in quote.tagIds) {
              tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
            }
          }

          // 获取积极的笔记内容示例
          final positiveKeywords = [
            '成长',
            '学习',
            '进步',
            '成功',
            '快乐',
            '感谢',
            '收获',
            '突破',
            '希望',
          ];
          final positiveQuotes = thisYearQuotes
              .where(
                (quote) => positiveKeywords.any(
                  (keyword) => quote.content.contains(keyword),
                ),
              )
              .take(5)
              .map((quote) => quote.content)
              .join('\n');

          final prompt = '''
你是一个年度报告生成助手。请基于以下用户的笔记数据，生成一份温暖、积极、有意义的年度总结报告。

用户数据：
- 年份：$currentYear
- 总笔记数：$totalNotes 篇
- 总字数：$totalWords 字
- 平均每篇字数：$averageWordsPerNote 字
- 主要标签：${tagCounts.keys.take(5).join(', ')}

部分积极内容示例：
$positiveQuotes

请参考我提供的HTML模板结构，生成一份完整的HTML年度报告。要求：
1. 保持模板的美观设计和响应式布局
2. 用真实数据替换模板中的示例数据
3. 在精彩回顾部分，只选择积极、正面、有成长意义的内容
4. 生成鼓励性的洞察和建议
5. 保持语气温暖、积极向上
6. 确保HTML在移动端浏览器中能正常显示

请直接返回完整的HTML代码，不需要其他说明。
''';

          final result = await aiService.analyzeSource(prompt);
          Navigator.pop(context); // 关闭加载对话框

          if (mounted && result.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => AIAnnualReportWebView(
                      htmlContent: result,
                      year: currentYear,
                    ),
              ),
            );
          }
        } catch (e) {
          Navigator.pop(context); // 关闭加载对话框
          AppLogger.e('生成AI年度报告失败', error: e);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('生成AI年度报告失败')));
          }
        }
      }
    } catch (e) {
      AppLogger.e('显示AI年度报告失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('获取数据失败')));
      }
    }
  }
}
