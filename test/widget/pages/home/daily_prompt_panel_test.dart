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
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/ai_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import '../../../test_harness.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class MockAIService extends ChangeNotifier implements AIService {
  bool _hasValidApiKey = true;
  Stream<String>? _mockStream;
  int streamGenerateDailyPromptCallCount = 0;

  @override
  bool hasValidApiKey() => _hasValidApiKey;

  @override
  Stream<String> streamGenerateDailyPrompt(
    AppLocalizations l10n, {
    String? city,
    String? weather,
    String? temperature,
    String? historicalInsights,
  }) {
    streamGenerateDailyPromptCallCount += 1;
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
        apiKey: 'test-key',
      );

  /// 面板判断"AI 是否已配置"读的是多 provider 设置（生成链路的真源），
  /// 不是 legacy 的 [aiSettings]。
  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [
          AIProviderSettings(
            id: 'test-provider',
            name: 'Test Provider',
            apiKey: '',
            apiUrl: 'https://api.test.com',
            model: 'test-model',
          ),
        ],
        currentProviderId: 'test-provider',
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
  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('HomeDailyPromptPanel Widget Tests', () {
    late MockAIService mockAIService;
    late MockSettingsService mockSettingsService;
    late MockLocationService mockLocationService;
    late MockWeatherService mockWeatherService;
    late MockInsightHistoryService mockInsightHistoryService;

    setUp(() async {
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

    testWidgets('renders a local prompt without invoking AI when unconfigured',
        (WidgetTester tester) async {
      mockAIService._hasValidApiKey = false;

      await tester.pumpWidget(createWidgetUnderTest());

      final state = tester
          .state<HomeDailyPromptPanelState>(find.byType(HomeDailyPromptPanel));
      await state.refreshPrompt();
      await tester.pumpAndSettle();

      expect(mockAIService.streamGenerateDailyPromptCallCount, 0);

      final promptText = find.descendant(
        of: find.byType(HomeDailyPromptPanel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textAlign == TextAlign.center &&
              widget.maxLines == 3,
        ),
      );
      expect(promptText, findsOneWidget);
      expect(tester.widget<Text>(promptText).data, isNotEmpty);
    });

    testWidgets(
        'falls back to a local prompt when the AI stream yields nothing',
        (WidgetTester tester) async {
      // 回归：推理模型可能把 token 预算全花在思考上，content 一个字都不返回。
      // 流正常结束但内容为空时面板必须退回本地提示，而不是停在"等待"状态。
      mockAIService._mockStream = const Stream<String>.empty();

      await tester.pumpWidget(createWidgetUnderTest());

      final state = tester
          .state<HomeDailyPromptPanelState>(find.byType(HomeDailyPromptPanel));
      await state.refreshPrompt();
      await tester.pumpAndSettle();

      expect(mockAIService.streamGenerateDailyPromptCallCount, 1);

      final promptText = find.descendant(
        of: find.byType(HomeDailyPromptPanel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textAlign == TextAlign.center &&
              widget.maxLines == 3,
        ),
      );
      expect(promptText, findsOneWidget);
      expect(tester.widget<Text>(promptText).data, isNotEmpty);
    });
  });
}
