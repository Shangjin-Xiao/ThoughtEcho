import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

import '../test_harness.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get autoAttachLocation => false;

  @override
  bool get autoAttachWeather => true;

  @override
  String? get defaultAuthor => null;

  @override
  String? get defaultSource => null;

  @override
  List<String> get defaultTagIds => const [];

  @override
  AppSettings get appSettings => AppSettings(developerMode: false);

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  LocalAISettings get localAISettings => const LocalAISettings();

  @override
  bool get addNoteDialogDeferAutoMetadata => false;

  @override
  bool get addNoteDialogAutoFocus => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => Position(
        longitude: 116.4074,
        latitude: 39.9042,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 请求永不返回，但服务里已经有上一次的天气数据——正是误报「未能附加」的场景。
class _HangingWeatherService extends ChangeNotifier implements WeatherService {
  @override
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) =>
      Completer<void>().future;

  @override
  bool get hasData => true;

  @override
  String get currentWeather => 'clear';

  @override
  String get temperature => '25°C';

  @override
  String getFormattedWeather(AppLocalizations l10n) => 'clear 25°C';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async =>
      null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFeatureGuideService extends ChangeNotifier
    implements FeatureGuideService {
  @override
  bool hasShown(String guideId) => true;

  @override
  bool hasShownAll(List<String> guideIds) => true;

  @override
  bool hasShownAny(List<String> guideIds) => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDown(() {
    UnifiedLogService.instance.dispose();
  });

  testWidgets('天气实际已附加时不提示「未能附加」', (WidgetTester tester) async {
    Quote? saved;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(
            value: _TestSettingsService(),
          ),
          ChangeNotifierProvider<LocationService>.value(
            value: _TestLocationService(),
          ),
          ChangeNotifierProvider<WeatherService>.value(
            value: _HangingWeatherService(),
          ),
          ChangeNotifierProvider<DatabaseService>.value(
            value: _TestDatabaseService(),
          ),
          ChangeNotifierProvider<FeatureGuideService>.value(
            value: _TestFeatureGuideService(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: AddNoteDialog(
                      tags: const [],
                      prefilledContent: '测试内容',
                      onSave: (quote) => saved = quote,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    // 等待元数据超时窗口（5s）走完
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));

    expect(saved, isNotNull);
    expect(saved!.weather, 'clear');
    expect(find.text('位置/天气未能附加，已直接保存'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
