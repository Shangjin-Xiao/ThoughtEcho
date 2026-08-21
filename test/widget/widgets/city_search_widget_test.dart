import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import 'package:thoughtecho/controllers/weather_search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/city_search_widget.dart';

class MockLocationService extends Mock implements LocationService {
  @override
  bool get isSearching => super.noSuchMethod(
        Invocation.getter(#isSearching),
        returnValue: false,
      ) as bool? ?? false;

  @override
  List<CityInfo> get searchResults => super.noSuchMethod(
        Invocation.getter(#searchResults),
        returnValue: <CityInfo>[],
      ) as List<CityInfo>;

  @override
  String? get city => super.noSuchMethod(
        Invocation.getter(#city),
        returnValue: '北京',
      ) as String?;

  @override
  String? get currentAddress => super.noSuchMethod(
        Invocation.getter(#currentAddress),
        returnValue: '中国, 北京市',
      ) as String?;

  @override
  Position? get currentPosition => super.noSuchMethod(
        Invocation.getter(#currentPosition),
      ) as Position?;

  @override
  Future<List<CityInfo>> searchCity(String? query) => super.noSuchMethod(
        Invocation.method(#searchCity, [query]),
        returnValue: Future<List<CityInfo>>.value(<CityInfo>[]),
      ) as Future<List<CityInfo>>;

  @override
  void clearSearchResults() => super.noSuchMethod(
        Invocation.method(#clearSearchResults, []),
      );
}

class MockWeatherService extends Mock implements WeatherService {
  @override
  bool get isLoading => super.noSuchMethod(
        Invocation.getter(#isLoading),
        returnValue: false,
      ) as bool? ?? false;

  @override
  bool get hasValidWeatherData => super.noSuchMethod(
        Invocation.getter(#hasValidWeatherData),
        returnValue: true,
      ) as bool? ?? true;

  @override
  String? get currentWeather => super.noSuchMethod(
        Invocation.getter(#currentWeather),
        returnValue: 'sunny',
      ) as String?;

  @override
  String? get temperature => super.noSuchMethod(
        Invocation.getter(#temperature),
        returnValue: '25°C',
      ) as String?;

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  WeatherServiceState get state => WeatherServiceState.success;
}

class MockSettingsService extends Mock implements SettingsService {
  List<CityInfo> _mockRecent = [];

  @override
  String? get localeCode => 'zh';

  @override
  List<CityInfo> get recentCities => _mockRecent;

  @override
  Future<void> addRecentCity(CityInfo city) async {
    _mockRecent.insert(0, city);
  }

  @override
  Future<void> removeRecentCity(CityInfo city) async {
    _mockRecent.remove(city);
  }

  @override
  Future<void> clearRecentCities() async {
    _mockRecent.clear();
  }
}

Widget _buildTestApp({
  required WeatherSearchController controller,
  required MockLocationService locationService,
  required MockWeatherService weatherService,
  required MockSettingsService settingsService,
  VoidCallback? onSuccess,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<WeatherSearchController>.value(value: controller),
      ChangeNotifierProvider<LocationService>.value(value: locationService),
      ChangeNotifierProvider<WeatherService>.value(value: weatherService),
      ChangeNotifierProvider<SettingsService>.value(value: settingsService),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: CitySearchWidget(
          weatherController: controller,
          onSuccess: onSuccess,
        ),
      ),
    ),
  );
}

void main() {
  late MockLocationService mockLocationService;
  late MockWeatherService mockWeatherService;
  late MockSettingsService mockSettingsService;
  late WeatherSearchController controller;

  setUp(() {
    mockLocationService = MockLocationService();
    mockWeatherService = MockWeatherService();
    mockSettingsService = MockSettingsService();
    controller =
        WeatherSearchController(mockLocationService, mockWeatherService);
  });

  testWidgets('renders header, weather card, search bar, and search guide',
      (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        controller: controller,
        locationService: mockLocationService,
        weatherService: mockWeatherService,
        settingsService: mockSettingsService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择城市'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('定位当前位置'), findsOneWidget);
    expect(find.text('输入城市名称开始搜索'), findsOneWidget);
  });

  testWidgets('renders recent cities chips when history is available',
      (tester) async {
    mockSettingsService._mockRecent = [
      CityInfo(
        name: '杭州',
        fullName: '中国, 浙江省, 杭州',
        lat: 30.2741,
        lon: 120.1551,
        country: '中国',
        province: '浙江省',
      ),
      CityInfo(
        name: '深圳',
        fullName: '中国, 广东省, 深圳',
        lat: 22.5431,
        lon: 114.0579,
        country: '中国',
        province: '广东省',
      ),
    ];

    await tester.pumpWidget(
      _buildTestApp(
        controller: controller,
        locationService: mockLocationService,
        weatherService: mockWeatherService,
        settingsService: mockSettingsService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近选择城市'), findsOneWidget);
    expect(find.text('清空历史'), findsOneWidget);
    expect(find.text('杭州'), findsOneWidget);
    expect(find.text('深圳'), findsOneWidget);
  });
}
