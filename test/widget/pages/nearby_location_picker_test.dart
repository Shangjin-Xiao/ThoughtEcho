import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/nearby_location_picker.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/place_search_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/widgets/app_loading_view.dart';

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
    this.searchResults = const [],
    this.shouldThrow = false,
    this.searchShouldThrow = false,
    this.onGetNearbyPlaces,
  });

  List<PlaceInfo> places;
  List<PlaceInfo> searchResults;
  bool shouldThrow;
  bool searchShouldThrow;
  int callCount = 0;
  int searchCallCount = 0;
  String? lastSearchQuery;
  final List<int> requestedOffsets = [];
  Future<List<PlaceInfo>> Function(int offset, int limit)? onGetNearbyPlaces;
  Future<List<PlaceInfo>> Function(String query)? onSearchNearby;

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
    requestedOffsets.add(offset);
    if (shouldThrow) {
      throw Exception('Network connection failed');
    }
    if (onGetNearbyPlaces != null) {
      return onGetNearbyPlaces!(offset, limit);
    }
    return places;
  }

  @override
  Future<List<PlaceInfo>> searchNearby(
    double latitude,
    double longitude, {
    required String query,
    String? localeCode,
    int limit = 20,
    int offset = 0,
  }) async {
    searchCallCount++;
    lastSearchQuery = query;
    if (searchShouldThrow) {
      throw Exception('Search network failed');
    }
    if (onSearchNearby != null) {
      return onSearchNearby!(query);
    }
    return searchResults;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocationService extends ChangeNotifier implements LocationService {
  _FakeLocationService({
    Position? position,
    this.formattedLocation = '中国,北京市,北京市,东城区',
    this.poiName,
    this.reverseResult,
    this.onReverseGeocodePoint,
  }) : _position = position ?? _mockPosition();

  final Position? _position;
  final String formattedLocation;
  final String? poiName;
  final Map<String, String>? reverseResult;
  final Future<Map<String, String>?> Function(
      double latitude, double longitude)? onReverseGeocodePoint;
  bool? lastHighAccuracyRequested;

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
  }) async {
    lastHighAccuracyRequested = highAccuracy;
    return _position;
  }

  @override
  String getFormattedLocation() => formattedLocation;

  @override
  Future<Map<String, String>?> reverseGeocodePoint(
    double latitude,
    double longitude,
  ) async {
    if (onReverseGeocodePoint != null) {
      return onReverseGeocodePoint!(latitude, longitude);
    }
    return reverseResult;
  }

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

Future<void> _pumpPickerWithNavigation(
  WidgetTester tester, {
  required NearbyLocationPicker picker,
  void Function(LocationPickerResult? result)? onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final res = await Navigator.of(context).push<LocationPickerResult>(
            MaterialPageRoute(builder: (_) => picker),
          );
          onResult?.call(res);
        },
        child: const Text('Open'),
      ),
    ),
  ));

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDownAll(() {
    UnifiedLogService.instance.dispose();
  });

  testWidgets('朋友圈模式：渲染顶部搜索框，第一项常驻当前系统行政区位置', (WidgetTester tester) async {
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

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('所在位置'), findsOneWidget);

    expect(find.text('北京市·东城区'), findsOneWidget);
    expect(find.text('只记城市和区县，不记具体地点'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsWidgets);

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

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    await tester.tap(find.text('天安门广场'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '天安门广场');
    expect(selectedResult!.latitude, candidatePlace.latitude);
    expect(selectedResult!.longitude, candidatePlace.longitude);
  });

  testWidgets('点击系统位置项所见即所得返回设备物理位置与行政区（不暗中注入 POI）',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(places: []);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_system_location_tile')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, isNull);
    expect(selectedResult!.location, '中国,北京市,北京市,东城区');
    expect(selectedResult!.latitude, 39.9042);
    expect(selectedResult!.longitude, 116.4074);
  });

  testWidgets('系统定位含详细街道或 POI 时，第一项展示并返回该详细地名', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      poiName: '北京街道',
      formattedLocation: '中国,广东省,广州市,越秀区',
    );
    final fakeSearch = _FakePlaceSearchService(places: []);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    expect(find.textContaining('越秀区·北京街道'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_system_location_tile')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '北京街道');
    expect(selectedResult!.location, '中国,广东省,广州市,越秀区');
  });

  testWidgets('在线地点服务不可用时，第一项仍然可用，且展示轻量重试横条', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(shouldThrow: true);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    expect(find.text('在线地点服务不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    expect(find.byKey(const ValueKey('nearby_picker_system_location_tile')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_system_location_tile')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, isNull);
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

    expect(find.text('离线坐标'), findsOneWidget);
    expect(find.textContaining('39.9042°N'), findsOneWidget);
  });

  testWidgets('传入已有 initialPoiName 时，第一项仍保留真实系统定位且未被覆盖，可点击切回系统位置',
      (WidgetTester tester) async {
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

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: candidatePlace.latitude,
        initialLongitude: candidatePlace.longitude,
        initialLocation: '中国,北京市,北京市,东城区',
        initialPoiName: '天安门广场',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    expect(find.byKey(const ValueKey('nearby_picker_system_location_tile')),
        findsOneWidget);
    expect(find.text('天安门广场'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_system_location_tile')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, isNull);
    expect(selectedResult!.location, '中国,北京市,北京市,东城区');
    expect(selectedResult!.latitude, 39.9042);
    expect(selectedResult!.longitude, 116.4074);
  });

  testWidgets('选点器进入时向系统请求 highAccuracy: true 高精度定位',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(places: []);

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    expect(fakeLoc.lastHighAccuracyRequested, isTrue);
  });

  testWidgets('顶部搜索栏支持输入实时搜索 POI，防抖触发 searchNearby 并展示搜索结果，点击可确认',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    const searchResultPlace = PlaceInfo(
      name: '奥林匹克森林公园',
      latitude: 40.0182,
      longitude: 116.3920,
      address: '科荟路33号',
      distanceMeters: 12500,
    );
    final fakeSearch = _FakePlaceSearchService(
      places: [
        const PlaceInfo(
          name: '近处普通地点',
          latitude: 39.9050,
          longitude: 116.4080,
        ),
      ],
      searchResults: [searchResultPlace],
    );

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    expect(find.text('近处普通地点'), findsOneWidget);

    // 输入搜索词
    await tester.enterText(find.byType(TextField), '奥森');
    await tester.pump(const Duration(milliseconds: 200));
    // 防抖中，尚未触发 searchNearby
    expect(fakeSearch.searchCallCount, equals(0));

    // 超过防抖间隔 400ms
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(fakeSearch.searchCallCount, equals(1));
    expect(fakeSearch.lastSearchQuery, equals('奥森'));
    expect(find.text('奥林匹克森林公园'), findsOneWidget);

    // 点选搜索结果并确认返回
    await tester.tap(find.text('奥林匹克森林公园'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '奥林匹克森林公园');
    expect(selectedResult!.latitude, searchResultPlace.latitude);
    expect(selectedResult!.longitude, searchResultPlace.longitude);
  });

  testWidgets('清空搜索框后恢复周边 POI 列表与系统定位项', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    const searchResultPlace = PlaceInfo(
      name: '远方美术馆',
      latitude: 40.0000,
      longitude: 116.5000,
    );
    final fakeSearch = _FakePlaceSearchService(
      places: [
        const PlaceInfo(
          name: '常驻周边地点',
          latitude: 39.9050,
          longitude: 116.4080,
        ),
      ],
      searchResults: [searchResultPlace],
    );

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('常驻周边地点'), findsOneWidget);

    // 输入搜索关键词并等待触发
    await tester.enterText(find.byType(TextField), '美术馆');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('远方美术馆'), findsOneWidget);
    expect(find.text('常驻周边地点'), findsNothing);

    // 点击清除按钮
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();

    expect(find.text('常驻周边地点'), findsOneWidget);
    expect(find.byKey(const ValueKey('nearby_picker_system_location_tile')),
        findsOneWidget);
  });

  testWidgets('搜索失败时展示错误提示，点击重试可重新请求', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(
      searchShouldThrow: true,
      searchResults: [
        const PlaceInfo(
          name: '故宫角楼',
          latitude: 39.9200,
          longitude: 116.4000,
        ),
      ],
    );

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '角楼');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('在线地点服务不可用'), findsOneWidget);

    // 恢复服务并点击重试
    fakeSearch.searchShouldThrow = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('故宫角楼'), findsOneWidget);
  });

  testWidgets('搜索无匹配结果时展示 mapPickerNoResults 空状态提示',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(
      places: [
        const PlaceInfo(
          name: '常驻周边地点',
          latitude: 39.9050,
          longitude: 116.4080,
        ),
      ],
      searchResults: [],
    );

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '火星基地');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('没有找到相关地点'), findsOneWidget);
  });

  testWidgets('键盘提交 searchAction 立即触发搜索，无需等待 400ms 防抖延迟',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(
      searchResults: [
        const PlaceInfo(
          name: '立即搜索结果',
          latitude: 39.9100,
          longitude: 116.4100,
        ),
      ],
    );

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '立即');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fakeSearch.searchCallCount, equals(1));
    expect(fakeSearch.lastSearchQuery, equals('立即'));
    expect(find.text('立即搜索结果'), findsOneWidget);
  });

  testWidgets('连续输入不同搜索词时，旧请求返回不覆盖新请求结果', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final completer1 = Completer<List<PlaceInfo>>();
    final completer2 = Completer<List<PlaceInfo>>();

    final fakeSearch = _FakePlaceSearchService();
    fakeSearch.onSearchNearby = (query) {
      if (query == '旧词') return completer1.future;
      if (query == '新词') return completer2.future;
      return Future.value([]);
    };

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    // 输入旧词并触发
    await tester.enterText(find.byType(TextField), '旧词');
    await tester.pump(const Duration(milliseconds: 500));

    // 立即输入新词并触发
    await tester.enterText(find.byType(TextField), '新词');
    await tester.pump(const Duration(milliseconds: 500));

    // 让新词先返回
    completer2.complete([
      const PlaceInfo(
        name: '新词命中地点',
        latitude: 39.9200,
        longitude: 116.4200,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('新词命中地点'), findsOneWidget);

    // 旧词慢速返回，不应覆盖新词结果
    completer1.complete([
      const PlaceInfo(
        name: '旧词命中地点',
        latitude: 39.9100,
        longitude: 116.4100,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('新词命中地点'), findsOneWidget);
    expect(find.text('旧词命中地点'), findsNothing);
  });

  testWidgets('滑动列表到底部触发 getNearbyPlaces 分页加载更多', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final page1 = List.generate(
      20,
      (i) => PlaceInfo(
        name: '地点 $i',
        latitude: 39.9000 + (i * 0.001),
        longitude: 116.4000 + (i * 0.001),
        address: '测试街道 $i 号',
        distanceMeters: 100 + i * 10,
      ),
    );
    final page2 = List.generate(
      5,
      (i) => PlaceInfo(
        name: '次页地点 $i',
        latitude: 39.9500 + (i * 0.001),
        longitude: 116.4500 + (i * 0.001),
        address: '次页街道 $i 号',
        distanceMeters: 500 + i * 10,
      ),
    );

    final fakeSearch = _FakePlaceSearchService(
      onGetNearbyPlaces: (offset, limit) async {
        if (offset == 0) return page1;
        return page2;
      },
    );

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    expect(fakeSearch.callCount, 1);
    expect(fakeSearch.requestedOffsets, [0]);
    expect(find.text('地点 0'), findsOneWidget);
    expect(find.text('次页地点 0'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    expect(fakeSearch.callCount, 2);
    expect(fakeSearch.requestedOffsets, [0, 20]);
    expect(find.text('次页地点 0'), findsOneWidget);
  });

  testWidgets('在线地点服务故障时点击错误横幅重试按钮重新拉取', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(shouldThrow: true);

    await tester.pumpWidget(_wrapPicker(
      child: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('在线地点服务不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(fakeSearch.callCount, 1);

    fakeSearch.shouldThrow = false;
    fakeSearch.places = [
      const PlaceInfo(
        name: '景山公园',
        latitude: 39.9242,
        longitude: 116.4014,
        address: '景山西街44号',
        distanceMeters: 800,
      ),
    ];

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(fakeSearch.callCount, 2);
    expect(find.text('在线地点服务不可用'), findsNothing);
    expect(find.text('景山公园'), findsOneWidget);
  });

  testWidgets('保留初始 POI（无论是否在候选列表中）时，点击确认统一返回初始位置与坐标',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    // 候选列表包含 initialPoiName
    final candidatePlace = const PlaceInfo(
      name: '天安门广场',
      latitude: 39.9037,
      longitude: 116.3976,
      address: '东长安街16号',
      distanceMeters: 450,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: 39.9037,
        initialLongitude: 116.3976,
        initialLocation: '初始区县地址',
        initialPoiName: '天安门广场',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 点击右上角确认按钮（此时天安门广场自动匹配为选中国项）
    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_confirm_button')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '天安门广场');
    expect(selectedResult!.location, '初始区县地址');
    expect(selectedResult!.latitude, 39.9037);
    expect(selectedResult!.longitude, 116.3976);
  });

  testWidgets('候选地点未出现在列表中时，点击确认仍统一返回初始位置与坐标', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final fakeSearch = _FakePlaceSearchService(places: []);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: 39.9037,
        initialLongitude: 116.3976,
        initialLocation: '初始区县地址',
        initialPoiName: '天安门广场',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 点击右上角确认按钮
    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_confirm_button')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '天安门广场');
    expect(selectedResult!.location, '初始区县地址');
    expect(selectedResult!.latitude, 39.9037);
    expect(selectedResult!.longitude, 116.3976);
  });

  testWidgets('点选候选 POI 时，若同坐标复用设备四级行政区', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
      formattedLocation: '中国,北京市,北京市,东城区',
    );
    final candidatePlace = const PlaceInfo(
      name: '故宫角楼',
      latitude: 39.9042,
      longitude: 116.4074,
      address: '景山前街4号',
      distanceMeters: 50,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    await tester.tap(find.text('故宫角楼'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '故宫角楼');
    expect(selectedResult!.location, '中国,北京市,北京市,东城区');
    expect(selectedResult!.latitude, 39.9042);
    expect(selectedResult!.longitude, 116.4074);
  });

  testWidgets('点选候选 POI 时，不同坐标尝试反查四级行政区（反查成功）', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
      formattedLocation: '中国,北京市,北京市,东城区',
      reverseResult: {
        'country': '中国',
        'province': '北京市',
        'city': '北京市',
        'district': '西城区',
      },
    );
    final candidatePlace = const PlaceInfo(
      name: '景山公园',
      latitude: 39.9242,
      longitude: 116.4014,
      address: '景山西街44号',
      distanceMeters: 800,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    await tester.tap(find.text('景山公园'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '景山公园');
    expect(selectedResult!.location, '中国,北京市,北京市,西城区');
    expect(selectedResult!.latitude, 39.9242);
    expect(selectedResult!.longitude, 116.4014);
  });

  testWidgets('点选候选 POI 时，不同坐标反查失败返回 null，不写入非规范的街道门牌串',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
      formattedLocation: '中国,北京市,北京市,东城区',
      reverseResult: null,
    );
    final candidatePlace = const PlaceInfo(
      name: '景山公园',
      latitude: 39.9242,
      longitude: 116.4014,
      address: '景山西街44号',
      distanceMeters: 800,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    await tester.tap(find.text('景山公园'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '景山公园');
    expect(selectedResult!.location, isNull,
        reason: '反查失败返回 null，不写入非规范的街道门牌串 place.address');
    expect(selectedResult!.latitude, 39.9242);
    expect(selectedResult!.longitude, 116.4014);
  });

  testWidgets('实时定位反查失败时，不回退为 widget.initialLocation，避免绑定错误旧地址',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      formattedLocation: '',
      poiName: null,
      reverseResult: null,
    );
    final fakeSearch = _FakePlaceSearchService(places: []);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: 31.2304,
        initialLongitude: 121.4737,
        initialLocation: '上海市黄浦区',
        initialPoiName: '人民广场',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 点击系统位置项（北京坐标，反查为空）
    await tester.tap(find.text('离线坐标'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    // 应该使用设备定位结果，不应该回退为旧的「上海市黄浦区」
    expect(selectedResult!.location, isNot(equals('上海市黄浦区')));
    expect(selectedResult!.latitude, 39.9042);
    expect(selectedResult!.longitude, 116.4074);
  });

  testWidgets('候选 POI 反查未完成期间，锁定状态生效，并发二次点选或确认按钮被禁用',
      (WidgetTester tester) async {
    final reverseCompleter = Completer<Map<String, String>?>();
    int reverseCallCount = 0;

    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
      formattedLocation: '中国,北京市,北京市,东城区',
      onReverseGeocodePoint: (lat, lon) async {
        reverseCallCount++;
        return reverseCompleter.future;
      },
    );

    const placeA = PlaceInfo(
      name: '景山公园',
      latitude: 39.9242,
      longitude: 116.4014,
      address: '景山西街44号',
      distanceMeters: 800,
    );
    const placeB = PlaceInfo(
      name: '北海公园',
      latitude: 39.9280,
      longitude: 116.3880,
      address: '文津街1号',
      distanceMeters: 1200,
    );
    final fakeSearch = _FakePlaceSearchService(places: [placeA, placeB]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 1. 点选候选地点 A，触发反查
    await tester.tap(find.text('景山公园'));
    // 渲染一帧使 setState 生效
    await tester.pump();

    // 验证反查被触发
    expect(reverseCallCount, equals(1));

    // 验证 _isConfirming 处于激活状态：
    // - AbsorbPointer 处于 absorbing 状态
    final absorbPointer = tester.widget<AbsorbPointer>(
      find.byKey(const ValueKey('nearby_picker_body_absorb_pointer')),
    );
    expect(absorbPointer.absorbing, isTrue);

    // - AppBar 确认按钮处于禁用状态，且展示 AppInlineLoadingIndicator
    final confirmButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('nearby_picker_confirm_button')),
    );
    expect(confirmButton.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nearby_picker_confirm_button')),
        matching: find.byType(AppInlineLoadingIndicator),
      ),
      findsOneWidget,
    );

    // 2. 在反查等待期间，尝试并发二次点选地点 B 和系统定位项，以及点击 AppBar 确认按钮
    await tester.tap(find.text('北海公园'), warnIfMissed: false);
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('nearby_picker_system_location_tile')),
      warnIfMissed: false,
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('nearby_picker_confirm_button')),
      warnIfMissed: false,
    );
    await tester.pump();

    // 确认反查调用依然只有 1 次，没有发起新的并发反查
    expect(reverseCallCount, equals(1));
    // 页面尚未 pop
    expect(selectedResult, isNull);

    // 3. 完成首次反查
    reverseCompleter.complete({
      'country': '中国',
      'province': '北京市',
      'city': '北京市',
      'district': '西城区',
    });
    await tester.pumpAndSettle();

    // 4. 验证成功返回地点 A 的结果，没有被并发点选干扰
    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, equals('景山公园'));
    expect(selectedResult!.location, equals('中国,北京市,北京市,西城区'));
    expect(selectedResult!.latitude, equals(placeA.latitude));
    expect(selectedResult!.longitude, equals(placeA.longitude));
  });

  testWidgets('候选 POI 反查未完成期间，页面被主动关闭（unmount），反查完成时不抛出异常且不二次 pop',
      (WidgetTester tester) async {
    final reverseCompleter = Completer<Map<String, String>?>();

    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
      formattedLocation: '中国,北京市,北京市,东城区',
      onReverseGeocodePoint: (lat, lon) async => reverseCompleter.future,
    );

    const placeA = PlaceInfo(
      name: '景山公园',
      latitude: 39.9242,
      longitude: 116.4014,
      address: '景山西街44号',
      distanceMeters: 800,
    );
    final fakeSearch = _FakePlaceSearchService(places: [placeA]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 1. 点选候选地点 A，触发异步反查
    await tester.tap(find.text('景山公园'));
    await tester.pump();

    // 2. 模拟用户直接点击系统返回键或导航关闭页面
    Navigator.of(tester.element(find.byType(NearbyLocationPicker))).pop();
    await tester.pumpAndSettle();

    // 此时页面已关闭退出
    expect(find.byType(NearbyLocationPicker), findsNothing);
    expect(selectedResult, isNull);

    // 3. 此时异步反查才返回结果，验证不会出现 unmounted setState 或对上一级路由二次 pop
    reverseCompleter.complete({
      'country': '中国',
      'province': '北京市',
      'city': '北京市',
      'district': '西城区',
    });
    await tester.pumpAndSettle();

    // 结果依然为 null，且无任何异常抛出
    expect(selectedResult, isNull);
  });

  testWidgets('候选 POI 反查未完成期间，路由开始退出（动画期间尚未完全 unmount），反查完成时不误 pop 上级路由',
      (WidgetTester tester) async {
    final reverseCompleter = Completer<Map<String, String>?>();

    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
      formattedLocation: '中国,北京市,北京市,东城区',
      onReverseGeocodePoint: (lat, lon) async => reverseCompleter.future,
    );

    const placeA = PlaceInfo(
      name: '景山公园',
      latitude: 39.9242,
      longitude: 116.4014,
      address: '景山西街44号',
      distanceMeters: 800,
    );
    final fakeSearch = _FakePlaceSearchService(places: [placeA]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 1. 点选候选地点 A，触发异步反查
    await tester.tap(find.text('景山公园'));
    await tester.pump();

    // 2. 模拟用户点击返回键开始退出路由
    await tester.tap(find.byType(BackButton));
    // 渲染一帧使退出动画启动，此时路由正在退出，但 State 依然处于 mounted 状态
    await tester.pump();
    expect(find.byType(NearbyLocationPicker), findsOneWidget);

    // 3. 在退出动画进行期间，反查才异步返回结果
    reverseCompleter.complete({
      'country': '中国',
      'province': '北京市',
      'city': '北京市',
      'district': '西城区',
    });
    await tester.pump();

    // 4. 等待动画完全结束，退出完成
    await tester.pumpAndSettle();

    // 验证选择器页面已退出，且父级页面（包含 Open 按钮）依然存在，没有被误 pop 掉
    expect(find.byType(NearbyLocationPicker), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(selectedResult, isNull);
  });

  testWidgets('返回候选地点少于 pageSize 但非空时，hasMore 保持为 true；返回空列表后终止翻页',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    final firstPage = List.generate(
      15,
      (i) => PlaceInfo(
        name: '地点$i',
        latitude: 39.9042 + i * 0.001,
        longitude: 116.4074 + i * 0.001,
        distanceMeters: 500 + i * 10,
      ),
    );

    // 第一次调用返回 15 项（小于 pageSize 20，但内容产生足够滚动距离），第二次调用返回空列表
    final fakeSearch = _FakePlaceSearchService(
      onGetNearbyPlaces: (offset, limit) async {
        if (offset == 0) {
          return firstPage;
        }
        return [];
      },
    );

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
    );

    expect(find.text('地点0'), findsOneWidget);

    // 1. 模拟触底滚动触发加载更多（验证 hasMore 保持为 true）
    final scrollFinder = find.byType(ListView);
    await tester.drag(scrollFinder, const Offset(0, -1000));
    await tester.pumpAndSettle();

    // 验证第二次请求被发起，且 offset 准确递增为 15
    expect(fakeSearch.callCount, 2);
    expect(fakeSearch.requestedOffsets, [0, 15]);

    // 2. 再次尝试触底滚动，验证因收到空列表导致 hasMore 翻为 false，不再发起第三次请求
    await tester.drag(scrollFinder, const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(fakeSearch.callCount, 2);
    expect(fakeSearch.requestedOffsets, [0, 15]);
  });

  testWidgets('候选列表中存在多个同名不同坐标 POI 时，初始选中项仅严格匹配同名且同坐标的候选地点',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    const branchA = PlaceInfo(
      name: '星巴克',
      latitude: 39.9100,
      longitude: 116.4000,
      distanceMeters: 200,
    );
    const branchB = PlaceInfo(
      name: '星巴克',
      latitude: 39.9200,
      longitude: 116.4100,
      distanceMeters: 800,
    );
    final fakeSearch = _FakePlaceSearchService(places: [branchA, branchB]);

    LocationPickerResult? selectedResult;

    // 传入的初始 POI 为 branchB 的坐标
    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: branchB.latitude,
        initialLongitude: branchB.longitude,
        initialPoiName: '星巴克',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 点击右上角确认按钮
    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_confirm_button')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '星巴克');
    expect(selectedResult!.latitude, branchB.latitude);
    expect(selectedResult!.longitude, branchB.longitude);
  });

  testWidgets('候选 POI 与初始坐标存在微小浮点误差（< 0.0001）时，确认保留原始行政区地址串',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService();
    // 候选列表项与传入的初始坐标存在 0.00005 偏差
    const candidatePlace = PlaceInfo(
      name: '故宫博物院',
      latitude: 39.91635,
      longitude: 116.39715,
      distanceMeters: 50,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: 39.9163,
        initialLongitude: 116.3971,
        initialLocation: '中国,北京市,北京市,东城区',
        initialPoiName: '故宫博物院',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 点击右上角确认按钮
    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_confirm_button')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '故宫博物院');
    // 验证保留了原始行政区，没有被作为新地点重新反查为 null
    expect(selectedResult!.location, '中国,北京市,北京市,东城区');
    expect(selectedResult!.latitude, 39.9163);
    expect(selectedResult!.longitude, 116.3971);
  });

  testWidgets('初始 POI 坐标为空时，点选列表中同名候选 POI 重新反查行政区而不复用旧地址',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      reverseResult: {
        'country': '中国',
        'province': '上海市',
        'city': '上海市',
        'district': '黄浦区',
      },
    );
    const candidatePlace = PlaceInfo(
      name: '同名地标',
      latitude: 31.2304,
      longitude: 121.4737,
      distanceMeters: 100,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: null,
        initialLongitude: null,
        initialLocation: '中国,北京市,北京市,东城区',
        initialPoiName: '同名地标',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 点击候选列表中的「同名地标」
    await tester.tap(find.text('同名地标'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '同名地标');
    // 验证重新反查解析了上海市的行政区，而不是错误地复用旧的北京市东城区
    expect(selectedResult!.location, '中国,上海市,上海市,黄浦区');
    expect(selectedResult!.latitude, 31.2304);
    expect(selectedResult!.longitude, 121.4737);
  });

  testWidgets('初始 POI 坐标为空时，未点选候选直接点击确认仍保留原始初始地址与 POI',
      (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
    );
    const candidatePlace = PlaceInfo(
      name: '同名地标',
      latitude: 31.2304,
      longitude: 121.4737,
      distanceMeters: 100,
    );
    final fakeSearch = _FakePlaceSearchService(places: [candidatePlace]);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: null,
        initialLongitude: null,
        initialLocation: '中国,北京市,北京市,东城区',
        initialPoiName: '同名地标',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 直接点击右上角确认按钮（未点选候选列表项）
    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_confirm_button')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '同名地标');
    // 保留原始初始地址
    expect(selectedResult!.location, '中国,北京市,北京市,东城区');
  });

  testWidgets('仅传入初始经度或纬度之一且与设备同名时，不误判定为系统当前位置', (WidgetTester tester) async {
    final fakeLoc = _FakeLocationService(
      position: _mockPosition(latitude: 39.9042, longitude: 116.4074),
      formattedLocation: '系统设备地址',
      poiName: '故宫博物院',
    );
    final fakeSearch = _FakePlaceSearchService(places: []);

    LocationPickerResult? selectedResult;

    await _pumpPickerWithNavigation(
      tester,
      picker: NearbyLocationPicker(
        initialLatitude: null,
        initialLongitude: 116.3971,
        initialLocation: '中国,北京市,北京市,东城区',
        initialPoiName: '故宫博物院',
        locationService: fakeLoc,
        placeSearchService: fakeSearch,
      ),
      onResult: (res) => selectedResult = res,
    );

    // 点击右上角确认按钮（未点选系统位置，保持原初始 POI）
    await tester
        .tap(find.byKey(const ValueKey('nearby_picker_confirm_button')));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.poiName, '故宫博物院');
    // 保留原始初始地址，而不是被误判为系统位置（系统地址为「系统设备地址」）
    expect(selectedResult!.location, '中国,北京市,北京市,东城区');
    // 保留原本传入的经度，而不是被覆盖为系统设备经度 116.4074
    expect(selectedResult!.longitude, 116.3971);
  });
}
