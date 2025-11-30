import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/onboarding_models.dart';
import '../services/api_service.dart';

/// 引导页面配置
class OnboardingConfig {
  /// 获取引导页面列表
  static List<OnboardingPageData> getPages(AppLocalizations l10n) {
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
        features: getCoreFeatures(l10n),
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

  /// 获取核心功能列表
  static List<OnboardingFeature> getCoreFeatures(AppLocalizations l10n) {
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

  /// 获取偏好设置列表（顺序：语言、每日一言类型、位置服务、默认启动页面）
  static List<OnboardingPreference<dynamic>> getPreferences(AppLocalizations l10n) {
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
        options: ApiService.hitokotoTypeKeys.entries
            .map(
              (entry) => OnboardingPreferenceOption<String>(
                value: entry.key,
                label: entry.value,
              ),
            )
            .toList(),
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

  /// 获取快速操作提示
  static List<String> getQuickTips(AppLocalizations l10n) {
    return [
      l10n.quickTip1,
      l10n.quickTip2,
      l10n.quickTip3,
      l10n.quickTip4,
    ];
  }

  /// 页面数量常量
  /// 页面结构: 欢迎页、功能展示页、个性化设置页
  static const int _pageCount = 3;

  // 获取总页数
  static int get totalPages => _pageCount;

  // 检查是否为最后一页
  static bool isLastPage(int pageIndex) => pageIndex == _pageCount - 1;

  // 获取页面数据
  static OnboardingPageData getPageData(int pageIndex, AppLocalizations l10n) {
    final pages = getPages(l10n);
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw ArgumentError('Invalid page index: $pageIndex');
    }
    return pages[pageIndex];
  }

  /// 偏好设置默认值（用于控制器初始化，不需要本地化）
  static const Map<String, dynamic> preferenceDefaults = {
    'localeCode': '',
    'hitokotoTypes': 'a,b,c,d,e,f,g,h,i,j,k',
    'locationService': false,
    'defaultStartPage': 0,
  };
}
