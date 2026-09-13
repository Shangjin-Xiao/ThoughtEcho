import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/nearby_location_picker.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/place_search_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

import '../../test_harness.dart';

Position _mockPosition(
        {double latitude = 39.9042, double longitude = 116.4074}) =>
    Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

class _FakePlaceSearchService implements PlaceSearchService {
  _FakePlaceSearchService({
    this.places = const [],
    this.shouldThrow = false,
  });

  List<PlaceInfo> places;
  bool shouldThrow;
  int callCount = 0;

  @override
  Future<List<PlaceInfo>> getNearbyPlaces(
    double latitude,
    double longitude, {
    String? categoryOrKeyword,
    String? localeCode,
    int limit = 20,
    int offset = 0,
  }) async {
    callCount++;
    if (shouldThrow) {
      throw Exception('Network connection failed');
    }
    return places;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocationService extends ChangeNotifier implements LocationService {
  _FakeLocationService({
    Position? position,
    this.formattedLocation = '中国,北京市,北京市,东城区',
    this.poiName = '故宫博物院',
    this.reverseResult,
  }) : _position = position ?? _mockPosition();

  final Position? _position;
  final String formattedLocation;
  final String? poiName;
  final Map<String, String>? reverseResult;

  @override
  Position? get currentPosition => _position;

  @override
  String? get currentPoiName => poiName;

  @override
  String? get district => '东城区';

  @override
  String? get city => '北京市';

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) async =>
      _position;

  @override
  String getFormattedLocation() => formattedLocation;

  @override
  Future<Map<String, String>?> reverseGeocodePoint(
    double latitude,
    double longitude,
  ) async =>
      reverseResult;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapPicker({
  required Widget child,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: child,
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

  testWidgets('朋友圈模式：不渲染地图瓦片与自定义搜索输入框，第一项常驻当前系统位置',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(places: [
      const PlaceInfo(
        name: '景山公园',
        latitude: 39.9242,
        longitude: 116.4014,
        address: '景山西街44号',
        distanceMeters: 800,
      ),
    ]);

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));

    await tester.pumpAndSettle();

    // 验证不包含地图组件和输入框
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);

    // 验证标题为"所在位置"
    expect(find.text('所在位置'), findsOneWidget);

    // 验证第一项展示当前系统位置与勾选图标
    expect(find.textContaining('故宫博物院'), findsOneWidget);
    expect(find.text('只记城市和区县，不记具体地点'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsWidgets);

    // 验证候选地点展示在下方
    expect(find.text('景山公园'), findsOneWidget);
    expect(find.text('景山西街44号'), findsOneWidget);
    expect(find.text('800 米'), findsOneWidget);
  });

  testWidgets('点击候选地点可返回选中的 POI 信息', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final candidatePlace = const PlaceInfo(
      name: '天安门广场',
      latitude: 39.9037,
      longitude: 116.3976,
      address: '东长安街',
      distanceMeters: 450,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final res = await Navigator.of(context).push<LocationPickerResult>(
              MaterialPageRoute(
                builder: (_) => NearbyLocationPicker(
                  locationService: fakeLoc,
                  placeSearchService: fakeSearch,
                ),
              ),
            );
            selectedResult = res;
          },
          child: const Text('Open'),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 点击候选地点"天安门广场"
    await tester.tap(find.text('天安门广场'));
    await tester.pumpAndSettle();

    // 确认结果已 pop 并包含选中的 POI 信息
    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '天安门广场');
    expect(selectedResult!.latitude, candidatePlace.latitude);
    expect(selectedResult!.longitude, candidatePlace.longitude);
  });

  testWidgets('点击系统位置项可返回设备物理位置', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(places: []);

    LocationPickerResult? selectedResult;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final res = await Navigator.of(context).push<LocationPickerResult>(
              MaterialPageRoute(
                builder: (_) => NearbyLocationPicker(
                  locationService: fakeLoc,
                  placeSearchService: fakeSearch,
                ),
              ),
            );
            selectedResult = res;
          },
          child: const Text('Open'),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 点击系统位置"故宫博物院"
    await tester.tap(find.textContaining('故宫博物院'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '故宫博物院');
    expect(selectedResult!.latitude, 39.9042);
    expect(selectedResult!.longitude, 116.4074);
  });

  testWidgets('在线地点服务不可用时，第一项仍然可用，且展示轻量重试横条', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(shouldThrow: true);

    LocationPickerResult? selectedResult;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final res = await Navigator.of(context).push<LocationPickerResult>(
              MaterialPageRoute(
                builder: (_) => NearbyLocationPicker(
                  locationService: fakeLoc,
                  placeSearchService: fakeSearch,
                ),
              ),
            );
            selectedResult = res;
          },
          child: const Text('Open'),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 提示在线服务不可用
    expect(find.text('在线地点服务不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 第一项仍然可用并可点击
    expect(find.textContaining('故宫博物院'), findsOneWidget);
    await tester.tap(find.textContaining('故宫博物院'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.latitude, 39.9042);
  });

  testWidgets('离线环境下反查为空时，第一项回退为精确经纬度物理坐标', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      formattedLocation: '',
      poiName: null,
      reverseResult: null,
    );
    final fakeSearch = _FakePlaceSearchService(shouldThrow: true);

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));

    await tester.pumpAndSettle();

    // 第一项副标题为"离线坐标"
    expect(find.text('离线坐标'), findsOneWidget);
    // 经纬度格式化为 39.9042°N, 116.4074°E
    expect(find.textContaining('39.9042°N'), findsOneWidget);
  });
}
