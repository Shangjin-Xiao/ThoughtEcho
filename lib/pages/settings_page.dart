import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
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
import 'trash_page.dart';
import '../widgets/city_search_widget.dart';
import '../controllers/weather_search_controller.dart';
import 'category_settings_page.dart';
import 'annual_report_page.dart';
import 'ai_annual_report_webview.dart';
import 'license_page.dart' as license;
import 'preferences_detail_page.dart';
import 'user_guide_page.dart';
import '../utils/feature_guide_helper.dart';
import 'storage_management_page.dart';
import 'local_ai_settings_page.dart'; // 导入本地 AI 设置页面
import 'smart_push_settings_page.dart'; // 导入智能推送设置页面
import '../widgets/anniversary_animation_overlay.dart'; // 导入一周年动画覆盖层
import '../widgets/anniversary_notebook_icon.dart';
import '../utils/anniversary_banner_text_utils.dart';
import '../utils/anniversary_display_utils.dart';

part 'settings/helper_methods.dart';
part 'settings/dialog_methods.dart';
part 'settings/widget_builders.dart';
part 'settings/annual_report_methods.dart';

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

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final theme = Theme.of(context);

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
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

                // --- 移除主列表中的链接 ListTile ---
                // Padding(...), ListTile(...), ListTile(...)
                // --- 移除结束 ---
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
}
