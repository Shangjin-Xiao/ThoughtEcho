import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/onboarding_controller.dart';
import '../config/onboarding_config.dart';
import '../models/onboarding_models.dart';
import '../widgets/onboarding/page_views.dart';
import '../widgets/onboarding/preferences_page_view.dart';
import '../services/migration_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/mmkv_service.dart';
import '../services/ai_analysis_database_service.dart';
import '../utils/app_logger.dart';
import '../constants/app_constants.dart';
import 'home_page.dart';
import '../utils/lottie_animation_manager.dart';

/// 重构后的新用户引导页面
///
/// 特点：
/// - 简化的3页引导流程
/// - 渐进式信息披露
/// - 科学的用户体验设计
/// - 清晰的代码架构
class OnboardingPage extends StatefulWidget {
  final bool showUpdateReady;
  final bool showFullOnboarding;

  const OnboardingPage({
    super.key,
    this.showUpdateReady = false,
    this.showFullOnboarding = false,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  OnboardingController? _controller;
  AnimationController? _loadingAnimationController;
  Animation<double>? _fadeInAnimation;

  bool _isLoaded = false;
  String? _errorMessage;

  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    // 不在 initState 中初始化，改在 didChangeDependencies 中
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 确保只初始化一次
    if (!_isInitializing && !_isLoaded && _errorMessage == null) {
      _isInitializing = true;
      // 使用 Future.microtask 确保在当前帧完成后执行
      Future.microtask(() => _initializeOnboarding());
    }
  }

  /// 初始化引导流程
  Future<void> _initializeOnboarding() async {
    try {
      if (!mounted) return;

      // 获取 servicesInitializedNotifier
      ValueNotifier<bool>? servicesInitializedNotifier;
      try {
        servicesInitializedNotifier = context.read<ValueNotifier<bool>>();
      } catch (e) {
        logError('无法获取servicesInitializedNotifier: $e', 
            error: e, source: 'OnboardingPage');
        // 创建临时notifier以继续流程
        servicesInitializedNotifier = ValueNotifier<bool>(false);
      }

      final controller = OnboardingController(
        servicesInitializedNotifier: servicesInitializedNotifier,
      );
      _controller = controller;
      
      // 尝试初始化控制器，如果失败则记录详细错误
      try {
        controller.initialize(context);
      } catch (e, stackTrace) {
        logError('OnboardingController初始化失败', 
            error: e, stackTrace: stackTrace, source: 'OnboardingPage');
        throw Exception('控制器初始化失败: $e');
      }

      final loadingController = AnimationController(
        duration: const Duration(milliseconds: 800),
        vsync: this,
      );
      _loadingAnimationController = loadingController;

      _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: loadingController,
          curve: Curves.easeOut,
        ),
      );

      // 如果是更新后显示，直接处理迁移
      if (widget.showUpdateReady && !widget.showFullOnboarding) {
        await _handleUpdateMigration();
      } else {
        // Web平台快速加载，其他平台保持延迟效果
        final loadDelay = kIsWeb 
            ? const Duration(milliseconds: 100)
            : const Duration(milliseconds: 500);
        await Future.delayed(loadDelay);
      }

      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
        _loadingAnimationController?.forward();
      }
    } catch (e, stackTrace) {
      logError('初始化引导失败', error: e, stackTrace: stackTrace, 
          source: 'OnboardingPage');
      if (mounted) {
        setState(() {
          _errorMessage = '初始化失败，请重试';
          _isLoaded = true;
        });
      }
    }
  }

  /// 处理更新后的迁移
  Future<void> _handleUpdateMigration() async {
    try {
      logInfo('处理更新后迁移');

      if (!mounted) return;

      final migrationService = MigrationService(
        databaseService: context.read<DatabaseService>(),
        settingsService: context.read<SettingsService>(),
        mmkvService: context.read<MMKVService>(),
      );

      final result = await migrationService.performMigration();

      if (!mounted) return;

      if (result.isSuccess) {
        logInfo('更新迁移成功完成');

        // 初始化 AI 分析数据库
        try {
          final aiAnalysisDbService = context.read<AIAnalysisDatabaseService>();
          await aiAnalysisDbService.init();
          logInfo('AI分析数据库初始化完成', source: 'OnboardingPage');
        } catch (aiDbError) {
          logError('AI分析数据库初始化失败: $aiDbError',
              error: aiDbError, source: 'OnboardingPage');
        }

        if (!mounted) return;

        // 标记服务初始化完成
        final servicesInitializedNotifier =
            context.read<ValueNotifier<bool>>();
        servicesInitializedNotifier.value = true;

        // 短暂延迟后自动跳转到主页
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          _navigateToHome();
        }
      } else {
        logError('更新迁移失败: ${result.errorMessage}');
        if (mounted) {
          setState(() {
            _errorMessage = '数据更新失败，但您仍可继续使用应用';
          });
        }
      }
    } catch (e) {
      logError('处理更新迁移失败', error: e, source: 'OnboardingPage');
      if (mounted) {
        setState(() {
          _errorMessage = '更新处理失败，请重启应用';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _loadingAnimationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return _buildLoadingView();
    }

    if (_errorMessage != null) {
      return _buildErrorView();
    }

    if (widget.showUpdateReady && !widget.showFullOnboarding) {
      return _buildUpdateCompleteView();
    }

    return _buildOnboardingView();
  }

  /// 加载视图
  Widget _buildLoadingView() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final s = (constraints.maxHeight * 0.4).clamp(48.0, 100.0);
                return EnhancedLottieAnimation(
                  type: LottieAnimationType.pulseLoading,
                  width: s,
                  height: s,
                  semanticLabel: '正在准备',
                );
              },
            ),
            const SizedBox(height: 20),
            Text('正在准备...', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  /// 错误视图
  Widget _buildErrorView() {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 20),
              Text('出现问题', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _navigateToHome,
                child: const Text('继续使用'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 更新完成视图
  Widget _buildUpdateCompleteView() {
    final theme = Theme.of(context);
    final animation = _fadeInAnimation ?? const AlwaysStoppedAnimation(1.0);

    return Scaffold(
      body: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Opacity(
            opacity: animation.value,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.upgrade,
                      size: 80,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      '更新完成',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '心迹已成功更新到新版本\n数据已自动迁移，无需手动操作',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (_errorMessage == null)
                      const EnhancedLottieAnimation(
                        type: LottieAnimationType.pulseLoading,
                        width: 60,
                        height: 60,
                      )
                    else
                      FilledButton(
                        onPressed: _navigateToHome,
                        child: const Text('进入应用'),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 引导视图
  Widget _buildOnboardingView() {
    final controller = _controller;
    if (controller == null) {
      return _buildErrorView();
    }
    final animation = _fadeInAnimation ?? const AlwaysStoppedAnimation(1.0);

    return ChangeNotifierProvider.value(
      value: controller,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Opacity(
            opacity: animation.value,
            child: Consumer<OnboardingController>(
              builder: (context, controller, child) {
                return Scaffold(
                  body: SafeArea(
                    child: Stack(
                      children: [
                        // 页面内容
                        PageView.builder(
                          controller: controller.pageController,
                          onPageChanged: controller.onPageChanged,
                          itemCount: OnboardingConfig.totalPages,
                          itemBuilder: (context, index) {
                            return _buildPageContent(index, controller);
                          },
                        ),

                        // 底部导航
                        _buildBottomNavigation(controller),

                        // 跳过按钮
                        if (!OnboardingConfig.isLastPage(
                          controller.state.currentPageIndex,
                        ))
                          _buildSkipButton(controller),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 构建页面内容
  Widget _buildPageContent(int pageIndex, OnboardingController controller) {
    final state = controller.state;
    final pageData = OnboardingConfig.getPageData(pageIndex);

    switch (pageData.type) {
      case OnboardingPageType.welcome:
        return WelcomePageView(pageData: pageData);
      case OnboardingPageType.features:
        return FeaturesPageView(pageData: pageData);
      case OnboardingPageType.preferences:
        return PreferencesPageView(
          pageData: pageData,
          state: state,
          onPreferenceChanged: controller.updatePreference,
        );
      case OnboardingPageType.complete:
        return _buildCompletePage();
    }
  }

  /// 完成页面
  Widget _buildCompletePage() {
    final theme = Theme.of(context);

    return Consumer<OnboardingController>(
      builder: (context, controller, child) {
        final hitokotoPreference = OnboardingConfig.preferences
            .firstWhere((p) => p.key == 'hitokotoTypes');
        final currentValue =
            controller.state.getPreference<String>('hitokotoTypes') ??
                hitokotoPreference.defaultValue as String;
        final selectedValues =
            currentValue.split(',').where((v) => v.isNotEmpty).toSet();
        final options = hitokotoPreference.options ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 每日一言类型选择 - 放在最上方
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hitokotoPreference.title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '已选择 ${selectedValues.length} 种类型',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hitokotoPreference.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 快速操作按钮
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final allValues = options
                                    .map((o) => o.value as String)
                                    .join(',');
                                controller.updatePreference(
                                  'hitokotoTypes', allValues);
                              },
                              icon: const Icon(Icons.select_all, size: 16),
                              label: const Text('全选'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                // 至少保留一个选项
                                final firstValue = options.isNotEmpty
                                    ? options.first.value as String
                                    : 'a';
                                controller.updatePreference(
                                  'hitokotoTypes', firstValue);
                              },
                              icon: const Icon(Icons.clear_all, size: 16),
                              label: const Text('清空'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: options.map((option) {
                          final isSelected =
                              selectedValues.contains(option.value as String);
                          return FilterChip(
                            label: Text(option.label),
                            selected: isSelected,
                            onSelected: (selected) {
                              final newSelectedValues =
                                  Set<String>.from(selectedValues);
                              if (selected) {
                                newSelectedValues.add(option.value as String);
                              } else {
                                newSelectedValues
                                    .remove(option.value as String);
                                // 确保至少有一个选项被选中
                                if (newSelectedValues.isEmpty) {
                                  newSelectedValues
                                      .add(options.first.value as String);
                                }
                              }
                              final newValue = newSelectedValues.join(',');
                                controller.updatePreference(
                                  'hitokotoTypes', newValue);
                            },
                            backgroundColor: theme.colorScheme.surface,
                            selectedColor: Colors.transparent,
                            checkmarkColor: theme.colorScheme.primary,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                              fontWeight: isSelected
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.3),
                              width: isSelected ? 2.0 : 1.0,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 完成信息 - 放在下方
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 80,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      '设置完成',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '您已完成所有设置\n现在可以开始记录您的思想',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primaryContainer,
                            theme.colorScheme.secondaryContainer,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '让我们一起随心记录',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 底部导航
  Widget _buildBottomNavigation(OnboardingController controller) {
    final theme = Theme.of(context);
    final state = controller.state;

    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 后退按钮
            if (state.canGoPrevious)
              TextButton.icon(
                onPressed: state.isCompleting ? null : controller.previousPage,
                icon: const Icon(Icons.arrow_back),
                label: const Text('上一步'),
              )
            else
              const SizedBox(width: 90),

            // 页面指示器
            Row(
              children: List.generate(OnboardingConfig.totalPages, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: state.currentPageIndex == index ? 12 : 8,
                  height: state.currentPageIndex == index ? 12 : 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.currentPageIndex == index
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                );
              }),
            ),

            // 下一步/完成按钮
            if (OnboardingConfig.isLastPage(state.currentPageIndex))
              FilledButton.icon(
                onPressed:
                    state.isCompleting ? null : controller.completeOnboarding,
                icon: state.isCompleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: EnhancedLottieAnimation(
                          type: LottieAnimationType.loading,
                          width: 18,
                          height: 18,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(state.isCompleting ? '请稍候...' : '开始使用'),
              )
            else
              FilledButton.icon(
                onPressed: state.isCompleting ? null : controller.nextPage,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('下一步'),
              ),
          ],
        ),
      ),
    );
  }

  /// 跳过按钮
  Widget _buildSkipButton(OnboardingController controller) {
    return Positioned(
      top: 20,
      right: 20,
      child: TextButton.icon(
        onPressed: controller.state.isCompleting
            ? null
            : () => _showSkipDialog(controller),
        icon: const Icon(Icons.skip_next),
        label: const Text('跳过'),
      ),
    );
  }

  /// 显示跳过对话框
  void _showSkipDialog(OnboardingController controller) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          return AlertDialog(
            title: const Text('跳过引导'),
            content: controller.state.isCompleting
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EnhancedLottieAnimation(
                        type: LottieAnimationType.loading,
                        width: 60,
                        height: 60,
                      ),
                      SizedBox(height: 16),
                      Text('正在初始化...'),
                    ],
                  )
                : const Text('确定要跳过引导直接进入应用吗？\n部分设置将使用默认值。'),
            actions: controller.state.isCompleting
                ? null
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        try {
                          await controller.skipOnboarding();
                          // 不要手动导航！让 SettingsService.hasCompletedOnboarding() 的变化
                          // 触发 MyApp 重新构建，从而自动跳转到 HomePage
                          // 这样才能确保数据库完全初始化后才构建 HomePage
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          // 移除了 _navigateToHome() 调用
                        } catch (error) {
                          logError('跳过引导失败',
                              error: error, source: 'OnboardingPage');
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('初始化失败，请重试'),
                                duration: AppConstants.snackBarDurationError,
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('确定跳过'),
                    ),
                  ],
          );
        },
      ),
    );
  }

  /// 导航到主页
  void _navigateToHome() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }
}
