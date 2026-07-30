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
import 'trash_page.dart';
import '../widgets/app_snackbar.dart';
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
import 'webdav_sync_page.dart';
import '../services/webdav_sync_service.dart';
import '../utils/lww_utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  // --- 定义链接地址 ---
  final String _projectUrl = 'https://github.com/Shangjin-Xiao/ThoughtEcho';
  final String _websiteUrl = 'https://note.shangjinyun.cn/';
  final String _privacyUrl = 'https://note.shangjinyun.cn/privacy.html';
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
          Consumer<LocationService>(
            builder: (context, locationService, _) => Card(
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
                                duration:
                                    AppConstants.snackBarDurationImportant,
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
                          final scaffoldMessenger =
                              ScaffoldMessenger.of(context);
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
                          style: theme.textTheme.titleSmall,
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
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: theme.colorScheme.tertiary),
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
                // 日志和实验性开关已移至「实验室」Card（_buildLabSection）
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
                  title: Text(l10n.trash),
                  subtitle: Consumer<SettingsService>(
                    builder: (context, settingsService, _) => Text(
                      _retentionLabel(
                        l10n,
                        settingsService.trashRetentionDays,
                      ),
                    ),
                  ),
                  leading: const Icon(Icons.delete_outline),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TrashPage(),
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
                ListTile(
                  title: Row(
                    children: [
                      Text(l10n.webdavSyncTitle),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Preview',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Consumer<WebDAVSyncService>(
                    builder: (context, webdavSync, _) {
                      if (!webdavSync.enabled) {
                        return Text(l10n.webdavSyncSubtitle);
                      }
                      String statusStr = '';
                      if (webdavSync.syncStatus == WebDAVSyncStatus.syncing) {
                        statusStr = l10n.webdavStatusSyncing;
                      } else if (webdavSync.syncStatus ==
                          WebDAVSyncStatus.success) {
                        statusStr = l10n.webdavStatusSuccess;
                      } else if (webdavSync.syncStatus ==
                          WebDAVSyncStatus.failed) {
                        statusStr = l10n.webdavStatusFailed;
                      }

                      final timeStr = webdavSync.lastSyncTime.isNotEmpty
                          ? LWWUtils.formatTimestamp(webdavSync.lastSyncTime)
                          : '从未同步';

                      return Text(statusStr.isNotEmpty
                          ? '$statusStr (上次：$timeStr)'
                          : '已启用 (上次：$timeStr)');
                    },
                  ),
                  leading: const Icon(Icons.cloud_sync_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WebDAVSyncPage(),
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
                                icon: Icons.language_outlined,
                                text: l10n.settingsVisitWebsite,
                                url: _websiteUrl,
                              ),
                              const SizedBox(height: 8),
                              _buildAboutLink(
                                context: context,
                                icon: Icons.code_outlined,
                                text: l10n.settingsViewSource,
                                url: _projectUrl,
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
                              const SizedBox(height: 8),
                              _buildAboutLink(
                                context: context,
                                icon: Icons.privacy_tip_outlined,
                                text: l10n.settingsPrivacyPolicy,
                                url: _privacyUrl,
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

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withAlpha(
                      (0.2 * 255).round(),
                    ),
                  ),
                ),
                ListTile(
                  title: Text(l10n.feedbackAndContact),
                  leading: const Icon(Icons.feedback_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FeedbackContactPage(),
                      ),
                    );
                  },
                ),

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

          // 实验室 Card（仅开发者模式可见，放在最后避免干扰普通用户）
          _buildLabSection(context),

          /*
          // --- 一周年开发者调试 Card (仅开发者模式可见) ---
          // 一周年开发者模式控制已临时关闭，保留给两周年复用。
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
          */
          const SizedBox(height: 20), // 底部增加一些间距
        ],
      ),
    );
  }

  String _retentionLabel(AppLocalizations l10n, int days) {
    switch (days) {
      case 7:
        return l10n.trashRetentionOption7Days;
      case 90:
        return l10n.trashRetentionOption90Days;
      case 30:
      default:
        return l10n.trashRetentionOption30Days;
    }
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

  /// 实验室：开发者模式下的调试入口和实验性开关。
  ///
  /// 这些项过去散落在「应用设置」Card 里，每一项各自包一层
  /// `Consumer<SettingsService>` 重复判断 `developerMode`，普通用户看到的是一张
  /// 混了实验开关的设置卡。现在整张 Card 只判断一次，非开发者模式完全不渲染。
  Widget _buildLabSection(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settingsService, _) {
        if (!settingsService.appSettings.developerMode) {
          return const SizedBox.shrink();
        }
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);

        return Card(
          margin: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              ListTile(
                title: Text(l10n.settingsLab),
                subtitle: Text(l10n.settingsLabDesc),
                leading: const Icon(Icons.science_outlined),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Divider(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),

              // 日志设置入口
              ListTile(
                title: Text(l10n.settingsLogs),
                subtitle: Text(l10n.settingsLogsDesc),
                leading: const Icon(Icons.article_outlined),
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

              // 记录页禁用卡片阴影
              SwitchListTile(
                title: Text(l10n.noteListDisableCardShadowsExperiment),
                subtitle: Text(l10n.noteListDisableCardShadowsExperimentDesc),
                secondary: const Icon(Icons.layers_clear_outlined),
                value: settingsService.noteListDisableCardShadows,
                onChanged: settingsService.setNoteListDisableCardShadows,
              ),

              // 记录页禁用折叠模糊
              SwitchListTile(
                title: Text(l10n.noteListDisableBackdropBlurExperiment),
                subtitle: Text(l10n.noteListDisableBackdropBlurExperimentDesc),
                secondary: const Icon(Icons.blur_off_outlined),
                value: settingsService.noteListDisableBackdropBlur,
                onChanged: settingsService.setNoteListDisableBackdropBlur,
              ),

              // 首屏滚动性能监测
              // 注意：这一项过去错误复用了 l10n.logDebugInfo（「日志调试信息」），
              // 和下面真正的调试信息入口标题完全相同，现已改用专属文案。
              SwitchListTile(
                title: Text(l10n.firstOpenScrollPerfMonitorExperiment),
                subtitle: Text(l10n.firstOpenScrollPerfMonitorExperimentDesc),
                secondary: const Icon(Icons.speed_outlined),
                value: settingsService.enableFirstOpenScrollPerfMonitor,
                onChanged: settingsService.setEnableFirstOpenScrollPerfMonitor,
              ),

              // AddNote 自动聚焦
              SwitchListTile(
                title: Text(l10n.addNoteAutoFocusExperiment),
                subtitle: Text(l10n.addNoteAutoFocusExperimentDesc),
                secondary: const Icon(Icons.keyboard_outlined),
                value: settingsService.addNoteDialogAutoFocus,
                onChanged: settingsService.setAddNoteDialogAutoFocus,
              ),

              // AddNote 延迟获取元数据
              SwitchListTile(
                title: Text(l10n.addNoteDeferMetadataExperiment),
                subtitle: Text(l10n.addNoteDeferMetadataExperimentDesc),
                secondary: const Icon(Icons.timer_outlined),
                value: settingsService.addNoteDialogDeferAutoMetadata,
                onChanged: settingsService.setAddNoteDialogDeferAutoMetadata,
              ),

              // 记录页添加笔记动画
              ListTile(
                title: Text(l10n.noteInsertAnimationExperiment),
                subtitle: Text(
                  l10n.noteInsertAnimationCurrent(
                    _noteInsertAnimationLabel(
                      l10n,
                      settingsService.noteInsertAnimationType,
                    ),
                  ),
                ),
                leading: const Icon(Icons.animation_outlined),
                trailing: DropdownButton<String>(
                  value: settingsService.noteInsertAnimationType,
                  items: [
                    DropdownMenuItem(
                      value: 'scale',
                      child: Text(l10n.noteInsertAnimationScale),
                    ),
                    DropdownMenuItem(
                      value: 'slide',
                      child: Text(l10n.noteInsertAnimationSlide),
                    ),
                    DropdownMenuItem(
                      value: 'none',
                      child: Text(l10n.noteInsertAnimationNone),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      settingsService.setNoteInsertAnimationType(value);
                    }
                  },
                ),
              ),

              // 日志调试信息（仅 Debug 构建）
              if (kDebugMode)
                ListTile(
                  title: Text(l10n.logDebugInfo),
                  subtitle: Text(l10n.logDebugInfoDesc),
                  leading: const Icon(Icons.bug_report),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showLogDebugInfo(context),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 记录页插入动画方案的显示名。
  String _noteInsertAnimationLabel(AppLocalizations l10n, String type) {
    switch (type) {
      case 'scale':
        return l10n.noteInsertAnimationScale;
      case 'slide':
        return l10n.noteInsertAnimationSlide;
      default:
        return l10n.noteInsertAnimationNone;
    }
  }

  /// 展示日志数据库状态和统计信息（Debug 构建的调试入口）。
  Future<void> _showLogDebugInfo(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final logService = Provider.of<UnifiedLogService>(context, listen: false);

    try {
      final dbStatus = await logService.getDatabaseStatus();
      final logSummary = logService.getLogSummary();

      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.logDebugInfo),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.databaseStatus,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                ...dbStatus.entries.map((e) => Text('${e.key}: ${e.value}')),
                const SizedBox(height: 16),
                Text(
                  l10n.logStatistics,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                ...logSummary.entries.map((e) => Text('${e.key}: ${e.value}')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.error(context, l10n.getDebugInfoFailed(e.toString()));
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 用 tertiaryContainer 承载这张庆祝卡片：M3 里 tertiary 正是为点缀性强调
    // 准备的色槽，既比普通设置卡醒目，又跟着用户的主题色走。
    // 此前这里是硬编码的 Tailwind indigo/slate 色板加两层 RadialGradient 光晕，
    // 既无视主题色，浅色模式下几乎全白的底也让白色笔记本插画糊进背景。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        color: colorScheme.tertiaryContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showAnniversaryAnimationInSettings(context),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // 左侧：笔记本插画
                const AnniversaryNotebookIcon(),
                const SizedBox(width: 20),
                // 右侧：文本和指示器
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.anniversaryBannerTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatAnniversaryBannerSubtitleForTile(
                          l10n.anniversaryBannerSubtitle,
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onTertiaryContainer
                              .withValues(alpha: 0.75),
                          height: 1.4,
                        ),
                        softWrap: true,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            l10n.anniversaryBannerTap,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: colorScheme.onTertiaryContainer,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAnniversaryAnimationInSettings(BuildContext context) {
    showAnniversaryAnimationOverlay(context);
  }
}
