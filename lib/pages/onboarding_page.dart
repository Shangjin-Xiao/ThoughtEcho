import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/clipboard_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/log_service.dart'; // 添加 LogService 导入
import '../theme/app_theme.dart';
import 'home_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLocationPermissionEnabled = false;
  bool _isClipboardMonitoringEnabled = false;
  final List<String> _selectedHitokotoTypes = ['a','b','c','d','e','f','g','h','i','j','k'];
  
  bool _isFinishing = false; // 添加状态，防止重复点击
  
  // 用于交互式引导
  bool _hasCompletedAddTask = false; // 确认 _hasCompletedCopyTask 已被注释或删除
  
  // 用于延迟加载和显示过渡效果
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    // 添加延迟加载效果
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) { // 调整页数判断
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
      final logService = Provider.of<LogService>(context, listen: false);

      // 1. 保存用户在引导页选择的设置
      _saveSettings();

      // 2. 执行数据库初始化/迁移（如果尚未完成）
      if (!settingsService.isInitialDatabaseSetupComplete()) {
        debugPrint('开始执行引导流程中的数据库初始化/迁移...');
        try {
          // 初始化数据库（包含迁移逻辑）
          await databaseService.init();
          debugPrint('数据库初始化/迁移完成');

          // 初始化默认分类
          await databaseService.initDefaultHitokotoCategories();
          debugPrint('默认一言分类初始化完成');

          // 补全旧数据字段
          await databaseService.patchQuotesDayPeriod();
          debugPrint('旧数据 dayPeriod 字段补全完成');

          // 标记数据库设置完成
          await settingsService.setInitialDatabaseSetupComplete(true);
          debugPrint('数据库初始设置标记完成');

        } catch (e, stackTrace) {
          debugPrint('引导流程中数据库操作失败: $e');
          // 使用 mounted 检查
          if (mounted) {
            logService.error('引导流程数据库操作失败', error: e, stackTrace: stackTrace);
          }
          // 即使失败，也标记为完成，防止卡在引导页
          await settingsService.setInitialDatabaseSetupComplete(true);
          // 可以考虑显示错误提示
          // 使用 mounted 检查
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('数据库设置时遇到问题，部分功能可能受限'), backgroundColor: Colors.orange),
            );
          }
        }
      } else {
        debugPrint('数据库初始设置已完成，跳过初始化/迁移步骤');
      }

      // 3. 标记引导流程完成
      await settingsService.setHasCompletedOnboarding(true);
      debugPrint('引导流程标记完成');

      // 关闭加载指示器
      if (mounted) Navigator.pop(context);

      // 4. 导航到主页
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }

    } catch (e, stackTrace) {
      debugPrint('完成引导流程时出错: $e');
      // 使用 mounted 检查
      if (mounted) {
        final logService = Provider.of<LogService>(context, listen: false);
        logService.error('完成引导流程失败', error: e, stackTrace: stackTrace);
        // 关闭加载指示器
        Navigator.pop(context);
        // 显示错误提示
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('完成引导时出错，请稍后重试'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isFinishing = false; // 允许重试
      });
    }
  }

  void _saveSettings() {
    try {
      // 保存位置权限设置
      if (_isLocationPermissionEnabled) {
        final locationService = Provider.of<LocationService>(context, listen: false);
        locationService.requestLocationPermission(); // 异步请求，不阻塞
      }
      
      // 保存剪贴板监控设置
      final clipboardService = Provider.of<ClipboardService>(context, listen: false);
      clipboardService.setEnableClipboardMonitoring(_isClipboardMonitoringEnabled);
      
      // 保存一言类型设置
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      final hitokotoType = _selectedHitokotoTypes.join(',');
      settingsService.updateHitokotoType(hitokotoType);
      debugPrint('引导页设置已保存');
    } catch (e) {
      debugPrint('保存引导页设置时出错: $e');
      // 记录错误，但不阻塞流程
      // 使用 mounted 检查
      if (mounted) {
        final logService = Provider.of<LogService>(context, listen: false);
        logService.info('保存引导页设置失败', error: e); // 将 warn 改为 info
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
              // 页面内容
              PageView(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildWelcomePage(theme),
                  _buildPermissionsPage(theme),
                  _buildHitokotoSettingsPage(theme),
                  _buildInteractiveGuidePage(theme),
                ],
              ),
              
              // 底部导航按钮
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
                      
                      // 页面指示器 (改为4页)
                      Row(
                        children: List.generate(4, (index) { // 页数改为4
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
                      
                      // 下一步/完成按钮 (改为判断 < 3)
                      _currentPage < 3 // 页数改为3
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
              
              // 跳过按钮
              Positioned(
                top: 10,
                right: 10,
                child: _currentPage < 3 // 改为判断 < 3
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

  // 第一页：欢迎页面
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
            Text(
              '让我们一起，随心迹录！',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // 第二页：权限申请页面
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
          
          // 位置权限 - 更现代化的UI
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            margin: const EdgeInsets.only(bottom: 16),
            child: SwitchListTile(
              value: _isLocationPermissionEnabled,
              onChanged: (value) {
                setState(() {
                  _isLocationPermissionEnabled = value;
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
                  '用于获取本地天气信息和在笔记中记录位置',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              secondary: Icon(
                _isLocationPermissionEnabled ? Icons.check_circle : Icons.circle_outlined,
                color: _isLocationPermissionEnabled ? Colors.green : theme.colorScheme.outline,
              ),
            ),
          ),
          
          // 剪贴板权限
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
          
          // 权限说明
          Container(
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

  // 第三页：一言设置页面
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
          
          // 预览示例
          if (_selectedHitokotoTypes.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(100),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(
                  color: theme.colorScheme.primary.withAlpha(60),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '预览示例',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.format_quote,
                        color: theme.colorScheme.primary,
                        size: 18,
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    _getRandomHitokotoExample(),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '——《心迹》',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          
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
                      // 确保至少选择一种类型
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
  
  // 生成随机一言示例
  String _getRandomHitokotoExample() {
    const examples = [
      "人生最曼妙的风景，是内心的淡定与从容。",
      "有些烦恼，挥一挥手，就过去了。",
      "真正的梦就是现实的彼岸。",
      "不为模糊不清的未来担忧，只为清清楚楚的现在努力。",
      "生活真象这杯浓酒，不经三番五次的提炼呵，就不会这样可口！",
    ];
    
    return examples[DateTime.now().millisecond % examples.length];
  }

  // 第四页（原第五页）：交互式引导页面
  Widget _buildInteractiveGuidePage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: SingleChildScrollView(  // 添加滚动支持防止溢出
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快速上手',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '来体验心迹的核心功能！',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            
            // 笔记添加模拟
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              ),
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '快速添加笔记',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.note_add,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  // 双击区域演示
                  GestureDetector(
                    onDoubleTap: () {
                      if (!_hasCompletedAddTask) {
                        setState(() {
                          _hasCompletedAddTask = true;
                        });
                        
                        // 显示添加成功的动画
                        showModalBottomSheet(
                          context: context,
                          builder: (context) => Container(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  '笔记已添加到收藏!',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '在应用中，双击任意内容可以快速添加到笔记',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('了解了'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withAlpha(100),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withAlpha(100),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.touch_app, size: 30),
                          const SizedBox(height: 8),
                          Text(
                            '双击这里添加到笔记',
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '把这句话收藏到您的笔记中',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 任务完成状态 (只判断 _hasCompletedAddTask)
            if (_hasCompletedAddTask)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '您的完成进度：',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTaskProgressItem(
                      theme,
                      '双击添加到笔记',
                      _hasCompletedAddTask,
                    ),
                  ],
                ),
              ),
              
            if (_hasCompletedAddTask) // 只判断 _hasCompletedAddTask
              Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(40),
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        '恭喜！您已完成所有交互引导，点击"完成"开启心迹之旅！',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 70), // 为底部按钮留出空间
          ],
        ),
      ),
    );
  }
  
  // 任务进度显示部件
  Widget _buildTaskProgressItem(ThemeData theme, String taskName, bool isCompleted) {
    return Row(
      children: [
        Icon(
          isCompleted ? Icons.check_circle : Icons.circle_outlined,
          color: isCompleted ? Colors.green : theme.colorScheme.outline,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            taskName,
            style: theme.textTheme.bodyMedium?.copyWith(
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              color: isCompleted
                  ? theme.colorScheme.onSurface.withAlpha((255 * 0.7).round()) // 使用 withAlpha
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}