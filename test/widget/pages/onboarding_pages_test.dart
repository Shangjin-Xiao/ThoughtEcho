import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/config/onboarding_config.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/onboarding_models.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/theme_style_labels.dart';
import 'package:thoughtecho/widgets/onboarding/appearance_page_view.dart';
import 'package:thoughtecho/widgets/onboarding/preferences_page_view.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  String styleName(AppLocalizations l10n, ThemeStyle style) {
    final (name, _) = themeStyleLabel(l10n, style);
    return name;
  }

  /// 外观屏（index 1）：主题风格 + 每日一言。
  Widget buildAppearancePage({
    required Locale locale,
    OnboardingState state = const OnboardingState(),
    void Function(String key, dynamic value)? onPreferenceChanged,
    AppTheme? appTheme,
  }) {
    return ChangeNotifierProvider<AppTheme>.value(
      value: appTheme ?? AppTheme(),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => AppearancePageView(
              pageData: OnboardingConfig.getPageDataWithContext(context, 1),
              state: state,
              onPreferenceChanged: onPreferenceChanged ?? (_, __) {},
            ),
          ),
        ),
      ),
    );
  }

  /// 习惯与隐私屏（index 2）。
  Widget buildPreferencesPage({
    OnboardingState state = const OnboardingState(),
    void Function(String key, dynamic value)? onPreferenceChanged,
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => PreferencesPageView(
            pageData: OnboardingConfig.getPageDataWithContext(context, 2),
            state: state,
            onPreferenceChanged: onPreferenceChanged ?? (_, __) {},
          ),
        ),
      ),
    );
  }

  group('外观屏 · 每日一言', () {
    testWidgets('根据语言为每日一言 provider 选择合适默认值', (tester) async {
      await tester.pumpWidget(buildAppearancePage(locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('ZenQuotes'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RadioGroup<String> &&
              widget.groupValue == ApiService.zenQuotesProvider,
        ),
        findsOneWidget,
      );
    });

    testWidgets('展示 API 选择，并把推荐项标出来', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      await tester.pumpWidget(buildAppearancePage(locale: const Locale('zh')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.dailyQuoteApi), findsOneWidget);
      expect(find.text('一言 (Hitokoto)'), findsOneWidget);
      // 中文下推荐 Hitokoto，标记只能出现在那一项上。
      expect(find.text(l10n.onboardingProviderRecommended), findsOneWidget);
    });

    testWidgets('类型默认全选且收在折叠区里，展开后才出现 chip', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      await tester.pumpWidget(buildAppearancePage(locale: const Locale('zh')));
      await tester.pumpAndSettle();

      // 折叠状态：只有摘要，没有 chip。
      expect(find.text(l10n.onboardingCustomizeTypes), findsOneWidget);
      expect(find.text(l10n.selectedCount(11)), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);

      await tester.ensureVisible(find.text(l10n.onboardingCustomizeTypes));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.onboardingCustomizeTypes));
      await tester.pumpAndSettle();

      expect(find.byType(FilterChip), findsNWidgets(11));
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
      expect(chips.every((chip) => chip.selected), isTrue);
    });

    testWidgets('非 Hitokoto provider 时整块类型选择都不出现', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      await tester.pumpWidget(
        buildAppearancePage(
          locale: const Locale('zh'),
          state: const OnboardingState(
            preferences: {'dailyQuoteProvider': ApiService.zenQuotesProvider},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.dailyQuoteApi), findsOneWidget);
      expect(find.text(l10n.onboardingCustomizeTypes), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
    });
  });

  group('外观屏 · 主题风格', () {
    testWidgets('每种风格都有一张预览，点击即切换', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      final appTheme = AppTheme();
      expect(appTheme.themeStyle, ThemeStyle.defaultStyle);

      await tester.pumpWidget(
        buildAppearancePage(locale: const Locale('zh'), appTheme: appTheme),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.themeStyle), findsOneWidget);
      for (final style in ThemeStyle.values) {
        expect(find.text(styleName(l10n, style)), findsOneWidget);
      }

      final target = ThemeStyle.values.firstWhere(
        (style) => style != ThemeStyle.defaultStyle,
      );
      await tester.tap(find.text(styleName(l10n, target)));
      await tester.pumpAndSettle();

      expect(appTheme.themeStyle, target);
    });
  });

  group('习惯与隐私屏', () {
    testWidgets('展示三项设置和 AI 说明卡', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      await tester.pumpWidget(buildPreferencesPage());
      await tester.pumpAndSettle();

      expect(find.text(l10n.prefDefaultStartPage), findsOneWidget);
      expect(find.text(l10n.prefLocationService), findsOneWidget);
      expect(find.text(l10n.settingsSentryTitle), findsOneWidget);
      expect(find.text(l10n.onboardingAiTitle), findsOneWidget);
      expect(find.text(l10n.onboardingAiOpenAfter), findsOneWidget);
    });

    testWidgets('勾选「完成后带我去配置」会写回 openAiSettingsAfter', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      final changes = <String, dynamic>{};

      await tester.pumpWidget(
        buildPreferencesPage(
          onPreferenceChanged: (key, value) => changes[key] = value,
        ),
      );
      await tester.pumpAndSettle();

      // AI 卡在这一屏最下面，测试视口下要先滚进来才点得到。
      await tester.ensureVisible(find.text(l10n.onboardingAiOpenAfter));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.onboardingAiOpenAfter));
      await tester.pumpAndSettle();

      expect(changes['openAiSettingsAfter'], isTrue);
    });

    testWidgets('AI 配置默认不勾选——没有 Key 的人不该被引到配置页', (tester) async {
      await tester.pumpWidget(buildPreferencesPage());
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });
  });
}
