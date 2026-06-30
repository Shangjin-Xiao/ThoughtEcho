import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/pages/home/daily_prompt_panel.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/models/settings_models.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class MockAIService extends ChangeNotifier implements AIService {
  bool _hasValidApiKey = true;
  Stream<String>? _mockStream;

  @override
  bool hasValidApiKey() => _hasValidApiKey;

  @override
  Stream<String> streamGenerateDailyPrompt(
    AppLocalizations l10n, {
    String? city,
    String? weather,
    String? temperature,
    List<Map<String, dynamic>> historicalInsights = const [],
  }) {
    return _mockStream ?? Stream.value('This is a test prompt.');
  }

  // Add dummy implementations for other interface methods...
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool todayThoughtsUseAI = true;

  @override
  AISettings get aiSettings => AISettings(
        apiUrl: 'https://api.test.com',
        model: 'test-model',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLocationService extends ChangeNotifier implements LocationService {
  @override
  String? city = 'TestCity';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockWeatherService extends ChangeNotifier implements WeatherService {
  @override
  String? currentWeather = 'Sunny';

  @override
  String? temperature = '25°C';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockInsightHistoryService extends ChangeNotifier
    implements InsightHistoryService {
  @override
  Future<String> formatRecentInsightsForDailyPrompt() async {
    return "";
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HomeDailyPromptPanel Widget Tests', () {
    late MockAIService mockAIService;
    late MockSettingsService mockSettingsService;
    late MockLocationService mockLocationService;
    late MockWeatherService mockWeatherService;
    late MockInsightHistoryService mockInsightHistoryService;

    setUp(() {
      mockAIService = MockAIService();
      mockSettingsService = MockSettingsService();
      mockLocationService = MockLocationService();
      mockWeatherService = MockWeatherService();
      mockInsightHistoryService = MockInsightHistoryService();
    });

    Widget createWidgetUnderTest() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AIService>.value(value: mockAIService),
          ChangeNotifierProvider<SettingsService>.value(
              value: mockSettingsService),
          ChangeNotifierProvider<LocationService>.value(
              value: mockLocationService),
          ChangeNotifierProvider<WeatherService>.value(
              value: mockWeatherService),
          ChangeNotifierProvider<InsightHistoryService>.value(
              value: mockInsightHistoryService),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HomeDailyPromptPanel(
              screenWidth: 800,
              isSmallScreen: false,
              isVerySmallScreen: false,
            ),
          ),
        ),
      );
    }

    testWidgets('should render correctly and display initial stream data',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(HomeDailyPromptPanel), findsOneWidget);

      final state = tester
          .state<HomeDailyPromptPanelState>(find.byType(HomeDailyPromptPanel));
      await state.refreshPrompt();
      await tester.pumpAndSettle();

      expect(find.text('This is a test prompt.'), findsOneWidget);
    });

    testWidgets('should use local prompt when AI is not configured',
        (WidgetTester tester) async {
      mockAIService._hasValidApiKey = false;

      await tester.pumpWidget(createWidgetUnderTest());

      final state = tester
          .state<HomeDailyPromptPanelState>(find.byType(HomeDailyPromptPanel));
      await state.refreshPrompt();
      await tester.pumpAndSettle();

      expect(find.textContaining('TestCity'), findsWidgets);
    });
  });
}
