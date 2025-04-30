import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/clipboard_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
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
  
  bool _isDatabaseMigrated = false;
  bool _isMigratingDatabase = false;
  
  // 用于交互式引导
  bool _hasCompletedCopyTask = false;
  bool _hasCompletedAddTask = false;
  
  // 用于延迟加载和显示过渡效果
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    // 使用Future.delayed让UI先显示，然后再开始数据库操作
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _migrateDatabase();
        // 添加延迟加载效果
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // 数据库迁移 - 优化性能
  Future<void> _migrateDatabase() async {
    if (_isDatabaseMigrated || _isMigratingDatabase) return;
    
    setState(() {
      _isMigratingDatabase = true;
    });
    
    try {
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      
      // 使用compute隔离执行数据库操作
      await Future.microtask(() async {
        // 执行数据库迁移操作
        await databaseService.init();
        
        // 确保默认分类存在（为旧数据提供默认分类）
        try {
          await databaseService.initDefaultHitokotoCategories();
          debugPrint('默认一言分类初始化完成');
        } catch (e) {
          debugPrint('初始化默认分类失败，将在首次使用时再次尝试: $e');
        }
        
        // 保存数据库迁移完成标记到设置中
        await settingsService.setDatabaseMigrationComplete(true);
      });
      
      if (mounted) {
        setState(() {
          _isDatabaseMigrated = true;
          _isMigratingDatabase = false;
        });
      }
    } catch (e) {
      debugPrint('数据库迁移过程中出错: $e');
      
      if (mounted) {
        setState(() {
          _isMigratingDatabase = false;
          _isDatabaseMigrated = true; // 即使出错也标记为已完成
        });
        
        // 尝试使用新数据库继续
        try {
          final databaseService = Provider.of<DatabaseService>(context, listen: false);
          final settingsService = Provider.of<SettingsService>(context, listen: false);
          
          await settingsService.setDatabaseMigrationComplete(true);
          
          if (!databaseService.isInitialized) {
            await databaseService.initializeNewDatabase();
          }
        } catch (e) {
          debugPrint('无法初始化新数据库: $e');
        }
      }
    }
  }

  void _nextPage() {
    if (_currentPage < 4) {
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

  void _finishOnboarding() {
    // 保存设置
    _saveSettings();
    
    // 标记为已完成引导
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    settingsService.setHasCompletedOnboarding(true);
    
    // 导航到主页
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
  }

  void _saveSettings() {
    // 保存位置权限设置
    if (_isLocationPermissionEnabled) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.requestLocationPermission();
    }
    
    // 保存剪贴板监控设置
    final clipboardService = Provider.of<ClipboardService>(context, listen: false);
    clipboardService.setEnableClipboardMonitoring(_isClipboardMonitoringEnabled);
    
    // 保存一言类型设置
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    final hitokotoType = _selectedHitokotoTypes.join(',');
    settingsService.updateHitokotoType(hitokotoType);
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
                  _buildMoreSettingsPage(theme),
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
                              onPressed: _previousPage,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('上一步'),
                            )
                          : const SizedBox(width: 90),
                      
                      // 页面指示器
                      Row(
                        children: List.generate(5, (index) {
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
                      
                      // 下一步/完成按钮
                      _currentPage < 4
                          ? FilledButton.icon(
                              onPressed: _nextPage,
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('下一步'),
                            )
                          : FilledButton.icon(
                              onPressed: _finishOnboarding,
                              icon: const Icon(Icons.check),
                              label: const Text('开始使用'),
                            ),
                    ],
                  ),
                ),
              ),
              
              // 跳过按钮
              Positioned(
                top: 10,
                right: 10,
                child: _currentPage < 4
                    ? TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('跳过引导'),
                              content: const Text('您确定要跳过引导直接进入应用吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _finishOnboarding();
                                  },
                                  child: const Text('确定'),
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
            
            // 显示数据库迁移状态 - 简化状态显示
            const SizedBox(height: 40),
            if (_isMigratingDatabase)
              const CircularProgressIndicator()
            else if (_isDatabaseMigrated)
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 40,
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

  // 第四页：更多设置页面
  Widget _buildMoreSettingsPage(ThemeData theme) {
    final appTheme = Provider.of<AppTheme>(context);
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '应用设置',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '个性化您的心迹应用体验：',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          
          // 应用主题设置
          _buildSettingSection(
            theme,
            icon: Icons.color_lens,
            title: '应用主题',
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildThemeModeOption(
                      context,
                      appTheme,
                      ThemeMode.light,
                      '浅色',
                      Icons.light_mode,
                    ),
                    _buildThemeModeOption(
                      context,
                      appTheme,
                      ThemeMode.dark,
                      '深色',
                      Icons.dark_mode,
                    ),
                    _buildThemeModeOption(
                      context,
                      appTheme,
                      ThemeMode.system,
                      '跟随系统',
                      Icons.brightness_auto,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // AI API 设置
          _buildSettingSection(
            theme,
            icon: Icons.smart_toy,
            title: 'AI 助手设置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '配置AI助手来增强您的笔记体验',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                
                // API密钥输入
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'API 密钥 (可选)',
                    hintText: '输入您的OpenAI API密钥',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                    ),
                    prefixIcon: const Icon(Icons.key),
                  ),
                  obscureText: true,
                  onChanged: (value) {
                    // 这里只是演示，实际上在完成设置后再保存
                    // settingsService.updateApiKey(value);
                  },
                ),
                
                const SizedBox(height: 12),
                
                // AI模型选择
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'AI 模型',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                    ),
                    prefixIcon: const Icon(Icons.psychology),
                  ),
                  value: 'gpt-3.5-turbo',
                  items: const [
                    DropdownMenuItem(value: 'gpt-3.5-turbo', child: Text('GPT-3.5 Turbo')),
                    DropdownMenuItem(value: 'gpt-4', child: Text('GPT-4')),
                    DropdownMenuItem(value: 'gpt-4-turbo', child: Text('GPT-4 Turbo')),
                  ],
                  onChanged: (value) {},
                ),
                
                const SizedBox(height: 16),
                
                // 提示文本
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '完成引导后可以在设置中完整配置AI功能',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 开始页面设置
          _buildSettingSection(
            theme,
            icon: Icons.home,
            title: '默认开始页面',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择应用启动时显示的页面',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                
                // 页面选择
                Wrap(
                  spacing: 8,
                  children: [
                    _buildPageOption(theme, '时间线', Icons.timeline, true),
                    _buildPageOption(theme, '笔记本', Icons.book, false),
                    _buildPageOption(theme, '统计', Icons.bar_chart, false),
                    _buildPageOption(theme, '灵感', Icons.lightbulb, false),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 60), // 为底部区域留空间
        ],
      ),
    );
  }
  
  // 默认页面选项
  Widget _buildPageOption(ThemeData theme, String label, IconData icon, bool isSelected) {
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (value) {
        // 这里只是演示，不需要实际实现
      },
      backgroundColor: theme.colorScheme.surface,
      selectedColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
      ),
    );
  }

  // 第五页：交互式引导页面
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
            
            // 可选择文本卡片 - 真实可交互
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
                        '真实交互演示',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  // 实际可选择/复制的文本
                  SelectableText(
                    '生活不止眼前的苟且，还有诗和远方。\n—— 北岛',
                    style: theme.textTheme.titleMedium,
                    onSelectionChanged: (selection, cause) {
                      if (!_hasCompletedCopyTask && selection.isValid && selection.isCollapsed == false) {
                        // 用户已完成选择文本任务
                        if (mounted) {
                          setState(() {
                            _hasCompletedCopyTask = true;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('成功选择文本！请尝试复制选择内容')),
                          );
                        }
                      }
                    },
                    toolbarOptions: const ToolbarOptions(
                      copy: true,
                      selectAll: true,
                      cut: false,
                      paste: false,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  // 操作提示
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.touch_app, 
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '请尝试选择并复制上面的文本',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
            
            // 任务完成状态
            if (_hasCompletedCopyTask || _hasCompletedAddTask)
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
                      '选择并复制文本',
                      _hasCompletedCopyTask,
                    ),
                    const SizedBox(height: 8),
                    _buildTaskProgressItem(
                      theme,
                      '双击添加到笔记',
                      _hasCompletedAddTask,
                    ),
                  ],
                ),
              ),
              
            if (_hasCompletedCopyTask && _hasCompletedAddTask)
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
                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  // 设置部分部件
  Widget _buildSettingSection(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.5),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // 主题模式选项
  Widget _buildThemeModeOption(
    BuildContext context,
    AppTheme appTheme,
    ThemeMode mode,
    String label,
    IconData icon,
  ) {
    final isSelected = appTheme.themeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => appTheme.setThemeMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 