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
      ) as bool;

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
      ) as bool;

  @override
  bool get hasValidWeatherData => super.noSuchMethod(
        Invocation.getter(#hasValidWeatherData),
        returnValue: true,
      ) as bool;

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
  @override
  String? get localeCode => 'zh';
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

  testWidgets(
      'renders header, weather card, search bar, and popular city chips',
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
    expect(find.text('热门城市'), findsNothing); // label is domesticCities
    expect(find.text('国内主要城市'), findsOneWidget);
    expect(find.text('国际主要城市'), findsOneWidget);
    expect(find.text('北京'), findsWidgets);
    expect(find.text('上海'), findsWidgets);
    expect(find.text('东京'), findsWidgets);
  });

  testWidgets('instant local filter updates when typing in search field',
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

    // Type 'sz' into search field
    await tester.enterText(find.byType(TextField), 'sz');
    await tester.pump();

    // Should find Shenzhen or Suzhou in search results
    expect(find.text('深圳'), findsWidgets);
    expect(find.text('苏州'), findsWidgets);
  });
}
