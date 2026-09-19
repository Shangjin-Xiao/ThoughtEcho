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

import '../../test_harness.dart';
import 'geocoding_test_support.dart';

/// 编辑模式"更新位置"保留 POI 名的回归测试单独成文件。
///
/// 它要走静态本地反查（`LocalGeocodingService` 自带串行队列和 MMKV 缓存，
/// 都是进程级单例）。和其他用例同文件时会互相污染该共享状态，
/// 导致成功分支不稳定；独立文件即独立测试隔离区，结果确定。
class _TestSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get autoAttachLocation => false;

  @override
  bool get autoAttachWeather => false;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => mockPosition();

  @override
  String? get currentPoiName => '故宫博物院';

  @override
  String getFormattedLocation() => '中国,北京市,北京市,东城区';

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) async =>
      mockPosition();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWeatherService extends ChangeNotifier implements WeatherService {
  @override
  bool get hasData => false;

  @override
  String get currentWeather => '';

  @override
  String get temperature => '';

  @override
  String getFormattedWeather(AppLocalizations l10n) => '';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDownAll(() {
    UnifiedLogService.instance.dispose();
  });

  testWidgets('编辑模式只有坐标+POI 时点更新位置：同样保留 POI 名', (WidgetTester tester) async {
    final mockPlatform = AdminMockGeocodingPlatform();
    final previousPlatform = installAdminMockPlatform(mockPlatform);
    addTearDown(() => restoreAdminMockPlatform(previousPlatform));
    Quote? savedQuote;
    final initialQuote = Quote(
      id: 'existing-edit-poi-1',
      content: '已有笔记内容',
      date: DateTime.now().toIso8601String(),
      latitude: 39.9242,
      longitude: 116.4014,
      poiName: '景山公园',
    );

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
            value: _TestWeatherService(),
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
                      initialQuote: initialQuote,
                      tags: const [],
                      prefilledContent: '测试长按选择地点',
                      onSave: (quote) {
                        savedQuote = quote;
                      },
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add_note_location_chip')));
    await tester.pumpAndSettle();
    expect(find.text('更新位置'), findsOneWidget);

    await tester.tap(find.text('更新位置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('位置已更新为'), findsOneWidget);
    // 静态反查真跑到了，断言成功链路而不是兜底分支
    expect(mockPlatform.placemarkCalls, 1);

    await tester.tap(find.byKey(const ValueKey('add_note_save_button')));
    await tester.pumpAndSettle();

    expect(savedQuote, isNotNull);
    expect(savedQuote!.poiName, '景山公园');
    expect(savedQuote!.location, '中国,北京市,北京市,西城区');
  });
}
