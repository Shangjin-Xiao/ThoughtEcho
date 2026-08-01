import 'package:flutter/material.dart';
import '../models/onboarding_models.dart';
import '../services/api_service.dart';
import '../gen_l10n/app_localizations.dart';

/// 引导页面配置
///
/// 三屏，顺序即用户看到的顺序：
/// 0. [OnboardingPageType.welcome] 欢迎与语言
/// 1. [OnboardingPageType.appearance] 外观风格与每日一言来源
/// 2. [OnboardingPageType.preferences] 使用习惯、隐私与 AI 引导
///
/// 偏好项由 [getPreferences] 统一定义（控制器据此播种默认值），但页面**不再**
/// 盲目遍历渲染：每屏按 key 取自己那几项。这样加一个偏好不会莫名其妙多出一张卡片。
class OnboardingConfig {
  static const Map<String, String> _nativeLanguageLabels = {
    'zh': '简体中文',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
  };

  /// 语言选项。空字符串表示跟随系统，排在首位。
  static const List<String> languageCodes = [
    '',
    'zh',
    'en',
    'ja',
    'ko',
    'es',
    'fr',
    'de',
  ];

  static String nativeLanguageLabel(String languageCode) {
    return _nativeLanguageLabels[languageCode] ?? languageCode;
  }

  static String languageDisplayLabel(
    AppLocalizations l10n,
    String languageCode,
  ) {
    if (languageCode.isEmpty) {
      return l10n.languageFollowSystem;
    }

    return nativeLanguageLabel(languageCode);
  }

  /// 获取引导页面列表（动态国际化）
  static List<OnboardingPageData> getPages(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      OnboardingPageData(
        title: l10n.onboardingWelcome,
        subtitle: l10n.onboardingSubtitle,
        description: l10n.onboardingDescription,
        type: OnboardingPageType.welcome,
      ),
      OnboardingPageData(
        title: l10n.onboardingAppearanceTitle,
        subtitle: l10n.onboardingAppearanceSubtitle,
        type: OnboardingPageType.appearance,
      ),
      OnboardingPageData(
        title: l10n.onboardingHabitsTitle,
        subtitle: l10n.onboardingHabitsSubtitle,
        description: l10n.onboardingModifyLater,
        type: OnboardingPageType.preferences,
      ),
    ];
  }

  /// 获取偏好设置列表（动态国际化）
  ///
  /// 顺序按所属屏排列：前两项在外观屏，后三项在习惯屏。
  static List<OnboardingPreference<dynamic>> getPreferences(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context);
    final localeCode = Localizations.localeOf(context).toLanguageTag();
    final defaultDailyQuoteProvider =
        ApiService.recommendedDailyQuoteProviderForLanguage(
      localeCode,
    );

    return [
      // ── 外观屏 ──
      OnboardingPreference<String>(
        key: 'dailyQuoteProvider',
        title: l10n.dailyQuoteApi,
        description: l10n.dailyQuoteApiDesc,
        defaultValue: defaultDailyQuoteProvider,
        type: OnboardingPreferenceType.radio,
        options: ApiService.getDailyQuoteProviders(l10n)
            .entries
            .map(
              (entry) => OnboardingPreferenceOption<String>(
                value: entry.key,
                label: entry.value,
              ),
            )
            .toList(),
      ),
      OnboardingPreference<String>(
        key: 'hitokotoTypes',
        title: l10n.prefDailyQuoteType,
        description: l10n.prefDailyQuoteTypeDesc,
        defaultValue: allHitokotoTypeValue,
        type: OnboardingPreferenceType.multiSelect,
        options: getHitokotoTypeOptions(context),
      ),

      // ── 习惯与隐私屏 ──
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
      OnboardingPreference<bool>(
        key: 'locationService',
        title: l10n.prefLocationService,
        description: l10n.prefLocationServiceDesc,
        defaultValue: false,
        type: OnboardingPreferenceType.toggle,
      ),
      OnboardingPreference<bool>(
        key: 'sentryEnabled',
        title: l10n.settingsSentryTitle,
        description: l10n.settingsSentryDesc,
        defaultValue: false,
        type: OnboardingPreferenceType.toggle,
      ),
    ];
  }

  /// 按 key 取单个偏好定义，取不到返回 null。
  static OnboardingPreference<dynamic>? preferenceByKey(
    BuildContext context,
    String key,
  ) {
    for (final preference in getPreferences(context)) {
      if (preference.key == key) return preference;
    }
    return null;
  }

  /// 一言类型全选时的取值。默认就是全选——新用户没有偏好，先给最丰富的内容，
  /// 想收窄再去折叠区里改。
  static String get allHitokotoTypeValue =>
      ApiService.hitokotoTypeKeys.keys.join(',');

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

  // 获取总页数
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
}
