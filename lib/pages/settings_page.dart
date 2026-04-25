import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../services/settings_service.dart';
import '../services/unified_log_service.dart';
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
import 'license_page.dart' as license;
import 'preferences_detail_page.dart';
import 'user_guide_page.dart';
import 'feedback_contact_page.dart';
import '../utils/feature_guide_helper.dart';
import 'storage_management_page.dart';
import 'local_ai_settings_page.dart'; // 导入本地 AI 设置页面
import 'smart_push_settings_page.dart'; // 导入智能推送设置页面
import '../widgets/anniversary_animation_overlay.dart'; // 导入一周年动画覆盖层
import '../widgets/anniversary_notebook_icon.dart';
import '../utils/anniversary_banner_text_utils.dart';
import '../utils/anniversary_display_utils.dart';
import '../extensions/note_category_localization_extension.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  // --- 定义链接地址 ---
  final String _projectUrl = 'https://github.com/Shangjin-Xiao/ThoughtEcho';
  final String _websiteUrl = 'https://note.shangjinyun.cn/';
  // --- 链接地址结束 ---
  final TextEditingController _locationController = TextEditingController();

  // --- 版本检查相关状态 ---
  bool _isCheckingUpdate = false;
  String? _updateCheckMessage;

  // --- 开发者模式相关 ---
  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  // 功能引导 keys
  final GlobalKey _preferencesGuideKey = GlobalKey();
  final GlobalKey _startupPageGuideKey = GlobalKey();
  final GlobalKey _themeGuideKey = GlobalKey();
  bool _guidesTriggered = false;

  @override
  void initState() {
    super.initState();
    // 初始化位置控制器
    _initLocationController();
  }

  /// 当设置页真正可见时触发功能引导
  void showGuidesIfNeeded({bool Function()? shouldShow}) {
    if (_guidesTriggered) return;

    final allShown =
        FeatureGuideHelper.hasShown(context, 'settings_preferences') &&
            FeatureGuideHelper.hasShown(context, 'settings_startup') &&
            FeatureGuideHelper.hasShown(context, 'settings_theme');

    if (allShown) {
      _guidesTriggered = true;
      return;
    }

    _guidesTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showSettingsGuides(shouldShow: shouldShow);
    });
  }

  /// 显示设置页功能引导
  void _showSettingsGuides({bool Function()? shouldShow}) {
    // 依次显示多个引导，等待前一个消失再显示下一个
    FeatureGuideHelper.showSequence(
      context: context,
      guides: [
        ('settings_preferences', _preferencesGuideKey),
        ('settings_startup', _startupPageGuideKey),
        ('settings_theme', _themeGuideKey),
      ],
      shouldShow: () {
        if (!mounted) {
          return false;
        }
        if (shouldShow != null && !shouldShow()) {
          return false;
        }
        return true;
      },
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
      final l10n = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cannotOpenLink(url)),
          duration: AppConstants.snackBarDurationError,
        ),
      );
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
        await UpdateBottomSheet.show(
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.checkUpdateFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // --- 版本检查方法结束 ---

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

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        children: [
          // 一周年庆典横幅（2026-03-23 至 2026-04-30 期间显示）
          _buildAnniversaryBanner(context),

          // 位置和天气设置 Card
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: Text(l10n.settingsLocationWeather),
                  leading: const Icon(Icons.location_on),
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
                  title: Text(l10n.settingsUseLocationService),
                  subtitle: Text(
                    locationService.hasLocationPermission
                        ? (locationService.isLocationServiceEnabled
                            ? l10n.settingsLocationEnabled
                            : l10n.settingsLocationPermissionOnly)
                        : l10n.settingsLocationNoPermission,
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
                            SnackBar(
                              content: Text(l10n.locationPermissionDenied),
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
                              title: Text(l10n.enableLocationService),
                              content: Text(l10n.enableLocationServiceDesc),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(currentContext),
                                  child: Text(l10n.cancel),
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
                                  child: Text(l10n.goToSettings),
                                ),
                              ],
                            ),
                          );
                        }
                        return;
                      }

                      if (mounted && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.gettingLocation),
                            duration: const Duration(seconds: 2),
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
                            SnackBar(
                              content: Text(l10n.locationServiceEnabled),
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
                            SnackBar(
                              content: Text(l10n.cannotGetLocation),
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
                          SnackBar(
                            content: Text(l10n.locationServiceDisabled),
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
                        l10n.settingsSetLocation,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: Text(l10n.settingsSearchCity),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          _showCitySearchDialog(context);
                        },
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        '${l10n.settingsCurrentLocation}: ${locationService.currentAddress ?? l10n.settingsNotSet}',
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

                // 当前天气信息已移动到"搜索并选择城市"对话框内
              ],
            ),
          ),

          // 应用设置 Card (保持不变)
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: Text(l10n.settingsAppSettings),
                  leading: const Icon(Icons.settings),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withAlpha(
                      (0.2 * 255).round(),
                    ),
                  ),
                ),
                // 语言设置
                _buildLanguageItem(context),
                // 二级页面入口：偏好设置
                ListTile(
                  key: _preferencesGuideKey, // 功能引导 key
                  title: Text(l10n.settingsPreferences),
                  subtitle: Text(l10n.settingsPreferencesDesc),
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
                  title: Text(l10n.settingsTheme),
                  subtitle: Text(l10n.settingsThemeDesc),
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
                  title: Text(l10n.settingsAI),
                  subtitle: Text(l10n.settingsAIDesc),
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
                // 本地AI功能 - 仅在开发者模式下显示
                Consumer<SettingsService>(
                  builder: (context, settingsService, _) {
                    if (!settingsService.appSettings.developerMode) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n.localAiFeatures,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiary.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: theme.colorScheme.tertiary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Text(
                              'Preview',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.tertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(l10n.localAiFeaturesDesc),
                      leading: const Icon(Icons.device_hub),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LocalAISettingsPage(),
                          ),
                        );
                      },
                    );
                  },
                ),
                // 智能推送
                Builder(
                  builder: (context) {
                    return ListTile(
                      title: Text(l10n.smartPushTitle),
                      subtitle: Text(l10n.smartPushDesc),
                      leading: const Icon(Icons.notifications_active_outlined),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SmartPushSettingsPage(),
                          ),
                        );
                      },
                    );
                  },
                ),
                ListTile(
                  title: Text(l10n.settingsHitokoto),
                  subtitle: Text(l10n.settingsHitokotoDesc),
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
                Consumer<SettingsService>(
                  builder: (context, settingsService, _) {
                    // 仅在开发者模式下显示日志设置入口
                    if (!settingsService.appSettings.developerMode) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      title: Text(l10n.settingsLogs),
                      subtitle: Text(l10n.settingsLogsDesc),
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
                    );
                  },
                ),
                Consumer<SettingsService>(
                  builder: (context, settingsService, _) {
                    if (!settingsService.appSettings.developerMode) {
                      return const SizedBox.shrink();
                    }
                    return SwitchListTile(
                      title: Text(l10n.logDebugInfo),
                      subtitle: Text(l10n.logDebugInfoDesc),
                      secondary: const Icon(Icons.speed_outlined),
                      value: settingsService.enableFirstOpenScrollPerfMonitor,
                      onChanged: (enabled) {
                        settingsService.setEnableFirstOpenScrollPerfMonitor(
                          enabled,
                        );
                      },
                    );
                  },
                ),
                // 添加日志调试信息显示（仅在Debug模式下显示）
                if (kDebugMode) ...[
                  ListTile(
                    title: Text(l10n.logDebugInfo),
                    subtitle: Text(l10n.logDebugInfoDesc),
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
                            title: Text(l10n.logDebugInfo),
                            content: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.databaseStatus,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  ...dbStatus.entries.map(
                                    (e) => Text('${e.key}: ${e.value}'),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    l10n.logStatistics,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  ...logSummary.entries.map(
                                    (e) => Text('${e.key}: ${e.value}'),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(l10n.close),
                              ),
                            ],
                          ),
                        );
                      } catch (e) {
                        if (!currentContext.mounted) return;
                        final l10n = AppLocalizations.of(currentContext);
                        ScaffoldMessenger.of(currentContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.getDebugInfoFailed(e.toString()),
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                ],
                // 存储管理
                ListTile(
                  title: Text(l10n.settingsStorage),
                  subtitle: Text(l10n.settingsStorageDesc),
                  leading: const Icon(Icons.storage_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StorageManagementPage(),
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
                  title: Text(l10n.settingsContentManagement),
                  leading: const Icon(Icons.category),
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
                  title: Text(l10n.settingsTags),
                  subtitle: Text(l10n.settingsTagsDesc),
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
                  title: Text(l10n.settingsBackup),
                  subtitle: Text(l10n.settingsBackupDesc),
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
                  title: Text(l10n.settingsSync),
                  subtitle: Text(l10n.settingsSyncDesc),
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
                  title: Text(l10n.settingsAbout),
                  leading: const Icon(Icons.info_outline),
                  trailing: const Icon(Icons.chevron_right), // 添加箭头指示可点击
                  onTap: () {
                    // 使用自定义关于对话框替代 showAboutDialog，以避免系统自动添加 "查看许可证" 按钮
                    showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(l10n.settingsAbout),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _handleLogoTap,
                                child: Image.asset(
                                  'assets/icon.png',
                                  width: 64,
                                  height: 64,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.apps,
                                          color: Colors.white,
                                          size: 36,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(l10n.settingsAboutSlogan),
                              const SizedBox(height: 20),
                              _buildAboutLink(
                                context: context,
                                icon: Icons.code_outlined,
                                text: l10n.settingsViewSource,
                                url: _projectUrl,
                              ),
                              const SizedBox(height: 8),
                              _buildAboutLink(
                                context: context,
                                icon: Icons.language_outlined,
                                text: l10n.settingsVisitWebsite,
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
                                          const FeedbackContactPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.feedback_outlined),
                                label: Text(l10n.feedbackAndContact),
                                style: _primaryButtonStyle(context),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const UserGuidePage(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.help_outline),
                                label: Text(l10n.userGuide),
                                style: _primaryButtonStyle(context),
                              ),
                              const SizedBox(height: 8),
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
                                label: Text(l10n.settingsViewLicenses),
                                style: _primaryButtonStyle(context),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            style: _textButtonStyle(dialogContext),
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(l10n.close),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withAlpha((0.2 * 255).round()),
                  ),
                ),

                // 检查更新 ListTile
                ListTile(
                  title: Text(l10n.settingsCheckUpdate),
                  subtitle: _updateCheckMessage != null
                      ? Text(
                          _updateCheckMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      : Text(l10n.settingsCheckUpdateDesc),
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

              ],
            ),
          ),

          // --- 关于信息 Card 结束 ---

          // --- 一周年开发者调试 Card (仅开发者模式可见) ---
          Consumer<SettingsService>(
            builder: (context, settingsService, _) {
              if (!settingsService.appSettings.developerMode) {
                return const SizedBox.shrink();
              }
              final l10n = AppLocalizations.of(context);
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(l10n.developerAnniversarySection),
                      leading: const Icon(Icons.cake_outlined),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Divider(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withAlpha((0.2 * 255).round()),
                      ),
                    ),
                    // 启用/禁用周年动画开关
                    SwitchListTile(
                      title: Text(l10n.developerAnniversaryEnabled),
                      subtitle: Text(l10n.developerAnniversaryEnabledDesc),
                      secondary: const Icon(Icons.celebration_outlined),
                      value: settingsService.anniversaryAnimationEnabled,
                      onChanged: (enabled) {
                        settingsService.setAnniversaryAnimationEnabled(enabled);
                      },
                    ),
                    // 重置"已展示"标志
                    ListTile(
                      title: Text(l10n.developerAnniversaryReset),
                      subtitle: Text(l10n.developerAnniversaryResetDesc),
                      leading: const Icon(Icons.refresh_outlined),
                      onTap: () async {
                        await settingsService.resetAnniversaryShown();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(
                                context,
                              ).developerAnniversaryResetDone,
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    // 预览动画
                    ListTile(
                      title: Text(l10n.developerAnniversaryPreview),
                      subtitle: Text(l10n.developerAnniversaryPreviewDesc),
                      leading: const Icon(Icons.play_circle_outlined),
                      onTap: () => _showAnniversaryAnimationInSettings(context),
                    ),
                  ],
                ),
              );
            },
          ),

          // --- 一周年开发者调试 Card 结束 ---
          const SizedBox(height: 20), // 底部增加一些间距
        ],
      ),
    );
  }

  // --- 处理 Logo 三击激活开发者模式 ---
  void _handleLogoTap() async {
    final now = DateTime.now();

    // 如果距离上次点击超过2秒，重置计数
    if (_lastLogoTap != null && now.difference(_lastLogoTap!).inSeconds > 2) {
      _logoTapCount = 0;
    }

    _lastLogoTap = now;
    _logoTapCount++;

    if (_logoTapCount >= 3) {
      _logoTapCount = 0;
      final settingsService = context.read<SettingsService>();
      final currentSettings = settingsService.appSettings;
      final newDeveloperMode = !currentSettings.developerMode;

      await settingsService.updateAppSettings(
        currentSettings.copyWith(developerMode: newDeveloperMode),
      );

      // 同步更新日志服务的持久化状态
      UnifiedLogService.instance.setPersistenceEnabled(newDeveloperMode);

      if (!mounted) return;
      final l10n = AppLocalizations.of(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newDeveloperMode
                ? l10n.developerModeEnabled
                : l10n.developerModeDisabled,
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // 关闭对话框
      Navigator.of(context).pop();
    }
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

  ButtonStyle _textButtonStyle(BuildContext context) =>
      TextButton.styleFrom(minimumSize: const Size.fromHeight(44));

  // 相关设置已移动到“偏好设置”二级页面

  // 构建语言设置项
  Widget _buildLanguageItem(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final currentLocale = settingsService.localeCode;
    final l10n = AppLocalizations.of(context);

    String getLanguageName(String? code) {
      switch (code) {
        case 'zh':
          return l10n.languageChinese;
        case 'en':
          return l10n.languageEnglish;
        case 'ja':
          return l10n.languageJapanese;
        case 'ko':
          return l10n.languageKorean;
        case 'es':
          return l10n.languageSpanish;
        case 'fr':
          return l10n.languageFrench;
        case 'de':
          return l10n.languageGerman;
        default:
          return l10n.languageFollowSystem;
      }
    }

    return ListTile(
      title: Text(l10n.languageSettings),
      subtitle: Text(getLanguageName(currentLocale)),
      leading: const Icon(Icons.translate),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.selectLanguage),
            content: StatefulBuilder(
              builder: (context, setState) {
                return RadioGroup<String?>(
                  groupValue: currentLocale,
                  onChanged: (value) async {
                    await settingsService.setLocale(value);
                    // 同步更新位置服务的语言设置
                    locationService.currentLocaleCode = value;
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String?>(
                        title: Text(l10n.languageFollowSystem),
                        value: null,
                      ),
                      RadioListTile<String?>(
                        title: Text(l10n.languageChinese),
                        value: 'zh',
                      ),
                      RadioListTile<String?>(
                        title: const Text('English'),
                        value: 'en',
                      ),
                      RadioListTile<String?>(
                        title: const Text('日本語'),
                        value: 'ja',
                      ),
                      RadioListTile<String?>(
                        title: const Text('한국어'),
                        value: 'ko',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Español'),
                        value: 'es',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Français'),
                        value: 'fr',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Deutsch'),
                        value: 'de',
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        );
      },
    );
  }

  // 构建默认启动页面设置项
  Widget _buildDefaultStartPageItem(BuildContext context) {
    // 从 SettingsService 获取设置
    final settingsService = Provider.of<SettingsService>(context);
    final currentValue = settingsService.appSettings.defaultStartPage;
    final l10n = AppLocalizations.of(context);

    return ListTile(
      key: _startupPageGuideKey, // 功能引导 key
      title: Text(l10n.settingsDefaultStartPage),
      subtitle: Text(
        currentValue == 0
            ? l10n.settingsStartPageHome
            : l10n.settingsStartPageNotes,
      ),
      leading: const Icon(Icons.home_outlined),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.settingsSelectStartPage),
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
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(
                        title: Text(l10n.settingsStartPageHome),
                        value: 0,
                      ),
                      RadioListTile<int>(
                        title: Text(l10n.settingsStartPageNotes),
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

  // --- 一周年庆典横幅 ---
  Widget _buildAnniversaryBanner(BuildContext context) {
    final now = DateTime.now();
    final settingsService = context.read<SettingsService>();
    final shouldShow = AnniversaryDisplayUtils.shouldShowSettingsBanner(
      now: now,
      developerMode: settingsService.appSettings.developerMode,
    );
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFF8FAFC), const Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showAnniversaryAnimationInSettings(context),
          child: Stack(
            children: [
              // 背景装饰 - 柔和的光晕
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFF818CF8,
                        ).withValues(alpha: isDark ? 0.2 : 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: -40,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFF60A5FA,
                        ).withValues(alpha: isDark ? 0.15 : 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 主内容区
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // 左侧：精致的笔记本图标
                    const AnniversaryNotebookIcon(),
                    const SizedBox(width: 20),
                    // 右侧：文本和指示器
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.anniversaryBannerTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: isDark
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatAnniversaryBannerSubtitleForTile(
                              l10n.anniversaryBannerSubtitle,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF475569),
                              height: 1.4,
                            ),
                            softWrap: true,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                l10n.anniversaryBannerTap,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF818CF8)
                                      : const Color(0xFF4F46E5),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: isDark
                                    ? const Color(0xFF818CF8)
                                    : const Color(0xFF4F46E5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnniversaryAnimationInSettings(BuildContext context) {
    showAnniversaryAnimationOverlay(context);
  }
}
