import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/config/onboarding_config.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/onboarding_models.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/widgets/onboarding/preferences_page_view.dart';

import '../../test_setup.dart';

void main() {
  setUpAll(() async {
    await TestSetup.setupWidgetTest();
  });

  testWidgets('引导页根据语言为每日一言 provider 选择合适默认值', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return PreferencesPageView(
              pageData: OnboardingConfig.getPageDataWithContext(context, 2),
              state: const OnboardingState(),
              onPreferenceChanged: (_, __) {},
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
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

  testWidgets('引导页在类型选择区域展示 API 选择', (tester) async {
    final localizations = await AppLocalizations.delegate.load(
      const Locale('zh'),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return PreferencesPageView(
              pageData: OnboardingConfig.getPageDataWithContext(context, 2),
              state: const OnboardingState(),
              onPreferenceChanged: (_, __) {},
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('每日一言类型'), findsOneWidget);
    expect(find.text(localizations.dailyQuoteApi), findsOneWidget);
    expect(find.text('一言 (Hitokoto)'), findsOneWidget);
  });

  testWidgets('引导页在非 Hitokoto provider 时隐藏类型分类选项', (tester) async {
    final localizations = await AppLocalizations.delegate.load(
      const Locale('zh'),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return PreferencesPageView(
              pageData: OnboardingConfig.getPageDataWithContext(context, 2),
              state: const OnboardingState(
                preferences: {
                  'dailyQuoteProvider': ApiService.zenQuotesProvider,
                },
              ),
              onPreferenceChanged: (_, __) {},
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text(localizations.dailyQuoteApi), findsOneWidget);
    expect(find.text(localizations.prefDailyQuoteType), findsNothing);
    expect(find.text(localizations.hitokotoTypeA), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
  });
}
