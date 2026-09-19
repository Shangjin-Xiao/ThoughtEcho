// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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
  _TestSettingsService({this.autoAttachLocation = false});

  @override
  final bool autoAttachLocation;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 自动抓取只拿到坐标和 POI、行政区为空（在线反查失败的典型现场）；
/// 手动"更新位置"后才能解析出行政区。
class _CoordsOnlyPoiLocationService extends ChangeNotifier
    implements LocationService {
  _CoordsOnlyPoiLocationService({this.updateResolvesAdmin = true});

  /// 为 false 时模拟"服务反查不出行政区"，对话框回退走静态本地反查。
  final bool updateResolvesAdmin;

  bool _adminReady = false;

  @override
  String? currentLocaleCode;

  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => _mockPosition();

  @override
  String? get currentPoiName => '景山公园';

  @override
  String getFormattedLocation() => _adminReady ? '中国,北京市,北京市,西城区' : '';

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) async =>
      _mockPosition();

  @override
  void setCoordinates(double latitude, double longitude, {String? address}) {
    // 与真实语义一致：只定坐标，行政区等反查回来再填。
  }

  @override
  Future<void> getAddressFromLatLng() async {
    if (updateResolvesAdmin) _adminReady = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 返回固定中文四级地址的地理编码桩，供静态本地反查走成功分支。
class _AdminMockGeocodingPlatform extends GeocodingPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<void> setLocaleIdentifier(String localeIdentifier) async {}

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    String? localeIdentifier,
  }) async {
    return [
      Placemark(
        country: '中国',
        administrativeArea: '北京市',
        locality: '北京市',
        subLocality: '西城区',
      ),
    ];
  }
}

/// 装上桩并返回之前的平台实例，调用方用 addTearDown 恢复。
GeocodingPlatform _installAdminMockPlatform([
  GeocodingPlatform? mock,
]) {
  GeocodingPlatform? previous;
  try {
    previous = GeocodingPlatform.instance;
  } catch (_) {
    previous = null;
  }
  final platform = mock ?? _AdminMockGeocodingPlatform();
  GeocodingPlatform.instance = platform;
  return previous ?? platform;
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
  bool autoAttachLocation = false,
  void Function(Quote)? onSave,
  LocationService? locationService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(
        value: _TestSettingsService(autoAttachLocation: autoAttachLocation),
      ),
      ChangeNotifierProvider<LocationService>.value(
        value: locationService ?? _TestLocationService(),
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
    // 弹窗提示内容包含格式化 POI 地名
    expect(find.textContaining('东城区·故宫博物院'), findsOneWidget);
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

  testWidgets('新建模式且 autoAttachLocation 为 true 时：长按选取地点保存后，不会被自动抓取覆盖',
      (WidgetTester tester) async {
    Quote? savedQuote;

    await tester.pumpWidget(_buildTestApp(
      autoAttachLocation: true,
      onSave: (quote) {
        savedQuote = quote;
      },
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final locationChip = find.byKey(const ValueKey('add_note_location_chip'));
    expect(locationChip, findsOneWidget);

    // 长按打开选择器
    await tester.longPress(locationChip);
    await tester.pumpAndSettle();

    // 选择位置并返回
    await tester.tap(find.textContaining('故宫博物院'));
    await tester.pumpAndSettle();

    // 点击保存
    final saveButton = find.byType(FilledButton).last;
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedQuote, isNotNull);
    expect(savedQuote!.poiName, '故宫博物院');
    expect(savedQuote!.latitude, 39.9042);
    expect(savedQuote!.longitude, 116.4074);
  });

  testWidgets('新建模式下已有 POI 时，单击位置按钮弹窗提示包含格式化 POI 地名',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final locationChip = find.byKey(const ValueKey('add_note_location_chip'));

    // 先长按选点
    await tester.longPress(locationChip);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('故宫博物院'));
    await tester.pumpAndSettle();

    // 单击位置按钮打开管理对话框
    await tester.tap(locationChip);
    await tester.pumpAndSettle();

    // 验证弹窗内容包含格式化后的 POI 地名
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('东城区·故宫博物院'), findsOneWidget);

    // 点击取消关闭对话框
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('取消'),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('新建模式只有坐标+POI 时点更新位置：只补行政区，不洗掉 POI 名',
      (WidgetTester tester) async {
    Quote? savedQuote;

    await tester.pumpWidget(_buildTestApp(
      locationService: _CoordsOnlyPoiLocationService(),
      onSave: (quote) {
        savedQuote = quote;
      },
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 首次勾选位置：触发抓取。Fake 只给坐标和 POI、行政区为空
    //（在线反查失败的典型现场）。
    await tester.tap(find.byKey(const ValueKey('add_note_location_chip')));
    await tester.pumpAndSettle();
    final chipWidget = tester.widget<FilterChip>(
        find.byKey(const ValueKey('add_note_location_chip')));
    expect(chipWidget.selected, isTrue);

    // 再点一次打开管理对话框：只有坐标无地址时才有"更新位置"
    await tester.tap(find.byKey(const ValueKey('add_note_location_chip')));
    await tester.pumpAndSettle();
    expect(find.text('更新位置'), findsOneWidget);

    await tester.tap(find.text('更新位置'));
    await tester.pumpAndSettle();

    // "更新位置"按设计先关弹窗再执行更新：更新成功后只剩提示条。
    expect(find.textContaining('位置已更新为'), findsOneWidget);

    // 直接保存：POI 名必须还在，行政区已补上
    final saveButton = find.byType(FilledButton).last;
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedQuote, isNotNull);
    expect(savedQuote!.poiName, '景山公园');
    expect(savedQuote!.location, '中国,北京市,北京市,西城区');
  });

  testWidgets('服务反查不出行政区时回退本地反查：同样保留 POI 名', (WidgetTester tester) async {
    final previousPlatform = _installAdminMockPlatform();
    addTearDown(() => GeocodingPlatform.instance = previousPlatform);
    Quote? savedQuote;

    await tester.pumpWidget(_buildTestApp(
      locationService:
          _CoordsOnlyPoiLocationService(updateResolvesAdmin: false),
      onSave: (quote) {
        savedQuote = quote;
      },
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add_note_location_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add_note_location_chip')));
    await tester.pumpAndSettle();
    expect(find.text('更新位置'), findsOneWidget);

    await tester.tap(find.text('更新位置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('位置已更新为'), findsOneWidget);

    final saveButton = find.byType(FilledButton).last;
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(savedQuote, isNotNull);
    expect(savedQuote!.poiName, '景山公园');
    expect(savedQuote!.location, '中国,北京市,北京市,西城区');
  });
}
