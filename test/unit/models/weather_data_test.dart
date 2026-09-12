import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/weather_data.dart';

void main() {
  group('WeatherData constructors', () {
    test('default constructor creates instance with all provided fields', () {
      final now = DateTime.now();
      final data = WeatherData(
        key: 'clear',
        description: 'Sunny',
        temperature: 25.5,
        temperatureText: '25.5°C',
        iconCode: 'clear_day',
        timestamp: now,
        latitude: 31.2304,
        longitude: 121.4737,
      );

      expect(data.key, 'clear');
      expect(data.description, 'Sunny');
      expect(data.temperature, 25.5);
      expect(data.temperatureText, '25.5°C');
      expect(data.iconCode, 'clear_day');
      expect(data.timestamp, now);
      expect(data.latitude, 31.2304);
      expect(data.longitude, 121.4737);
    });

    test(
        'WeatherData.error creates error instance with default or custom message',
        () {
      final dataDefault = WeatherData.error();
      expect(dataDefault.key, 'error');
      expect(dataDefault.description, 'error');
      expect(dataDefault.iconCode, 'error');
      expect(dataDefault.temperature, isNull);
      expect(dataDefault.temperatureText, isNull);

      final dataCustom = WeatherData.error('Network failure');
      expect(dataCustom.key, 'error');
      expect(dataCustom.description, 'Network failure');
      expect(dataCustom.iconCode, 'error');
    });

    test('WeatherData.unknown creates unknown instance', () {
      final data = WeatherData.unknown();
      expect(data.key, 'unknown');
      expect(data.description, 'unknown');
      expect(data.iconCode, 'cloudy');
      expect(data.temperature, isNull);
      expect(data.temperatureText, isNull);
    });
  });

  group('WeatherData JSON serialization', () {
    test('fromJson deserializes complete valid JSON', () {
      final json = {
        'key': 'rain',
        'description': 'Light Rain',
        'temperature': 18,
        'temperatureText': '18°C',
        'iconCode': 'rainy',
        'timestamp': '2025-01-01T12:00:00.000Z',
        'latitude': 30.0,
        'longitude': 120.0,
      };

      final data = WeatherData.fromJson(json);

      expect(data.key, 'rain');
      expect(data.description, 'Light Rain');
      expect(data.temperature, 18.0);
      expect(data.temperatureText, '18°C');
      expect(data.iconCode, 'rainy');
      expect(data.timestamp, DateTime.parse('2025-01-01T12:00:00.000Z'));
      expect(data.latitude, 30.0);
      expect(data.longitude, 120.0);
    });

    test('fromJson provides fallbacks for missing or null fields', () {
      final json = <String, dynamic>{};

      final data = WeatherData.fromJson(json);

      expect(data.key, 'unknown');
      expect(data.description, 'unknown');
      expect(data.temperature, isNull);
      expect(data.temperatureText, isNull);
      expect(data.iconCode, 'cloudy');
      expect(data.latitude, isNull);
      expect(data.longitude, isNull);
      expect(data.timestamp, isNotNull);
    });

    test('toJson serializes WeatherData instance correctly', () {
      final timestamp = DateTime.parse('2025-01-01T12:00:00.000Z');
      final data = WeatherData(
        key: 'snow',
        description: 'Light Snow',
        temperature: -2.5,
        temperatureText: '-2.5°C',
        iconCode: 'snowy',
        timestamp: timestamp,
        latitude: 40.0,
        longitude: 116.0,
      );

      final json = data.toJson();

      expect(json, {
        'key': 'snow',
        'description': 'Light Snow',
        'temperature': -2.5,
        'temperatureText': '-2.5°C',
        'iconCode': 'snowy',
        'timestamp': timestamp.toIso8601String(),
        'latitude': 40.0,
        'longitude': 116.0,
      });
    });
  });

  group('WeatherData methods and getters', () {
    test('isValid evaluates correctness based on key', () {
      final clear = WeatherData(
        key: 'clear',
        description: 'clear',
        iconCode: 'clear_day',
        timestamp: DateTime.now(),
      );
      expect(clear.isValid, isTrue);

      final unknown = WeatherData.unknown();
      expect(unknown.isValid, isFalse);

      final error = WeatherData.error();
      expect(error.isValid, isFalse);
    });

    test('isExpired checks time difference against cache duration', () {
      final recent = WeatherData(
        key: 'clear',
        description: 'clear',
        iconCode: 'clear_day',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(recent.isExpired(), isFalse);

      final expired = WeatherData(
        key: 'clear',
        description: 'clear',
        iconCode: 'clear_day',
        timestamp: DateTime.now().subtract(const Duration(hours: 4)),
      );
      expect(expired.isExpired(), isTrue);

      expect(recent.isExpired(const Duration(minutes: 30)), isTrue);
    });

    test('isLocationMatch checks coordinates within tolerance', () {
      final data = WeatherData(
        key: 'clear',
        description: 'clear',
        iconCode: 'clear_day',
        timestamp: DateTime.now(),
        latitude: 31.2304,
        longitude: 121.4737,
      );

      expect(data.isLocationMatch(31.2300, 121.4700), isTrue);
      expect(data.isLocationMatch(32.0000, 121.4737), isFalse);

      final dataNoLocation = WeatherData(
        key: 'clear',
        description: 'clear',
        iconCode: 'clear_day',
        timestamp: DateTime.now(),
      );
      expect(dataNoLocation.isLocationMatch(31.2304, 121.4737), isFalse);
    });

    test('icon getter returns appropriate IconData for various icon codes', () {
      IconData getIconFor(String code) => WeatherData(
            key: 'test',
            description: 'test',
            iconCode: code,
            timestamp: DateTime.now(),
          ).icon;

      expect(getIconFor('clear_day'), Icons.wb_sunny);
      expect(getIconFor('clear_night'), Icons.nightlight_round);
      expect(getIconFor('cloudy'), Icons.cloud);
      expect(getIconFor('fog'), Icons.cloud);
      expect(getIconFor('rainy'), Icons.water_drop);
      expect(getIconFor('thunderstorm'), Icons.flash_on);
      expect(getIconFor('snowy'), Icons.ac_unit);
      expect(getIconFor('hail'), Icons.grain);
      expect(getIconFor('error'), Icons.error_outline);
      expect(getIconFor('unknown_code'), Icons.cloud_queue);
    });

    testWidgets('formattedText formats description and temperature with l10n',
        (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return Container();
            },
          ),
        ),
      );

      final dataWithTemp = WeatherData(
        key: 'clear',
        description: 'clear',
        temperatureText: '25°C',
        iconCode: 'clear_day',
        timestamp: DateTime.now(),
      );

      final formattedWithTemp = dataWithTemp.formattedText(l10n);
      expect(formattedWithTemp, contains('25°C'));

      final dataWithoutTemp = WeatherData(
        key: 'clear',
        description: 'clear',
        iconCode: 'clear_day',
        timestamp: DateTime.now(),
      );

      final formattedWithoutTemp = dataWithoutTemp.formattedText(l10n);
      expect(formattedWithoutTemp, equals(l10n.weatherClear));
    });

    test('equality and hashCode work as expected', () {
      final now = DateTime.now();
      final a = WeatherData(
        key: 'clear',
        description: 'Sunny',
        temperature: 25.0,
        iconCode: 'clear_day',
        timestamp: now,
        latitude: 30.0,
        longitude: 120.0,
      );
      final b = WeatherData(
        key: 'clear',
        description: 'Sunny',
        temperature: 25.0,
        iconCode: 'clear_day',
        timestamp: now,
        latitude: 30.0,
        longitude: 120.0,
      );
      final c = WeatherData(
        key: 'cloudy',
        description: 'Cloudy',
        temperature: 20.0,
        iconCode: 'cloudy',
        timestamp: now,
        latitude: 30.0,
        longitude: 120.0,
      );

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == Object(), isFalse);
    });

    test('toString returns formatted string representation', () {
      final data = WeatherData(
        key: 'clear',
        description: 'Sunny',
        temperature: 25.0,
        iconCode: 'clear_day',
        timestamp: DateTime.now(),
      );

      expect(data.toString(),
          'WeatherData(key: clear, description: Sunny, temperature: 25.0)');
    });
  });

  group('WeatherCodeMapper methods', () {
    test(
        'getKeyByDescription maps known descriptions and returns null for unknown',
        () {
      expect(WeatherCodeMapper.getKeyByDescription('clear'), 'clear');
      expect(WeatherCodeMapper.getKeyByDescription('partly_cloudy'),
          'partly_cloudy');
      expect(WeatherCodeMapper.getKeyByDescription('thunderstorm_heavy'),
          'thunderstorm_heavy');
      expect(WeatherCodeMapper.getKeyByDescription('non_existent'), isNull);
      expect(WeatherCodeMapper.getKeyByDescription(''), isNull);
    });

    test('getWeatherKey maps WMO weather codes correctly', () {
      expect(WeatherCodeMapper.getWeatherKey(0), 'clear');
      expect(WeatherCodeMapper.getWeatherKey(1), 'partly_cloudy');
      expect(WeatherCodeMapper.getWeatherKey(2), 'partly_cloudy');
      expect(WeatherCodeMapper.getWeatherKey(3), 'cloudy');
      expect(WeatherCodeMapper.getWeatherKey(45), 'fog');
      expect(WeatherCodeMapper.getWeatherKey(48), 'fog');
      expect(WeatherCodeMapper.getWeatherKey(51), 'drizzle');
      expect(WeatherCodeMapper.getWeatherKey(56), 'freezing_rain');
      expect(WeatherCodeMapper.getWeatherKey(61), 'rain');
      expect(WeatherCodeMapper.getWeatherKey(71), 'snow');
      expect(WeatherCodeMapper.getWeatherKey(77), 'snow_grains');
      expect(WeatherCodeMapper.getWeatherKey(80), 'rain_shower');
      expect(WeatherCodeMapper.getWeatherKey(85), 'snow_shower');
      expect(WeatherCodeMapper.getWeatherKey(95), 'thunderstorm');
      expect(WeatherCodeMapper.getWeatherKey(96), 'thunderstorm_heavy');
      expect(WeatherCodeMapper.getWeatherKey(999), 'unknown');
    });

    test('getDescription returns non-UI description string', () {
      expect(WeatherCodeMapper.getDescription('clear'), 'clear');
      expect(WeatherCodeMapper.getDescription('rain'), 'rain');
      expect(WeatherCodeMapper.getDescription('unknown_key'), 'unknown');
    });

    testWidgets(
        'getLocalizedDescription returns localized strings for all keys',
        (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return Container();
            },
          ),
        ),
      );

      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'clear'),
          l10n.weatherClear);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'partly_cloudy'),
          l10n.weatherPartlyCloudy);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'cloudy'),
          l10n.weatherCloudy);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'fog'),
          l10n.weatherFog);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'drizzle'),
          l10n.weatherDrizzle);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'freezing_rain'),
          l10n.weatherFreezingRain);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'rain'),
          l10n.weatherRain);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'snow'),
          l10n.weatherSnow);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'snow_grains'),
          l10n.weatherSnowGrains);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'rain_shower'),
          l10n.weatherRainShower);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'snow_shower'),
          l10n.weatherSnowShower);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'thunderstorm'),
          l10n.weatherThunderstorm);
      expect(
          WeatherCodeMapper.getLocalizedDescription(l10n, 'thunderstorm_heavy'),
          l10n.weatherThunderstormHeavy);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'error'),
          l10n.weatherError);
      expect(WeatherCodeMapper.getLocalizedDescription(l10n, 'unknown_key'),
          l10n.weatherUnknown);
    });

    test('getIconCode maps keys to icon codes', () {
      expect(WeatherCodeMapper.getIconCode('clear'), 'clear_day');
      expect(WeatherCodeMapper.getIconCode('rain'), 'rainy');
      expect(WeatherCodeMapper.getIconCode('unknown_key'), 'cloudy');
    });

    test('getIcon maps key directly to IconData', () {
      expect(WeatherCodeMapper.getIcon('clear'), Icons.wb_sunny);
      expect(WeatherCodeMapper.getIcon('rain'), Icons.water_drop);
      expect(WeatherCodeMapper.getIcon('thunderstorm'), Icons.flash_on);
      expect(WeatherCodeMapper.getIcon('unknown_key'), Icons.cloud);
    });
  });
}
