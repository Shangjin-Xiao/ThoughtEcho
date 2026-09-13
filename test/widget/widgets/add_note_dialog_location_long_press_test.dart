import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/nearby_location_picker.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

import '../../test_harness.dart';

Position _mockPosition() => Position(
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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => _mockPosition();

  @override
  String? get currentPoiName => '故宫博物院';

  @override
  String getFormattedLocation() => '中国,北京市,北京市,东城区';

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) async =>
      _mockPosition();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

Widget _buildTestApp({
  Quote? initialQuote,
  void Function(Quote)? onSave,
}) {
  return MultiProvider(
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
                  onSave: onSave ?? (_) {},
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

  tearDownAll(() {
    UnifiedLogService.instance.dispose();
  });

  testWidgets('编辑模式下长按位置按钮：显示只读提示对话框，不跳转地点选择器', (WidgetTester tester) async {
    final initialQuote = Quote(
      id: 'existing-id-1',
      content: '已有笔记内容',
      date: DateTime.now().toIso8601String(),
      location: '中国,北京市,北京市,东城区',
      latitude: 39.9042,
      longitude: 116.4074,
      poiName: '故宫博物院',
    );

    await tester.pumpWidget(_buildTestApp(initialQuote: initialQuote));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final locationChip = find.byKey(const ValueKey('add_note_location_chip'));
    expect(locationChip, findsOneWidget);

    // 长按位置按钮
    await tester.longPress(locationChip);
    await tester.pumpAndSettle();

    // 验证弹出的是只读提示对话框，而不是 NearbyLocationPicker
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('位置信息'), findsOneWidget);
    expect(find.byType(NearbyLocationPicker), findsNothing);

    // 关闭对话框并清理
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('取消'),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('新建模式下长按位置按钮：打开附近地点选择器，选中并保存保留 poiName',
      (WidgetTester tester) async {
    Quote? savedQuote;

    await tester.pumpWidget(_buildTestApp(
      onSave: (quote) {
        savedQuote = quote;
      },
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final locationChip = find.byKey(const ValueKey('add_note_location_chip'));
    expect(locationChip, findsOneWidget);

    // 长按位置按钮打开 NearbyLocationPicker
    await tester.longPress(locationChip);
    await tester.pumpAndSettle();

    // 验证已导航到 NearbyLocationPicker
    expect(find.byType(NearbyLocationPicker), findsOneWidget);
    expect(find.text('所在位置'), findsOneWidget);

    // 选中设备当前位置
    expect(find.textContaining('故宫博物院'), findsOneWidget);
    await tester.tap(find.textContaining('故宫博物院'));
    await tester.pumpAndSettle();

    // 确认返回了 AddNoteDialog，且位置已被选中
    expect(find.byType(NearbyLocationPicker), findsNothing);
    final FilterChip chipWidget = tester.widget(locationChip);
    expect(chipWidget.selected, isTrue);

    // 点击保存
    final saveButton = find.byType(FilledButton).last;
    expect(find.descendant(of: saveButton, matching: find.text('保存')),
        findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // 验证保存的笔记包含 POI 名称与经纬度
    expect(savedQuote, isNotNull);
    expect(savedQuote!.poiName, '故宫博物院');
    expect(savedQuote!.latitude, 39.9042);
    expect(savedQuote!.longitude, 116.4074);
  });
}
