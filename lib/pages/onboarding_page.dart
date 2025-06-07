import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart'; // 导入版本信息包

import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/mmkv_service.dart'; // 导入 MMKV 服务
import '../services/clipboard_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart'; // 使用新的统一日志服务
import '../theme/app_theme.dart';
import 'home_page.dart';
import '../models/app_settings.dart'; // 导入 AppSettings

class OnboardingPage extends StatefulWidget {
  final bool showUpdateReady; // 是否只显示最后一页（升级提示）
  final bool showFullOnboarding; // 是否完整引导
  const OnboardingPage({super.key, this.showUpdateReady = false, this.showFullOnboarding = false});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  PermissionStatus _locationPermissionStatus = PermissionStatus.denied; // 跟踪权限状态
  bool _isLocationPermissionEnabled = false;
  bool _isClipboardMonitoringEnabled = false;
  final List<String> _selectedHitokotoTypes = ['a','b','c','d','e','f','g','h','i','j','k'];
  int _selectedStartPage = AppSettings.defaultSettings().defaultStartPage; // 使用 AppSettings.defaultSettings() 获取默认值
  
  bool _isFinishing = false; // 添加状态，防止重复点击
  
  // 用于延迟加载和显示过渡效果
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    // 检查初始权限状态
    _checkInitialLocationPermission();
    // 确保初始化时启用动态取色功能
    // 新版本更新时，只跳转到最后一页，但不自动关闭
    if (widget.showUpdateReady && !widget.showFullOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 只跳转到最后页面，不自动执行_finishOnboarding
        _pageController.jumpToPage(3);
        
        // 移除自动执行迁移和结束的代码
        // await Future.delayed(const Duration(milliseconds: 600));
        // if (mounted) {
        //   _finishOnboarding();
        // }
      });
    }
    // 添加延迟加载效果
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
      }
    });
  }

  // 检查初始位置权限状态
  Future<void> _checkInitialLocationPermission() async {
    final status = await Permission.location.status;
    if (mounted) {
      setState(() {
        _locationPermissionStatus = status;
              _isLocationPermissionEnabled = _locationPermissionStatus.isGranted || _locationPermissionStatus.isLimited;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    // 页数仍然是 4 页 (0, 1, 2, 3)
    if (_currentPage < 3) { 
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    if (_isFinishing) return; // 防止重复执行
    setState(() {
      _isFinishing = true;
    });

    // 显示加载指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      final mmkvService = Provider.of<MMKVService>(context, listen: false); // 获取 MMKV 服务

      // --- 版本检查与迁移逻辑 ---
      const String mmkvKeyLastRunVersion = 'lastRunVersionBuildNumber';
      const int migrationNeededFromBuildNumber = 12; // *** 定义需要迁移的起始版本号 ***

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentBuildNumberString = packageInfo.buildNumber;
      int currentBuildNumber = int.tryParse(currentBuildNumberString) ?? 0;

      String lastRunBuildNumberString = mmkvService.getString(mmkvKeyLastRunVersion) ?? '0';
      int lastRunBuildNumber = int.tryParse(lastRunBuildNumberString) ?? 0;

      bool isFirstSetup = !settingsService.isInitialDatabaseSetupComplete();
      bool isUpdateRequiringMigration = currentBuildNumber > lastRunBuildNumber && currentBuildNumber >= migrationNeededFromBuildNumber;
      bool needsMigration = isFirstSetup || isUpdateRequiringMigration;

      debugPrint('版本检查: 当前版本=$currentBuildNumber, 上次运行版本=$lastRunBuildNumber, 是否首次设置=$isFirstSetup, 是否需要迁移=$needsMigration');

      try {
        // 确保数据库已初始化
        await databaseService.init();
        debugPrint('数据库初始化完成 (引导流程)');
        
        // 添加此行: 明确初始化默认一言分类标签
        await databaseService.initDefaultHitokotoCategories();
        debugPrint('引导流程中已显式初始化默认一言分类标签');

        if (needsMigration) {
          debugPrint('开始执行引导流程中的数据迁移...');
          try {
            // 确保数据库已完全初始化后再执行迁移
            if (!databaseService.isInitialized) {
              throw Exception('数据库未完全初始化，无法执行迁移');
            }

            // 补全旧数据字段
            await databaseService.patchQuotesDayPeriod();
            debugPrint('旧数据 dayPeriod 字段补全完成');

            // 迁移旧weather字段为key
            await databaseService.migrateWeatherToKey();
            debugPrint('旧weather字段已迁移为key');

            // 迁移旧dayPeriod字段为key
            await databaseService.migrateDayPeriodToKey();
            debugPrint('旧dayPeriod字段已迁移为key');

            // 如果是首次设置，标记完成
            if (isFirstSetup) {
              await settingsService.setInitialDatabaseSetupComplete(true);
              debugPrint('数据库初始设置标记完成');
            }

            // 重要：标记数据库迁移已完成，避免重复迁移
            await settingsService.setDatabaseMigrationComplete(true);
            debugPrint('数据迁移成功完成，已标记迁移状态');          } catch (e, stackTrace) {
            debugPrint('引导流程中数据迁移失败: $e');
            logError('引导流程数据迁移失败', error: e, stackTrace: stackTrace, source: 'OnboardingPage');

            // 即使迁移失败，如果是首次设置，也标记完成，避免阻塞
            if (isFirstSetup) {
              await settingsService.setInitialDatabaseSetupComplete(true);
              // 对于新用户，即使迁移失败也标记迁移完成，因为没有旧数据需要迁移
              await settingsService.setDatabaseMigrationComplete(true);
              debugPrint('首次设置：即使迁移失败也标记完成，避免阻塞新用户');
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('数据格式更新时遇到问题'), backgroundColor: Colors.orange),
              );
            }
          }
        } else {
          debugPrint('无需执行数据迁移');
          // 即使无需迁移，也要确保标记迁移完成状态
          if (!settingsService.isDatabaseMigrationComplete()) {
            await settingsService.setDatabaseMigrationComplete(true);
            debugPrint('无需迁移，已标记迁移完成状态');
          }
        }

        // 迁移检查/执行完成后，如果版本号增加了，更新记录
        if (currentBuildNumber > lastRunBuildNumber) {
           await mmkvService.setString(mmkvKeyLastRunVersion, currentBuildNumberString);
           debugPrint('已更新上次运行版本号记录为: $currentBuildNumberString');
        }      } catch (e, stackTrace) {
         debugPrint('引导流程中数据库初始化失败: $e');
         logError('引导流程数据库初始化失败', error: e, stackTrace: stackTrace, source: 'OnboardingPage');
         // 即使初始化失败，也标记完成首次设置，避免卡住引导
         if (isFirstSetup) {
            await settingsService.setInitialDatabaseSetupComplete(true);
         }
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('数据库初始化时遇到问题'), backgroundColor: Colors.orange),
           );
         }
      }
      // --- 版本检查与迁移逻辑结束 ---


      // 1. 保存用户在引导页选择的设置 (包括启动页) - 移到迁移逻辑之后
      if (!widget.showUpdateReady || widget.showFullOnboarding) {
        await _saveSettings();
      }

      // 2. 标记引导流程完成（仅完整引导时设置） - 原来的步骤3
      if (!widget.showUpdateReady || widget.showFullOnboarding) {
        await settingsService.setHasCompletedOnboarding(true);
        debugPrint('引导流程标记完成');
      }

      // 关闭加载指示器
      if (mounted) Navigator.pop(context);

      // 4. 导航到主页
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }    } catch (e, stackTrace) {
      debugPrint('完成引导流程时出错: $e');
      if (mounted) {
        logError('完成引导流程失败', error: e, stackTrace: stackTrace, source: 'OnboardingPage');
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('完成引导时出错，请稍后重试'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isFinishing = false; // 允许重试
      });
    }
  }

  // 修改 _saveSettings 以包含启动页
  Future<void> _saveSettings() async { 
    try {
      // 保存位置权限设置 - 注意：实际权限在开关切换时请求
      // 这里可以考虑保存用户 *期望* 的状态，但实际状态由系统权限决定
      
      // 保存剪贴板监控设置 - setEnableClipboardMonitoring 是同步方法，移除 await
      final clipboardService = Provider.of<ClipboardService>(context, listen: false);
      clipboardService.setEnableClipboardMonitoring(_isClipboardMonitoringEnabled);
      
      // 保存一言类型设置
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      final hitokotoType = _selectedHitokotoTypes.join(',');
      await settingsService.updateHitokotoType(hitokotoType);

      // 保存默认启动页面设置
      final currentAppSettings = settingsService.appSettings;
      await settingsService.updateAppSettings(
        currentAppSettings.copyWith(defaultStartPage: _selectedStartPage)
      );

      debugPrint('引导页设置已保存');    } catch (e) {
      debugPrint('保存引导页设置时出错: $e');
      // 记录错误，但不阻塞流程
      // 使用 mounted 检查
      if (mounted) { // 添加 mounted 检查
        logInfo('保存引导页设置失败', source: 'OnboardingPage'); // 将 warn 改为 info
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 添加动画过渡效果
    return AnimatedOpacity(
      opacity: _isLoaded ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 500),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // 页面内容 - 更新 children
              PageView(
                controller: _pageController,
                physics: widget.showUpdateReady && !widget.showFullOnboarding ? const NeverScrollableScrollPhysics() : null,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildWelcomePage(theme),
                  _buildPermissionsPage(theme),
                  _buildHitokotoSettingsPage(theme),
                  _buildStartPageSelectionPage(theme), // 替换为启动页选择
                  _buildLastPage(),
                ],
              ),
              
              // 底部导航按钮 - 保持不变 (页数仍为4)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.scaffoldBackgroundColor.withAlpha(0),
                        theme.scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 后退按钮
                      _currentPage > 0
                          ? TextButton.icon(
                              onPressed: _isFinishing ? null : _previousPage, // 禁用按钮
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('上一步'),
                            )
                          : const SizedBox(width: 90), // 占位符
                      
                      // 页面指示器 (仍为4页)
                      Row(
                        children: List.generate(4, (index) { 
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == index ? 12 : 8,
                            height: _currentPage == index ? 12 : 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == index
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withAlpha(70),
                            ),
                          );
                        }),
                      ),
                      
                      // 下一步/完成按钮 (判断 < 3)
                      _currentPage < 3 
                          ? FilledButton.icon(
                              onPressed: _isFinishing ? null : _nextPage, // 禁用按钮
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('下一步'),
                            )
                          : FilledButton.icon(
                              onPressed: _isFinishing ? null : _finishOnboarding, // 禁用按钮
                              icon: _isFinishing 
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check),
                              label: Text(_isFinishing ? '请稍候...' : '开始使用'),
                            ),
                    ],
                  ),
                ),
              ),
              
              // 跳过按钮 - 保持不变 (判断 < 3)
              Positioned(
                top: 10,
                right: 10,
                child: _currentPage < 3 
                    ? TextButton.icon(
                        onPressed: _isFinishing ? null : () { // 禁用按钮
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('跳过引导'),
                              content: const Text('您确定要跳过引导直接进入应用吗？\n部分设置将使用默认值。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _finishOnboarding(); // 跳过也执行完成逻辑
                                  },
                                  child: const Text('确定跳过'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.skip_next),
                        label: const Text('跳过'),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 第一页：欢迎页面 - 保持不变
  Widget _buildWelcomePage(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(  // 添加滚动支持防止溢出
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 应用图标 - 使用正确路径加载图标
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Image.asset(
                'assets/icon.png',  // 确保路径正确
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                // 减少不必要的错误处理代码，使用简单图标替代
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('图标加载错误: $error');
                  return Icon(
                    Icons.auto_stories,
                    size: 80,
                    color: theme.colorScheme.primary,
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
            
            // 欢迎标题
            Text(
              '欢迎使用心迹',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            
            // 欢迎文字
            Text(
              '记录生活点滴，留存思想灵感',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            // Text( // Removed from here
            //   '让我们一起，随心迹录！',
            //   style: theme.textTheme.bodyLarge,
            //   textAlign: TextAlign.center,
            // ),
          ],
        ),
      ),
    );
  }

  // 第二页：权限申请页面 - 修改位置权限逻辑
  Widget _buildPermissionsPage(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '核心权限',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '为了提供完整体验，心迹需要以下权限：',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          
          // 位置权限 - 修改 onChanged
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            margin: const EdgeInsets.only(bottom: 16),
            child: SwitchListTile(
              value: _isLocationPermissionEnabled,
              onChanged: (value) async { 
                final locationService = Provider.of<LocationService>(context, listen: false);
                dynamic status;
                if (value) {
                  // 请求权限
                  final result = await locationService.requestLocationPermission();
                  if (result is PermissionStatus) {
                    status = result;
                  } else {
                    status = result ? PermissionStatus.granted : PermissionStatus.denied;
                  }
                
                } else {
                  // 用户关闭开关，可以视为拒绝，或者引导去设置
                  status = PermissionStatus.denied;
                  // 可选：如果需要，引导用户去系统设置关闭权限
                  // openAppSettings(); 
                }
                // 更新UI状态
                if (mounted) {
                  setState(() {
                    if (status is PermissionStatus) {
                      _locationPermissionStatus = status;
                      _isLocationPermissionEnabled = status.isGranted || status.isLimited;
                    } else if (status is bool) {
                      _locationPermissionStatus = status ? PermissionStatus.granted : PermissionStatus.denied;
                      _isLocationPermissionEnabled = status ? true : false;
                    } else {
                      _locationPermissionStatus = PermissionStatus.denied;
                      _isLocationPermissionEnabled = false;
                    }
                  });
                }
              },
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.location_on,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '位置权限',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _getLocationSubtitle(), // 根据状态显示不同文本
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              secondary: Icon(
                _isLocationPermissionEnabled ? Icons.check_circle : Icons.circle_outlined,
                color: _isLocationPermissionEnabled ? Colors.green : theme.colorScheme.outline,
              ),
            ),
          ),
          
          // 剪贴板权限 - 保持不变
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            margin: const EdgeInsets.only(bottom: 16),
            child: SwitchListTile(
              value: _isClipboardMonitoringEnabled,
              onChanged: (value) {
                setState(() {
                  _isClipboardMonitoringEnabled = value;
                });
              },
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.content_paste,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '剪贴板监控',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '检测剪贴板内容，方便快速添加到笔记中',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              secondary: Icon(
                _isClipboardMonitoringEnabled ? Icons.check_circle : Icons.circle_outlined,
                color: _isClipboardMonitoringEnabled ? Colors.green : theme.colorScheme.outline,
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 权限说明 - 保持不变
          Container(
            // ... (代码不变) ...
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: theme.colorScheme.outline.withAlpha(100),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '关于权限',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• 所有权限均为可选，您可以随时在应用设置中更改',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '• 我们非常重视您的隐私，所有数据都存储在您的设备上',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '• 位置信息仅用于获取天气和记录笔记位置',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 根据权限状态获取位置权限的副标题
  String _getLocationSubtitle() {
    switch (_locationPermissionStatus) {
      case PermissionStatus.granted:
      case PermissionStatus.limited: // Limited access is also considered enabled
        return '已授权。用于获取天气和记录位置。';
      case PermissionStatus.denied:
        return '用于获取本地天气信息和在笔记中记录位置';
      case PermissionStatus.permanentlyDenied:
        return '权限已被永久拒绝，请在系统设置中开启';
      case PermissionStatus.restricted:
        return '权限受限 (例如家长控制)';
      default:
        return '用于获取本地天气信息和在笔记中记录位置';
    }
  }

  // 第三页：一言设置页面 - 保持不变
  Widget _buildHitokotoSettingsPage(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每日一言',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '选择您感兴趣的内容类型：',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          
          // 快速操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedHitokotoTypes.clear();
                      for (final key in ApiService.hitokotoTypes.keys) {
                        _selectedHitokotoTypes.add(key);
                      }
                    });
                  },
                  icon: const Icon(Icons.select_all),
                  label: const Text('全选'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedHitokotoTypes.clear();
                      _selectedHitokotoTypes.add('a'); // 至少选一个
                    });
                  },
                  icon: const Icon(Icons.deselect),
                  label: const Text('清除全部'),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 类型选择网格
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ApiService.hitokotoTypes.entries.map((entry) {
              final isSelected = _selectedHitokotoTypes.contains(entry.key);
              return FilterChip(
                label: Text(entry.value),
                selected: isSelected,
                showCheckmark: false,
                avatar: isSelected ? const Icon(Icons.check, size: 16) : null,
                labelStyle: TextStyle(
                  color: isSelected ? theme.colorScheme.onPrimary : null,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: theme.colorScheme.surface,
                selectedColor: theme.colorScheme.primary,
                onSelected: (bool selected) {
                  setState(() {
                    if (selected) {
                      _selectedHitokotoTypes.add(entry.key);
                    } else {
                      _selectedHitokotoTypes.remove(entry.key);
                      if (_selectedHitokotoTypes.isEmpty) {
                        _selectedHitokotoTypes.add('a');
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),
          
          const SizedBox(height: 24),
          
          // 类型说明
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: theme.colorScheme.outline.withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '关于每日一言',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '每日一言是心迹的特色功能，可以在首页展示精选名言、诗词和金句，为您的一天带来灵感。选择您感兴趣的类型，系统将从中随机展示内容。',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 新增：第四页 - 默认启动页面选择
  Widget _buildStartPageSelectionPage(ThemeData theme) {
    // 定义启动页选项 - Key 修改为 int
    final Map<int, String> startPageOptions = { 
      0: '主页概览', // 0 代表主页
      1: '笔记列表', // 1 代表笔记列表
      // 2: '日历视图', // 如果有日历视图可以取消注释
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '个性化设置',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '选择您希望打开应用时首先看到的页面：',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          
          // 使用 Card 包裹选项
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0), // 给内部一些垂直间距
              child: Column(
                children: startPageOptions.entries.map((entry) {
                  // 修改 RadioListTile 的类型为 int
                  return RadioListTile<int>( 
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: _selectedStartPage,
                    onChanged: (int? value) { // 修改类型为 int?
                      if (value != null) {
                        setState(() {
                          _selectedStartPage = value;
                        });
                      }
                    },
                    activeColor: theme.colorScheme.primary,
                  );
                }).toList(),
              ),
            ),
          ),
          
          const SizedBox(height: 24),

          // 新增：核心操作提示 - 修改提示文本
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withAlpha(100),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: theme.colorScheme.secondary.withAlpha(60)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      color: theme.colorScheme.secondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '核心操作提示',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  // 修改提示文本，添加单击复制
                  '💡 在主屏幕单击「每日一言」卡片可复制内容，双击则可将其快速添加到笔记！', 
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 说明文字
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(color: theme.colorScheme.outline.withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '提示',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '您可以随时在应用的设置页面更改默认启动页。',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24), // 在提示和 Slogan 之间添加间距
          Text( // 添加 Slogan
            '让我们一起，随心迹录！',
            style: theme.textTheme.titleLarge?.copyWith( // 使用 titleLarge 增大字号
              color: theme.colorScheme.primary, // 改用主色调
              fontWeight: FontWeight.bold, // 加粗
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16), // 在 Slogan 和版本提示之间添加间距 (如果显示)

          // 新增：如果是版本升级后进入，显示新版提示
          if (widget.showUpdateReady)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 24), // 调整版本提示的边距
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: theme.colorScheme.primary.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(Icons.new_releases, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '🎉 新版本已准备就绪！欢迎体验更多新功能和优化。',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 50), // 稍微减少底部按钮的空间，因为增加了 Slogan
        ],
      ),
    );
  }

  // 最后一页
  Widget _buildLastPage() {
    final theme = Theme.of(context);
    final isUpdate = widget.showUpdateReady && !widget.showFullOnboarding;
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isUpdate ? Icons.upgrade : Icons.emoji_emotions,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            isUpdate ? '程序已更新' : '欢迎使用心迹',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            isUpdate
                ? '程序已成功升级至新版本，数据已自动迁移，无需手动操作。\n\n如遇到任何问题，请在设置页反馈。'
                : '你已完成所有设置，随时可以开始记录和探索你的思想。',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          // Added the text here for the non-update case
          if (!isUpdate) ...[
            const SizedBox(height: 10),
            Text(
              '让我们一起，随心迹录！',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isFinishing ? null : _finishOnboarding,
            child: Text(isUpdate ? '进入应用' : '开始使用'),
          ),
        ],
      ),
    );
  }
}