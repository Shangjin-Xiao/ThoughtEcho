import 'package:flutter/material.dart';
import '../models/onboarding_models.dart';
import '../services/api_service.dart';
import '../gen_l10n/app_localizations.dart';

/// 引导页面配置
class OnboardingConfig {
  /// 获取引导页面列表（动态国际化）
  static List<OnboardingPageData> getPages(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      // 第1页：欢迎页面
      OnboardingPageData(
        title: l10n.onboardingWelcome,
        subtitle: l10n.onboardingSubtitle,
        description: l10n.onboardingDescription,
        type: OnboardingPageType.welcome,
      ),

      // 第2页：核心功能展示
      OnboardingPageData(
        title: l10n.onboardingCoreFeatures,
        subtitle: l10n.onboardingDiscoverFeatures,
        features: getCoreFeatures(context),
        type: OnboardingPageType.features,
      ),

      // 第3页：个性化设置
      OnboardingPageData(
        title: l10n.onboardingPersonalization,
        subtitle: l10n.onboardingCustomizeExperience,
        description: l10n.onboardingModifyLater,
        type: OnboardingPageType.preferences,
      ),
    ];
  }

  // 兼容旧代码的静态访问器（使用占位符，实际使用时应通过getPages获取）
  static List<OnboardingPageData> get pages => [
    const OnboardingPageData(
      title: '',
      subtitle: '',
      type: OnboardingPageType.welcome,
    ),
    const OnboardingPageData(
      title: '',
      subtitle: '',
      type: OnboardingPageType.features,
    ),
    const OnboardingPageData(
      title: '',
      subtitle: '',
      type: OnboardingPageType.preferences,
    ),
  ];

  /// 获取核心功能列表（动态国际化）
  static List<OnboardingFeature> getCoreFeatures(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      OnboardingFeature(
        title: l10n.featureSmartNotes,
        description: l10n.featureSmartNotesDesc,
        icon: Icons.edit_note,
      ),
      OnboardingFeature(
        title: l10n.featureDailyQuote,
        description: l10n.featureDailyQuoteDesc,
        icon: Icons.format_quote,
      ),
      OnboardingFeature(
        title: l10n.featureAiInsight,
        description: l10n.featureAiInsightDesc,
        icon: Icons.auto_awesome,
      ),
      OnboardingFeature(
        title: l10n.featureLocalFirst,
        description: l10n.featureLocalFirstDesc,
        icon: Icons.security,
      ),
    ];
  }

  /// 获取偏好设置列表（动态国际化）
  static List<OnboardingPreference<dynamic>> getPreferences(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context);
    return [
      // 0. 语言选择（放在最前面）
      OnboardingPreference<String>(
        key: 'localeCode',
        title: l10n.prefLanguage,
        description: l10n.prefLanguageDesc,
        defaultValue: '', // 空字符串表示跟随系统
        type: OnboardingPreferenceType.radio,
        options: [
          OnboardingPreferenceOption<String>(
            value: '',
            label: l10n.languageFollowSystem,
          ),
          OnboardingPreferenceOption<String>(
            value: 'zh',
            label: l10n.languageChinese,
          ),
          OnboardingPreferenceOption<String>(
            value: 'en',
            label: l10n.languageEnglish,
          ),
        ],
      ),

      // 1. 每日一言类型选择
      OnboardingPreference<String>(
        key: 'hitokotoTypes',
        title: l10n.prefDailyQuoteType,
        description: l10n.prefDailyQuoteTypeDesc,
        defaultValue: 'a,b,c,d,e,f,g,h,i,j,k',
        type: OnboardingPreferenceType.multiSelect,
        options: getHitokotoTypeOptions(context),
      ),

      // 2. 位置服务
      OnboardingPreference<bool>(
        key: 'locationService',
        title: l10n.prefLocationService,
        description: l10n.prefLocationServiceDesc,
        defaultValue: false,
        type: OnboardingPreferenceType.toggle,
      ),

      // 3. 默认启动页面
      OnboardingPreference<int>(
        key: 'defaultStartPage',
        title: l10n.prefDefaultStartPage,
        description: l10n.prefDefaultStartPageDesc,
        defaultValue: 0,
        type: OnboardingPreferenceType.radio,
        options: [
          OnboardingPreferenceOption<int>(
            value: 0,
            label: l10n.prefHomeOverview,
            description: l10n.prefHomeOverviewDesc,
          ),
          OnboardingPreferenceOption<int>(
            value: 1,
            label: l10n.prefNoteList,
            description: l10n.prefNoteListDesc,
          ),
        ],
      ),
    ];
  }

  /// 获取每日一言类型选项（动态国际化）
  static List<OnboardingPreferenceOption<String>> getHitokotoTypeOptions(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context);
    // 使用国际化的一言类型名称
    final hitokotoTypeLabels = {
      'a': l10n.hitokotoTypeA,
      'b': l10n.hitokotoTypeB,
      'c': l10n.hitokotoTypeC,
      'd': l10n.hitokotoTypeD,
      'e': l10n.hitokotoTypeE,
      'f': l10n.hitokotoTypeF,
      'g': l10n.hitokotoTypeG,
      'h': l10n.hitokotoTypeH,
      'i': l10n.hitokotoTypeI,
      'j': l10n.hitokotoTypeJ,
      'k': l10n.hitokotoTypeK,
    };

    return ApiService.hitokotoTypeKeys.entries
        .map(
          (entry) => OnboardingPreferenceOption<String>(
            value: entry.key,
            label: hitokotoTypeLabels[entry.key] ?? entry.value,
          ),
        )
        .toList();
  }

  // 兼容旧代码的静态访问器
  static final List<OnboardingPreference<dynamic>> preferences = [];

  /// 获取快速操作提示（动态国际化）
  static List<String> getQuickTips(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      '💡 ${l10n.onboardingQuickTip1}',
      '✨ ${l10n.onboardingQuickTip2}',
      '🏷️ ${l10n.onboardingQuickTip3}',
      '🔍 ${l10n.onboardingQuickTip4}',
    ];
  }

  // 兼容旧代码的静态访问器
  static const List<String> quickTips = [];

  // 获取总页数（固定为3页）
  static int get totalPages => 3;

  // 检查是否为最后一页
  static bool isLastPage(int pageIndex) => pageIndex == totalPages - 1;

  // 获取页面数据（动态国际化版本）
  static OnboardingPageData getPageDataWithContext(
    BuildContext context,
    int pageIndex,
  ) {
    final pages = getPages(context);
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw ArgumentError('Invalid page index: $pageIndex');
    }
    return pages[pageIndex];
  }

  // 获取页面数据（兼容旧代码，返回占位符数据）
  static OnboardingPageData getPageData(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= totalPages) {
      throw ArgumentError('Invalid page index: $pageIndex');
    }
    return pages[pageIndex];
  }
}
