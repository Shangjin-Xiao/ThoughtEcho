import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/pages/home/daily_prompt_panel.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

class _FakeAIService extends Fake implements AIService {
  final Stream<String> stream;
  _FakeAIService(this.stream);

  @override
  bool hasValidApiKey() => true;

  @override
  Stream<String> streamGenerateDailyPrompt(
    AppLocalizations l10n, {
    String? city,
    String? weather,
    String? temperature,
    String? historicalInsights,
    Future<String?>? historicalInsightsFuture,
  }) {
    return stream;
  }
}

class _FakeLocationService extends Fake implements LocationService {
  @override
  String? get city => 'Beijing';
}

class _FakeWeatherService extends Fake implements WeatherService {
  @override
  String? get currentWeather => 'sunny';
  @override
  String? get temperature => '22°C';
}

class _FakeSettingsService extends Fake implements SettingsService {
  @override
  bool get todayThoughtsUseAI => true;

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [
          AIProviderSettings(
            id: 'test',
            name: 'test',
            apiUrl: 'https://api.test.com',
            apiKey: 'key',
            model: 'model',
          ),
        ],
        currentProviderId: 'test',
      );
}

class _FakeInsightHistoryService extends Fake implements InsightHistoryService {
  @override
  Future<String> formatRecentInsightsForDailyPrompt() async => '';
}

void main() {
  testWidgets(
      'HomeDailyPromptPanel includes AnimatedSize and AnimatedSwitcher and debounces stream updates',
      (WidgetTester tester) async {
    Provider.debugCheckInvalidValueType = null;
    final controller = StreamController<String>();

    final aiService = _FakeAIService(controller.stream);
    final locationService = _FakeLocationService();
    final weatherService = _FakeWeatherService();
    final settingsService = _FakeSettingsService();
    final insightService = _FakeInsightHistoryService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AIService>.value(value: aiService),
          Provider<LocationService>.value(value: locationService),
          Provider<WeatherService>.value(value: weatherService),
          Provider<SettingsService>.value(value: settingsService),
          Provider<InsightHistoryService>.value(value: insightService),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: HomeDailyPromptPanel(
              screenWidth: 400,
              isSmallScreen: false,
              isVerySmallScreen: false,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify presence of AnimatedSize and AnimatedSwitcher
    expect(find.byType(AnimatedSize), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    final animatedSizeWidget =
        tester.widget<AnimatedSize>(find.byType(AnimatedSize));
    expect(
        animatedSizeWidget.duration, equals(const Duration(milliseconds: 200)));
    expect(animatedSizeWidget.curve, equals(Curves.easeOutCubic));

    final animatedSwitcherWidget =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(animatedSwitcherWidget.duration,
        equals(const Duration(milliseconds: 200)));

    // Trigger refreshPrompt
    final state = tester
        .state<HomeDailyPromptPanelState>(find.byType(HomeDailyPromptPanel));
    state.refreshPrompt();
    await tester.pump();

    // Verify loading state has ValueKey('loading')
    expect(find.byKey(const ValueKey('loading')), findsOneWidget);

    // Emit chunk 1
    controller.add('Hello');
    await tester.pump(const Duration(milliseconds: 30));

    // At 30ms, text shouldn't be rendered yet due to 100ms debounce
    expect(find.byKey(const ValueKey('loading')), findsOneWidget);

    // Advance past 100ms timer
    await tester.pump(const Duration(milliseconds: 80));

    // Now AnimatedSwitcher switched to Text with ValueKey('text')
    expect(find.byKey(const ValueKey('text')), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);

    // Emit more chunks rapidly
    controller.add(' world');
    controller.add('!');
    await tester.pump(const Duration(milliseconds: 20));
    // Not updated yet in state due to debounce
    expect(find.text('Hello world!'), findsNothing);

    // Stream closes
    await controller.close();
    await tester.pumpAndSettle();

    // On done, buffer is immediately flushed
    expect(find.text('Hello world!'), findsOneWidget);
  });
}
