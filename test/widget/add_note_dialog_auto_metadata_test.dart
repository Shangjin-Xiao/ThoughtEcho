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

Position _beijingPosition() => Position(
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

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  _TestSettingsService({this.autoAttachLocation = true});

  @override
  final bool autoAttachLocation;

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

/// 定位要 200ms 才回来——用户完全可能在这之前就点保存。
class _SlowLocationService extends ChangeNotifier implements LocationService {
  _SlowLocationService({Position? initialPosition})
      : _position = initialPosition;

  Position? _position;

  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => _position;

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _position = _beijingPosition();
    return _position;
  }

  @override
  String getFormattedLocation() => '中国,北京市,北京市,朝阳区';

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 天气在定位之后才开始抓，再花 300ms——两次抓取之间正是元数据被丢掉的窗口。
class _SlowWeatherService extends ChangeNotifier implements WeatherService {
  bool _hasData = false;

  @override
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _hasData = true;
    notifyListeners();
  }

  @override
  bool get hasData => _hasData;

  @override
  String get currentWeather => _hasData ? 'clear' : '';

  @override
  String get temperature => _hasData ? '25°C' : '';

  @override
  String getFormattedWeather(AppLocalizations l10n) => 'clear 25°C';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 天气立刻就有数据，用来构造「用户手动勾上又移除」的场景。
class _InstantWeatherService extends ChangeNotifier implements WeatherService {
  var fetchCount = 0;

  @override
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    fetchCount++;
  }

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

Widget _buildApp({
  required SettingsService settings,
  required LocationService location,
  required WeatherService weather,
  required void Function(Quote) onSave,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<LocationService>.value(value: location),
      ChangeNotifierProvider<WeatherService>.value(value: weather),
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
                  onSave: onSave,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  // 用 tearDownAll：UnifiedLogService 是单例，逐个用例 dispose 会让后面的用例
  // 用到一个已经销毁的实例。
  tearDownAll(() {
    UnifiedLogService.instance.dispose();
  });

  testWidgets('抓取还没开始就点保存：转圈等到位置和天气都到手', (WidgetTester tester) async {
    Quote? saved;

    await tester.pumpWidget(
      _buildApp(
        settings: _TestSettingsService(),
        location: _SlowLocationService(),
        weather: _SlowWeatherService(),
        onSave: (quote) => saved = quote,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    // 兜底定时器（900ms）都还没到，抓取一次都没跑起来。
    await tester.pump(const Duration(milliseconds: 50));

    // 用位置定位保存按钮：等待中它的文案会换成转圈，按文案找会找不到。
    final saveButton = find.byType(FilledButton).last;
    expect(find.descendant(of: saveButton, matching: find.text('保存')),
        findsOneWidget);
    await tester.tap(saveButton);
    await tester.pump();

    // 等待中：保存按钮换成转圈并禁用
    expect(
      find.descendant(
        of: saveButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    expect(saved, isNull);

    // 定位 200ms + 天气 300ms，中间那段窗口不能被当成「已经抓完」
    await tester.pump(const Duration(milliseconds: 250));
    expect(saved, isNull, reason: '位置刚到手、天气还没抓，不该提前落库');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.weather, 'clear');
    expect(saved!.temperature, '25°C');
    expect(saved!.latitude, 39.9042);
    expect(saved!.location, '中国,北京市,北京市,朝阳区');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('抓取开始前用户移除天气：保存时不会被自动附加计划加回来', (WidgetTester tester) async {
    Quote? saved;
    final weather = _InstantWeatherService();

    await tester.pumpWidget(
      _buildApp(
        // 只预约天气，把变量收敛到一条线上
        settings: _TestSettingsService(autoAttachLocation: false),
        // 天气要有坐标才抓得动，这里给一个已缓存的位置
        location: _SlowLocationService(initialPosition: _beijingPosition()),
        weather: weather,
        onSave: (quote) => saved = quote,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 兜底定时器还没到，自动附加一次都没跑；用户自己先勾上天气
    final weatherChip = find.byKey(const ValueKey('add_note_weather_chip'));
    await tester.tap(weatherChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(weather.fetchCount, 1);

    // 再点一次打开详情对话框，明确移除。
    // 这里用固定小步 pump 而不是 pumpAndSettle：整段必须压在兜底定时器（900ms）之前，
    // 否则自动附加会先跑起来，测的就不是「抓取开始前移除」这个场景了。
    await tester.tap(weatherChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('移除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(saved, isNotNull);
    expect(saved!.weather, isNull, reason: '用户明确移除的天气不该在保存时被静默加回');
    expect(weather.fetchCount, 1, reason: '不该为已取消的附加再发一次请求');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
