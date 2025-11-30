import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../models/onboarding_models.dart';
import '../../config/onboarding_config.dart';
import '../../controllers/onboarding_controller.dart';
import '../../services/settings_service.dart';

/// 欢迎页面组件
class WelcomePageView extends StatefulWidget {
  final OnboardingPageData pageData;
  final VoidCallback? onGetStarted;

  const WelcomePageView({super.key, required this.pageData, this.onGetStarted});

  @override
  State<WelcomePageView> createState() => _WelcomePageViewState();
}

class _WelcomePageViewState extends State<WelcomePageView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // 语言选择
  late FixedExtentScrollController _languageScrollController;
  int _selectedLanguageIndex = 0;

  // 语言选项: 空字符串表示跟随系统
  static const List<String> _languageCodes = ['', 'zh', 'en'];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.3, 1.0, curve: Curves.easeOutBack),
          ),
        );

    // 初始化语言选择控制器
    _languageScrollController = FixedExtentScrollController(initialItem: 0);

    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 从控制器获取当前语言设置
    final controller = context.read<OnboardingController>();
    final currentLocale =
        controller.state.getPreference<String>('localeCode') ?? '';
    final index = _languageCodes.indexOf(currentLocale);
    if (index >= 0 && index != _selectedLanguageIndex) {
      _selectedLanguageIndex = index;
      if (_languageScrollController.hasClients) {
        _languageScrollController.jumpToItem(index);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _languageScrollController.dispose();
    super.dispose();
  }

  String _getLanguageLabel(String code) {
    switch (code) {
      case '':
        return AppLocalizations.of(context).languageFollowSystem;
      case 'zh':
        return AppLocalizations.of(context).languageChinese;
      case 'en':
        return AppLocalizations.of(context).languageEnglish;
      default:
        return code;
    }
  }

  void _onLanguageChanged(int index) {
    setState(() {
      _selectedLanguageIndex = index;
    });
    final controller = context.read<OnboardingController>();
    final selectedCode = _languageCodes[index];
    controller.updatePreference('localeCode', selectedCode);

    // 立即应用语言设置
    final settingsService = context.read<SettingsService>();
    settingsService.setLocale(selectedCode.isEmpty ? null : selectedCode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 应用图标
                    _buildAppIcon(theme),
                    const SizedBox(height: 40),

                    // 标题
                    Text(
                      widget.pageData.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // 副标题 + 条带底座（不覆盖文字）
                    Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // 条带底座，稍微下移
                            Positioned(
                              top: 18,
                              left: 0,
                              right: 0,
                              child: FractionallySizedBox(
                                widthFactor: 0.82,
                                child: Container(
                                  height: 22,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        theme.colorScheme.primary.withValues(
                                          alpha: 0.18,
                                        ),
                                        theme.colorScheme.secondary.withValues(
                                          alpha: 0.13,
                                        ),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.13),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 副标题文字悬浮于条带之上
                            Text(
                              widget.pageData.subtitle,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 23,
                                letterSpacing: 1.1,
                                shadows: [
                                  Shadow(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),

                    if (widget.pageData.description != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.82,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.10,
                              ),
                              blurRadius: 22,
                              spreadRadius: 1,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(
                          widget.pageData.description!,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 19,
                            letterSpacing: 1.1,
                            fontFamily: 'Rounded',
                            shadows: [
                              Shadow(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.13,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],

                    // 语言选择器
                    const SizedBox(height: 40),
                    _buildLanguageSelector(theme, l10n),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建语言选择器
  Widget _buildLanguageSelector(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          // 标题行
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.language_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.onboardingSelectLanguage,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 语言滚轮选择器
          SizedBox(
            height: 120,
            child: ListWheelScrollView.useDelegate(
              controller: _languageScrollController,
              itemExtent: 40,
              perspective: 0.003,
              diameterRatio: 1.5,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: _onLanguageChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: _languageCodes.length,
                builder: (context, index) {
                  final isSelected = index == _selectedLanguageIndex;
                  return Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: isSelected ? 18 : 15,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                      ),
                      child: Text(_getLanguageLabel(_languageCodes[index])),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon(ThemeData theme) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                Icons.auto_stories,
                size: 64,
                color: theme.colorScheme.onPrimary,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 功能展示页面组件
class FeaturesPageView extends StatefulWidget {
  final OnboardingPageData pageData;

  const FeaturesPageView({super.key, required this.pageData});

  @override
  State<FeaturesPageView> createState() => _FeaturesPageViewState();
}

class _FeaturesPageViewState extends State<FeaturesPageView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Animation<double>> _featureAnimations;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    final features = widget.pageData.features ?? [];
    _featureAnimations = List.generate(features.length, (index) {
      // Calculate intervals that ensure end values don't exceed 1.0
      final startDelay = index * 0.1; // Reduced from 0.15 to 0.1
      const animationDuration = 0.4; // Fixed duration for each animation
      final endTime = (startDelay + animationDuration).clamp(0.0, 1.0);

      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(startDelay, endTime, curve: Curves.easeOutCubic),
        ),
      );
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final features = widget.pageData.features ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 页面标题
          Text(
            widget.pageData.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.pageData.subtitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),

          // 功能列表
          ...features.asMap().entries.map((entry) {
            final index = entry.key;
            final feature = entry.value;

            return AnimatedBuilder(
              animation: _featureAnimations[index],
              builder: (context, child) {
                // Clamp animation values to valid ranges
                final animationValue = _featureAnimations[index].value;
                final clampedOpacity = animationValue.clamp(0.0, 1.0);
                final clampedScale = animationValue.clamp(0.0, double.infinity);

                return Transform.scale(
                  scale: clampedScale,
                  child: Opacity(
                    opacity: clampedOpacity,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: _FeatureCard(
                        feature: feature,
                        isHighlight: feature.isHighlight,
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          const SizedBox(height: 24),

          // 快速提示
          _buildQuickTips(theme),
        ],
      ),
    );
  }

  Widget _buildQuickTips(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).quickTips,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...OnboardingConfig.getQuickTips(context).map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                tip,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 功能卡片组件
class _FeatureCard extends StatelessWidget {
  final OnboardingFeature feature;
  final bool isHighlight;

  const _FeatureCard({required this.feature, this.isHighlight = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: isHighlight ? 8 : 2,
      shadowColor: isHighlight
          ? theme.colorScheme.primary.withValues(alpha: 0.3)
          : null,
      child: Container(
        decoration: isHighlight
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.secondaryContainer,
                  ],
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // 图标
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isHighlight
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  feature.icon,
                  color: isHighlight
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),

              // 文本内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isHighlight
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feature.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isHighlight
                            ? theme.colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.8,
                              )
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              // 高亮标识
              if (isHighlight)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    AppLocalizations.of(context).coreFeature,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
