import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/unified_log_service.dart';
import '../utils/app_logger.dart';
import '../models/note_category.dart';
import 'ai_settings_page.dart';
import 'hitokoto_settings_page.dart';
import 'theme_settings_page.dart';
import 'logs_settings_page.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/version_check_service.dart';
import '../widgets/update_dialog.dart';
import '../constants/app_constants.dart';
import 'backup_restore_page.dart';
import 'note_sync_page.dart';
import '../widgets/city_search_widget.dart';
import '../controllers/weather_search_controller.dart';
import 'category_settings_page.dart';
import 'annual_report_page.dart';
import 'ai_annual_report_webview.dart';
import 'license_page.dart' as license;
import 'preferences_detail_page.dart';
import '../services/image_cache_service.dart';
import '../services/media_reference_service.dart';
import '../utils/feature_guide_helper.dart';

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

  // --- 版本检查相关状态 ---
  bool _isCheckingUpdate = false;
  String? _updateCheckMessage;

  // --- 清除缓存相关状态 ---
  bool _isClearingCache = false;
  
  // 功能引导 keys
  final GlobalKey _preferencesGuideKey = GlobalKey();
  final GlobalKey _startupPageGuideKey = GlobalKey();
  final GlobalKey _themeGuideKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 初始化位置控制器
    _initLocationController();
    
    // 显示功能引导
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSettingsGuides();
    });
  }

  /// 显示设置页功能引导
  void _showSettingsGuides() {
    // 依次显示多个引导
    FeatureGuideHelper.showSequence(
      context: context,
      guides: [
        ('settings_preferences', _preferencesGuideKey),
        ('settings_startup', _startupPageGuideKey),
        ('settings_theme', _themeGuideKey),
      ],
      delayBetween: const Duration(milliseconds: 600),
      autoDismissDuration: const Duration(seconds: 4),
    );
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
      messenger.showSnackBar(SnackBar(
        content: Text('无法打开链接: $url'),
        duration: AppConstants.snackBarDurationError,
      ));
    }
  }
  // --- 启动 URL 辅助函数结束 ---

  // --- 版本检查方法 ---
  Future<void> _checkForUpdates({bool showNoUpdateMessage = true}) async {
    if (_isCheckingUpdate) return;

    setState(() {
      _isCheckingUpdate = true;
      _updateCheckMessage = null;
    });

    try {
      final versionInfo = await VersionCheckService.checkForUpdates(
        forceRefresh: true,
      );

      setState(() {
        _isCheckingUpdate = false;
      });

      if (mounted) {
        await UpdateDialog.show(
          context,
          versionInfo,
          showNoUpdateMessage: showNoUpdateMessage,
        );
      }
    } catch (e) {
      setState(() {
        _isCheckingUpdate = false;
        _updateCheckMessage = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // --- 版本检查方法结束 ---

  // --- 清除缓存方法 ---
  Future<void> _clearAppCache() async {
    if (_isClearingCache) return;
    setState(() {
      _isClearingCache = true;
    });

    // 在await之前获取所有需要的服务
    final weatherService = Provider.of<WeatherService>(context, listen: false);
    final db = Provider.of<DatabaseService>(context, listen: false);

    try {
      // 清理图片缓存（SVG转图片等）
      try {
        // 延迟导入避免循环依赖（文件顶部已静态导入）
        // ignore: unnecessary_statements
        ImageCacheService().clearCache();
      } catch (_) {}

      // 清理天气缓存
      try {
        await weatherService.clearCache();
      } catch (_) {}

      // 清理版本检查缓存
      try {
        VersionCheckService.clearCache();
      } catch (_) {}

      // 刷新数据库内存缓存（不删除数据）
      try {
        db.refreshAllData();
      } catch (_) {}

      // 额外：清理无引用（孤儿）媒体文件
      int orphanCleared = 0;
      try {
        orphanCleared = await MediaReferenceService.cleanupOrphanFiles();
      } catch (_) {}

      if (!mounted) return;
      final msg =
          orphanCleared > 0 ? '缓存已清除，已清理$orphanCleared个无用媒体文件' : '缓存已清除';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清除缓存失败: $e'),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearingCache = false;
        });
      }
    }
  }
  // --- 清除缓存方法结束 ---

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
      builder: (dialogContext) => ChangeNotifierProvider.value(
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        // actions: [
        //   PopupMenuButton<String>(
        //     icon: const Icon(Icons.analytics_outlined),
        //     tooltip: '年度报告',
        //     onSelected: (value) {
        //       if (value == 'native') {
        //         _showNativeAnnualReport();
        //       } else if (value == 'ai') {
        //         _showAIAnnualReport();
        //       } else if (value == 'test') {
        //         _testAIAnnualReport();
        //       }
        //     },
        //     itemBuilder: (context) => [
        //       const PopupMenuItem(
        //         value: 'native',
        //         child: Row(
        //           children: [
        //             Icon(Icons.analytics_outlined),
        //             SizedBox(width: 8),
        //             Text('年度报告'),
        //           ],
        //         ),
        //       ),
        //       const PopupMenuItem(
        //         value: 'ai',
        //         child: Row(
        //           children: [
        //             Icon(Icons.auto_awesome),
        //             SizedBox(width: 8),
        //             Text('AI 年度总结'),
        //           ],
        //         ),
        //       ),
        //       const PopupMenuItem(
        //         value: 'test',
        //         child: Row(
        //           children: [
        //             Icon(Icons.bug_report),
        //             SizedBox(width: 8),
        //             Text('测试AI报告'),
        //           ],
        //         ),
        //       ),
        //     ],
        //   ),
        // ],
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
                      color: locationService.hasLocationPermission &&
                              locationService.isLocationServiceEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                  value: locationService.hasLocationPermission &&
                      locationService.isLocationServiceEnabled,
                  onChanged: (value) async {
                    if (value) {
                      bool permissionGranted =
                          await locationService.requestLocationPermission();
                      if (!permissionGranted) {
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('无法获取位置权限'),
                              duration: AppConstants.snackBarDurationError,
                            ),
                          );
                        }
                        return;
                      }

                      bool serviceEnabled =
                          await Geolocator.isLocationServiceEnabled();
                      if (!mounted) return; // Add this check
                      if (!serviceEnabled) {
                        if (mounted && context.mounted) {
                          final currentContext =
                              context; // Capture context before async gap
                          showDialog(
                            context: currentContext,
                            builder: (context) => AlertDialog(
                              title: const Text('请启用位置服务'),
                              content: const Text(
                                '心迹需要访问您的位置以提供天气等功能。请在系统设置中启用位置服务。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(currentContext),
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

                      if (mounted && context.mounted) {
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
                        if (context.mounted) {
                          final scaffoldMessenger = ScaffoldMessenger.of(
                            context,
                          );
                          scaffoldMessenger.removeCurrentSnackBar();
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('位置服务已启用，位置已更新'),
                              duration: AppConstants.snackBarDurationImportant,
                            ),
                          );
                        }
                        setState(() {
                          _locationController.text =
                              locationService.getFormattedLocation();
                        });
                      } else {
                        if (!mounted) return;
                        if (context.mounted) {
                          final scaffoldMessenger = ScaffoldMessenger.of(
                            context,
                          );
                          scaffoldMessenger.removeCurrentSnackBar();
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('无法获取当前位置'),
                              duration: AppConstants.snackBarDurationError,
                            ),
                          );
                        }
                      }
                    } else {
                      if (!mounted) return;
                      if (context.mounted) {
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                            content: Text('位置服务已禁用'),
                            duration: AppConstants.snackBarDurationNormal,
                          ),
                        );
                      }
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

                // 当前天气信息已移动到“搜索并选择城市”对话框内
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
                // 二级页面入口：偏好设置
                ListTile(
                  key: _preferencesGuideKey, // 功能引导 key
                  title: const Text('偏好设置'),
                  subtitle: const Text('个性化选项与AI功能'),
                  leading: const Icon(Icons.tune),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PreferencesDetailPage(),
                      ),
                    );
                  },
                ),

                // 添加默认启动页面设置
                _buildDefaultStartPageItem(context),

                ListTile(
                  key: _themeGuideKey, // 功能引导 key
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
                  subtitle: const Text('配置AI分析所需的API信息和多服务商管理'),
                  leading: const Icon(Icons.auto_awesome),
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
                // 移至偏好设置页
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
                // 添加日志调试信息显示（仅在Debug模式下显示）
                if (kDebugMode) ...[
                  ListTile(
                    title: const Text('日志调试信息'),
                    subtitle: const Text('显示日志数据库状态和路径信息'),
                    leading: const Icon(Icons.bug_report),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      // 保存context引用以避免async gap问题
                      final currentContext = context;
                      final logService = Provider.of<UnifiedLogService>(
                        currentContext,
                        listen: false,
                      );

                      try {
                        final dbStatus = await logService.getDatabaseStatus();
                        final logSummary = logService.getLogSummary();

                        if (!currentContext.mounted) return;
                        showDialog(
                          context: currentContext,
                          builder: (context) => AlertDialog(
                            title: const Text('日志调试信息'),
                            content: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('数据库状态:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  ...dbStatus.entries
                                      .map((e) => Text('${e.key}: ${e.value}')),
                                  const SizedBox(height: 16),
                                  const Text('日志统计:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  ...logSummary.entries
                                      .map((e) => Text('${e.key}: ${e.value}')),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      } catch (e) {
                        if (!currentContext.mounted) return;
                        ScaffoldMessenger.of(currentContext).showSnackBar(
                          SnackBar(
                            content: Text('获取调试信息失败: $e'),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                ],
                // 清除缓存
                ListTile(
                  title: const Text('清除缓存'),
                  subtitle: const Text('释放图片、天气与版本检查等缓存'),
                  leading: const Icon(Icons.cleaning_services_outlined),
                  trailing: _isClearingCache
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _isClearingCache
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('清除缓存'),
                              content: const Text(
                                  '将清除图片、天气与版本检查缓存，不会删除任何笔记数据。是否继续？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('取消'),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    Navigator.pop(dialogContext);
                                    await _clearAppCache();
                                  },
                                  child: const Text('清除'),
                                ),
                              ],
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
                ListTile(
                  title: const Text('笔记同步'),
                  subtitle: const Text('与附近设备同步笔记数据'),
                  leading: const Icon(Icons.sync),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NoteSyncPage(),
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
                    // 使用自定义关于对话框替代 showAboutDialog，以避免系统自动添加 "查看许可证" 按钮
                    showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('关于 心迹 (ThoughtEcho)'),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/icon.png',
                                width: 64,
                                height: 64,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.apps,
                                          color: Colors.white, size: 36),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              const Text('你的专属灵感摘录本'),
                              const SizedBox(height: 20),
                              _buildAboutLink(
                                context: context,
                                icon: Icons.code_outlined,
                                text: '查看项目源码 (GitHub)',
                                url: _projectUrl,
                              ),
                              const SizedBox(height: 8),
                              _buildAboutLink(
                                context: context,
                                icon: Icons.language_outlined,
                                text: '访问官网',
                                url: _websiteUrl,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const license.LicensePage(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.article_outlined),
                                label: const Text('查看许可证信息'),
                                style: _primaryButtonStyle(context),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            style: _textButtonStyle(dialogContext),
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // --- 关于标题 ListTile 结束 ---

                // 添加分隔线
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: Theme.of(context).colorScheme.outline.withAlpha(
                          (0.2 * 255).round(),
                        ),
                  ),
                ),

                // 检查更新 ListTile
                ListTile(
                  title: const Text('检查更新'),
                  subtitle: _updateCheckMessage != null
                      ? Text(_updateCheckMessage!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))
                      : const Text('检查是否有新版本可用'),
                  leading: _isCheckingUpdate
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update),
                  trailing: _isCheckingUpdate
                      ? null
                      : const Icon(Icons.chevron_right),
                  onTap: _isCheckingUpdate ? null : () => _checkForUpdates(),
                ),

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
    return Center(
      child: ElevatedButton.icon(
        style: _primaryButtonStyle(context),
        onPressed: () => _launchUrl(url),
        icon: Icon(icon, size: 18),
        label: Text(text),
      ),
    );
  }
  // --- 辅助方法结束 ---

  // 统一按钮样式方法，作为类的私有工具方法，便于在文件内复用
  ButtonStyle _primaryButtonStyle(BuildContext context) =>
      ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  ButtonStyle _textButtonStyle(BuildContext context) => TextButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
      );

  // 相关设置已移动到“偏好设置”二级页面

  // 构建默认启动页面设置项
  Widget _buildDefaultStartPageItem(BuildContext context) {
    // 从 SettingsService 获取设置
    final settingsService = Provider.of<SettingsService>(context);
    final currentValue = settingsService.appSettings.defaultStartPage;

    return ListTile(
      key: _startupPageGuideKey, // 功能引导 key
      title: const Text('默认启动页面'),
      subtitle: Text(currentValue == 0 ? '首页（每日一言）' : '记录（笔记列表）'),
      leading: const Icon(Icons.home_outlined),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('选择默认启动页面'),
            content: StatefulBuilder(
              builder: (context, setState) {
                return RadioGroup<int>(
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
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(
                        title: Text('首页（每日一言）'),
                        value: 0,
                      ),
                      RadioListTile<int>(
                        title: Text('记录（笔记列表）'),
                        value: 1,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 显示原生年度报告
  // ignore: unused_element
  Future<void> _showNativeAnnualReport() async {
    try {
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final quotes = await databaseService.getUserQuotes();
      final currentYear = DateTime.now().year;

      final thisYearQuotes = quotes.where((quote) {
        final quoteDate = DateTime.parse(quote.date);
        return quoteDate.year == currentYear;
      }).toList();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AnnualReportPage(year: currentYear, quotes: thisYearQuotes),
          ),
        );
      }
    } catch (e) {
      AppLogger.e('显示原生年度报告失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
          content: Text('生成年度报告失败'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
    }
  }

  /// 显示AI年度报告
  // ignore: unused_element
  Future<void> _showAIAnnualReport() async {
    try {
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final quotes = await databaseService.getUserQuotes();
      final currentYear = DateTime.now().year;

      final thisYearQuotes = quotes.where((quote) {
        final quoteDate = DateTime.parse(quote.date);
        return quoteDate.year == currentYear;
      }).toList();

      if (mounted) {
        // 显示加载对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
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

          // 获取月度分布数据
          final Map<int, int> monthlyData = {};
          for (int i = 1; i <= 12; i++) {
            monthlyData[i] = 0;
          }
          for (final quote in thisYearQuotes) {
            final quoteDate = DateTime.parse(quote.date);
            monthlyData[quoteDate.month] =
                (monthlyData[quoteDate.month] ?? 0) + 1;
          }

          // 获取标签信息
          final allCategories = await databaseService.getCategories();
          final tagNames = <String>[];
          for (final tagId in tagCounts.keys.take(10)) {
            final category = allCategories.firstWhere(
              (c) => c.id == tagId,
              orElse: () => NoteCategory(id: tagId, name: '未知标签'),
            );
            tagNames.add(category.name);
          }

          // 获取时间段分布
          final Map<String, int> timePeriods = {
            '早晨': 0,
            '上午': 0,
            '下午': 0,
            '傍晚': 0,
            '夜晚': 0,
          };

          for (final quote in thisYearQuotes) {
            final quoteDate = DateTime.parse(quote.date);
            final hour = quoteDate.hour;
            if (hour >= 5 && hour < 9) {
              timePeriods['早晨'] = (timePeriods['早晨'] ?? 0) + 1;
            } else if (hour >= 9 && hour < 12) {
              timePeriods['上午'] = (timePeriods['上午'] ?? 0) + 1;
            } else if (hour >= 12 && hour < 18) {
              timePeriods['下午'] = (timePeriods['下午'] ?? 0) + 1;
            } else if (hour >= 18 && hour < 22) {
              timePeriods['傍晚'] = (timePeriods['傍晚'] ?? 0) + 1;
            } else {
              timePeriods['夜晚'] = (timePeriods['夜晚'] ?? 0) + 1;
            }
          }

          final peakTime = timePeriods.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

          // 修复：活跃记录天数应按“年月日”去重，而非仅按“日号”
          final int uniqueActiveDays = thisYearQuotes
              .map((q) {
                final d = DateTime.parse(q.date);
                return DateTime(d.year, d.month, d.day);
              })
              .toSet()
              .length;

          final prompt = '''基于以下用户笔记数据，生成一份完整的HTML年度报告。

用户数据统计：
- 年份：$currentYear
- 总笔记数：$totalNotes 篇
- 总字数：$totalWords 字
- 平均每篇字数：$averageWordsPerNote 字
- 活跃记录天数：$uniqueActiveDays 天
- 使用标签数：${tagCounts.length} 个

月度分布数据：
${monthlyData.entries.map((e) => '${e.key}月: ${e.value}篇').join('\n')}

主要标签（按使用频率）：
${tagNames.take(10).join(', ')}

最活跃记录时间：$peakTime

部分积极内容示例：
${positiveQuotes.isNotEmpty ? positiveQuotes : '用户的记录充满了思考和成长的足迹。'}

请生成一份完整的HTML年度报告，要求：
1. 必须返回完整的HTML代码，从<!DOCTYPE html>开始到</html>结束
2. 不要返回JSON或其他格式，只返回HTML
3. 使用现代化的移动端友好设计
4. 包含所有真实的统计数据
5. 精选积极正面的笔记内容作为回顾
6. 生成鼓励性的洞察和建议
7. 保持温暖积极的语调
8. 确保HTML可以在浏览器中正常显示

请直接返回HTML代码，不需要任何解释。''';

          AppLogger.i('开始生成AI年度报告，数据统计：总笔记$totalNotes篇，总字数$totalWords字');

          final result = await aiService.generateAnnualReportHTML(prompt);

          AppLogger.i('AI年度报告生成完成，内容长度：${result.length}字符');

          if (!mounted) return;
          Navigator.pop(context); // 关闭加载对话框

          if (mounted && result.isNotEmpty) {
            // 检查返回内容的格式
            final isHtml =
                result.trim().toLowerCase().startsWith('<!doctype') ||
                    result.trim().toLowerCase().startsWith('<html');
            final isJson =
                result.trim().startsWith('{') || result.trim().startsWith('[');

            AppLogger.i('AI返回内容格式检查：isHtml=$isHtml, isJson=$isJson');

            if (isJson) {
              AppLogger.w('AI返回了JSON格式而非HTML，可能是模型理解错误');
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AIAnnualReportWebView(
                  htmlContent: result,
                  year: currentYear,
                ),
              ),
            );
          } else {
            AppLogger.w('AI返回了空内容');
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(
                content: Text('AI返回了空内容，请重试'),
                duration: AppConstants.snackBarDurationError,
              ));
            }
          }
        } catch (e) {
          AppLogger.e('生成AI年度报告失败', error: e);
          if (mounted) {
            Navigator.pop(context); // 关闭加载对话框

            String errorMessage = '生成AI年度报告失败';
            if (e.toString().contains('API Key')) {
              errorMessage = '请先在AI设置中配置有效的API Key';
            } else if (e.toString().contains('network') ||
                e.toString().contains('连接')) {
              errorMessage = '网络连接异常，请检查网络后重试';
            } else if (e.toString().contains('quota') ||
                e.toString().contains('limit')) {
              errorMessage = 'AI服务配额不足，请稍后重试';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      AppLogger.e('显示AI年度报告失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
          content: Text('获取数据失败'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
    }
  }

  /// 测试AI年度报告功能
  // ignore: unused_element
  Future<void> _testAIAnnualReport() async {
    try {
      AppLogger.i('开始测试AI年度报告功能');

      // 显示测试对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在测试AI年度报告...'),
            ],
          ),
        ),
      );

      try {
        final aiService = Provider.of<AIService>(context, listen: false);

        // 使用简化的测试数据
        const testPrompt = '''基于以下用户笔记数据，生成一份完整的HTML年度报告。

用户数据统计：
- 年份：2024
- 总笔记数：100 篇
- 总字数：5000 字
- 平均每篇字数：50 字
- 活跃记录天数：200 天
- 使用标签数：10 个

月度分布数据：
1月: 8篇
2月: 12篇
3月: 15篇
4月: 10篇
5月: 9篇
6月: 11篇
7月: 13篇
8月: 7篇
9月: 6篇
10月: 4篇
11月: 3篇
12月: 2篇

主要标签（按使用频率）：
个人成长, 工作思考, 读书笔记, 生活感悟, 技术学习

最活跃记录时间：晚上

部分积极内容示例：
今天学会了新的技术，感觉很有成就感。
和朋友聊天收获很多，人际关系让我成长了不少。
读了一本好书，对人生有了新的理解。

请生成一份完整的HTML年度报告，要求：
1. 必须返回完整的HTML代码，从<!DOCTYPE html>开始到</html>结束
2. 不要返回JSON或其他格式，只返回HTML
3. 使用现代化的移动端友好设计
4. 包含所有真实的统计数据
5. 精选积极正面的笔记内容作为回顾
6. 生成鼓励性的洞察和建议
7. 保持温暖积极的语调
8. 确保HTML可以在浏览器中正常显示

请直接返回HTML代码，不需要任何解释。''';

        AppLogger.i('发送测试提示词给AI');

        final result = await aiService.generateAnnualReportHTML(testPrompt);

        AppLogger.i('AI测试报告生成完成，内容长度：${result.length}字符');

        if (!mounted) return;
        Navigator.pop(context); // 关闭加载对话框

        if (mounted && result.isNotEmpty) {
          // 详细检查返回内容
          final trimmed = result.trim();
          final isHtml = trimmed.toLowerCase().startsWith('<!doctype') ||
              trimmed.toLowerCase().startsWith('<html');
          final isJson = trimmed.startsWith('{') || trimmed.startsWith('[');
          final containsHtmlTags = trimmed.contains('<html') ||
              trimmed.contains('<body') ||
              trimmed.contains('<div');

          AppLogger.i('''
测试结果分析：
- 内容长度：${result.length}字符
- 是HTML格式：$isHtml
- 是JSON格式：$isJson
- 包含HTML标签：$containsHtmlTags
- 前100字符：${trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed}
''');

          // 显示结果对话框
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('测试结果'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('内容长度：${result.length}字符'),
                  Text('HTML格式：${isHtml ? '✅' : '❌'}'),
                  Text('JSON格式：${isJson ? '⚠️' : '✅'}'),
                  Text('包含HTML标签：${containsHtmlTags ? '✅' : '❌'}'),
                  const SizedBox(height: 10),
                  const Text('前100字符：'),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      trimmed.length > 100
                          ? '${trimmed.substring(0, 100)}...'
                          : trimmed,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AIAnnualReportWebView(
                          htmlContent: result,
                          year: 2024,
                        ),
                      ),
                    );
                  },
                  child: const Text('查看报告'),
                ),
              ],
            ),
          );
        } else {
          AppLogger.w('AI返回了空内容');
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(
              content: Text('测试失败：AI返回了空内容'),
              duration: AppConstants.snackBarDurationError,
            ));
          }
        }
      } catch (e) {
        AppLogger.e('测试AI年度报告失败', error: e);
        if (mounted) {
          Navigator.pop(context); // 关闭加载对话框

          String errorMessage = '测试失败：$e';
          if (e.toString().contains('API Key')) {
            errorMessage = '测试失败：请先在AI设置中配置有效的API Key';
          } else if (e.toString().contains('network') ||
              e.toString().contains('连接')) {
            errorMessage = '测试失败：网络连接异常';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.e('测试AI年度报告初始化失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
          content: Text('测试初始化失败'),
          duration: AppConstants.snackBarDurationError,
        ));
      }
    }
  }
}
