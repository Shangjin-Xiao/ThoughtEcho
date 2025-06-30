import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import '../../lib/services/weather_service.dart';

// Mock class generation annotation
@GenerateMocks([WeatherService])
class MockWeatherService extends Mock implements WeatherService {
  static const Map<String, dynamic> _mockBeijingWeather = {
    'name': '北京',
    'weather': [
      {
        'main': 'Clear',
        'description': '晴朗',
        'icon': '01d',
      }
    ],
    'main': {
      'temp': 25.0,
      'feels_like': 27.0,
      'humidity': 60,
      'pressure': 1013,
    },
    'visibility': 10000,
    'wind': {
      'speed': 3.2,
      'deg': 180,
    },
    'sys': {
      'country': 'CN',
      'sunrise': 1640745600,
      'sunset': 1640782800,
    },
  };

  static const Map<String, dynamic> _mockShanghaiWeather = {
    'name': '上海',
    'weather': [
      {
        'main': 'Clouds',
        'description': '多云',
        'icon': '03d',
      }
    ],
    'main': {
      'temp': 22.0,
      'feels_like': 24.0,
      'humidity': 75,
      'pressure': 1015,
    },
    'visibility': 8000,
    'wind': {
      'speed': 2.8,
      'deg': 120,
    },
    'sys': {
      'country': 'CN',
      'sunrise': 1640745600,
      'sunset': 1640782800,
    },
  };

  bool _isLoading = false;
  Map<String, dynamic>? _lastWeatherData;

  @override
  bool get isLoading => _isLoading;

  @override
  Future<Map<String, dynamic>?> getCurrentWeather({
    double? latitude,
    double? longitude,
    String? cityName,
  }) async {
    _isLoading = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 600));

    Map<String, dynamic>? weatherData;

    if (cityName != null) {
      // Return mock weather based on city name
      if (cityName.contains('北京') || cityName.toLowerCase().contains('beijing')) {
        weatherData = _mockBeijingWeather;
      } else if (cityName.contains('上海') || cityName.toLowerCase().contains('shanghai')) {
        weatherData = _mockShanghaiWeather;
      } else {
        // Default weather for unknown cities
        weatherData = {
          'name': cityName,
          'weather': [
            {
              'main': 'Clear',
              'description': '晴朗',
              'icon': '01d',
            }
          ],
          'main': {
            'temp': 20.0,
            'feels_like': 22.0,
            'humidity': 65,
            'pressure': 1010,
          },
          'visibility': 10000,
          'wind': {
            'speed': 2.5,
            'deg': 90,
          },
          'sys': {
            'country': 'UN',
            'sunrise': 1640745600,
            'sunset': 1640782800,
          },
        };
      }
    } else if (latitude != null && longitude != null) {
      // Return mock weather based on coordinates
      if (latitude > 39 && latitude < 41 && longitude > 116 && longitude < 118) {
        weatherData = _mockBeijingWeather;
      } else if (latitude > 31 && latitude < 32 && longitude > 121 && longitude < 122) {
        weatherData = _mockShanghaiWeather;
      } else {
        // Default weather for other coordinates
        weatherData = {
          'name': '未知地区',
          'weather': [
            {
              'main': 'Clear',
              'description': '晴朗',
              'icon': '01d',
            }
          ],
          'main': {
            'temp': 18.0,
            'feels_like': 20.0,
            'humidity': 70,
            'pressure': 1008,
          },
          'visibility': 9000,
          'wind': {
            'speed': 3.0,
            'deg': 150,
          },
          'sys': {
            'country': 'UN',
            'sunrise': 1640745600,
            'sunset': 1640782800,
          },
        };
      }
    }

    _lastWeatherData = weatherData;
    _isLoading = false;
    notifyListeners();

    return weatherData;
  }

  @override
  Future<List<Map<String, dynamic>>> getForecast({
    double? latitude,
    double? longitude,
    String? cityName,
    int days = 5,
  }) async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800));

    // Generate mock forecast data
    final forecast = <Map<String, dynamic>>[];
    final baseTemp = 20.0;
    final weatherTypes = ['Clear', 'Clouds', 'Rain', 'Snow'];
    final weatherDescriptions = ['晴朗', '多云', '雨', '雪'];
    final weatherIcons = ['01d', '03d', '10d', '13d'];

    for (int i = 0; i < days; i++) {
      final weatherIndex = i % weatherTypes.length;
      forecast.add({
        'dt': DateTime.now().add(Duration(days: i)).millisecondsSinceEpoch ~/ 1000,
        'weather': [
          {
            'main': weatherTypes[weatherIndex],
            'description': weatherDescriptions[weatherIndex],
            'icon': weatherIcons[weatherIndex],
          }
        ],
        'main': {
          'temp': baseTemp + (i * 2) - 2,
          'feels_like': baseTemp + (i * 2),
          'humidity': 60 + (i * 5),
          'pressure': 1010 + i,
        },
        'wind': {
          'speed': 2.0 + (i * 0.5),
          'deg': 90 + (i * 30),
        },
      });
    }

    _isLoading = false;
    notifyListeners();

    return forecast;
  }

  @override
  String formatTemperature(double temperature) {
    return '${temperature.round()}°C';
  }

  @override
  String getWeatherDescription(Map<String, dynamic> weatherData) {
    try {
      final weather = weatherData['weather'] as List;
      if (weather.isNotEmpty) {
        return weather.first['description'] as String;
      }
    } catch (e) {
      // Ignore error and return default
    }
    return '未知天气';
  }

  @override
  String getWeatherIcon(Map<String, dynamic> weatherData) {
    try {
      final weather = weatherData['weather'] as List;
      if (weather.isNotEmpty) {
        return weather.first['icon'] as String;
      }
    } catch (e) {
      // Ignore error and return default
    }
    return '01d';
  }

  @override
  double getTemperature(Map<String, dynamic> weatherData) {
    try {
      final main = weatherData['main'] as Map<String, dynamic>;
      return (main['temp'] as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  @override
  double getHumidity(Map<String, dynamic> weatherData) {
    try {
      final main = weatherData['main'] as Map<String, dynamic>;
      return (main['humidity'] as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  @override
  double getWindSpeed(Map<String, dynamic> weatherData) {
    try {
      final wind = weatherData['wind'] as Map<String, dynamic>;
      return (wind['speed'] as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  @override
  Future<bool> testConnection() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true; // Always successful in mock
  }

  // Test helper methods
  void setIsLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  Map<String, dynamic>? get lastWeatherData => _lastWeatherData;

  void setMockWeatherData(Map<String, dynamic>? data) {
    _lastWeatherData = data;
    notifyListeners();
  }

  void simulateNetworkError() {
    throw Exception('Mock weather service network error');
  }

  void resetState() {
    _isLoading = false;
    _lastWeatherData = null;
    notifyListeners();
  }

  // Mock specific weather conditions
  Map<String, dynamic> getMockSunnyWeather() => Map.from(_mockBeijingWeather);
  Map<String, dynamic> getMockCloudyWeather() => Map.from(_mockShanghaiWeather);
  
  Map<String, dynamic> getMockRainyWeather() => {
    'name': '测试城市',
    'weather': [
      {
        'main': 'Rain',
        'description': '雨',
        'icon': '10d',
      }
    ],
    'main': {
      'temp': 15.0,
      'feels_like': 13.0,
      'humidity': 85,
      'pressure': 1005,
    },
    'visibility': 5000,
    'wind': {
      'speed': 4.5,
      'deg': 270,
    },
    'sys': {
      'country': 'TEST',
      'sunrise': 1640745600,
      'sunset': 1640782800,
    },
  };
}