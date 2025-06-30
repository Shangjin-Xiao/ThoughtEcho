import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:geolocator/geolocator.dart';
import '../../lib/services/location_service.dart';

// Mock class generation annotation
@GenerateMocks([LocationService])
class MockLocationService extends Mock implements LocationService {
  static const Position _mockPosition = Position(
    longitude: 116.4074,
    latitude: 39.9042,
    timestamp: null,
    accuracy: 10.0,
    altitude: 0.0,
    heading: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0,
    altitudeAccuracy: 0.0,
    headingAccuracy: 0.0,
  );

  static const String _mockAddress = '北京市朝阳区';
  
  bool _hasLocationPermission = true;
  bool _isLocationServiceEnabled = true;
  bool _isLoading = false;
  Position? _currentPosition = _mockPosition;
  String? _currentAddress = _mockAddress;
  List<CityInfo> _searchResults = [];
  bool _isSearching = false;

  @override
  Position? get currentPosition => _currentPosition;

  @override
  String? get currentAddress => _currentAddress;

  @override
  bool get hasLocationPermission => _hasLocationPermission;

  @override
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;

  @override
  bool get isLoading => _isLoading;

  @override
  List<CityInfo> get searchResults => _searchResults;

  @override
  bool get isSearching => _isSearching;

  @override
  Future<void> getCurrentLocation({bool forceRefresh = false}) async {
    _isLoading = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    if (_hasLocationPermission && _isLocationServiceEnabled) {
      _currentPosition = _mockPosition;
      _currentAddress = _mockAddress;
    } else {
      _currentPosition = null;
      _currentAddress = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  Future<bool> requestLocationPermission() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _hasLocationPermission = true;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> checkLocationPermission() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _hasLocationPermission;
  }

  @override
  Future<bool> checkLocationService() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _isLocationServiceEnabled;
  }

  @override
  Future<String?> getAddressFromCoordinates(double latitude, double longitude) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Mock address based on coordinates
    if (latitude > 39 && latitude < 41 && longitude > 116 && longitude < 118) {
      return '北京市朝阳区';
    } else if (latitude > 31 && latitude < 32 && longitude > 121 && longitude < 122) {
      return '上海市浦东新区';
    } else if (latitude > 22 && latitude < 24 && longitude > 113 && longitude < 115) {
      return '广东省深圳市';
    } else {
      return '未知地区 ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    }
  }

  @override
  Future<List<CityInfo>> searchCities(String query) async {
    _isSearching = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    // Mock search results
    final results = <CityInfo>[];
    
    if (query.contains('北京') || query.toLowerCase().contains('beijing')) {
      results.add(CityInfo(
        name: '北京',
        fullName: '中国 北京市',
        lat: 39.9042,
        lon: 116.4074,
        country: '中国',
        province: '北京市',
      ));
    }
    
    if (query.contains('上海') || query.toLowerCase().contains('shanghai')) {
      results.add(CityInfo(
        name: '上海',
        fullName: '中国 上海市',
        lat: 31.2304,
        lon: 121.4737,
        country: '中国',
        province: '上海市',
      ));
    }
    
    if (query.contains('深圳') || query.toLowerCase().contains('shenzhen')) {
      results.add(CityInfo(
        name: '深圳',
        fullName: '中国 广东省 深圳市',
        lat: 22.5431,
        lon: 114.0579,
        country: '中国',
        province: '广东省',
      ));
    }
    
    if (query.contains('广州') || query.toLowerCase().contains('guangzhou')) {
      results.add(CityInfo(
        name: '广州',
        fullName: '中国 广东省 广州市',
        lat: 23.1291,
        lon: 113.2644,
        country: '中国',
        province: '广东省',
      ));
    }

    // If no specific matches, add some default results
    if (results.isEmpty && query.isNotEmpty) {
      results.addAll([
        CityInfo(
          name: '测试城市1',
          fullName: '测试国家 测试省份 测试城市1',
          lat: 30.0,
          lon: 120.0,
          country: '测试国家',
          province: '测试省份',
        ),
        CityInfo(
          name: '测试城市2',
          fullName: '测试国家 测试省份 测试城市2',
          lat: 35.0,
          lon: 110.0,
          country: '测试国家',
          province: '测试省份',
        ),
      ]);
    }

    _searchResults = results;
    _isSearching = false;
    notifyListeners();

    return results;
  }

  @override
  Future<void> clearSearchResults() async {
    _searchResults = [];
    notifyListeners();
  }

  @override
  Future<void> selectCity(CityInfo city) async {
    _currentPosition = Position(
      longitude: city.lon,
      latitude: city.lat,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
    _currentAddress = city.fullName;
    notifyListeners();
  }

  // Test helper methods
  void setHasLocationPermission(bool hasPermission) {
    _hasLocationPermission = hasPermission;
    notifyListeners();
  }

  void setIsLocationServiceEnabled(bool isEnabled) {
    _isLocationServiceEnabled = isEnabled;
    notifyListeners();
  }

  void setMockPosition(Position? position) {
    _currentPosition = position;
    notifyListeners();
  }

  void setMockAddress(String? address) {
    _currentAddress = address;
    notifyListeners();
  }

  void simulateLocationError() {
    _currentPosition = null;
    _currentAddress = null;
    _hasLocationPermission = false;
    notifyListeners();
  }

  void resetToDefaults() {
    _hasLocationPermission = true;
    _isLocationServiceEnabled = true;
    _isLoading = false;
    _currentPosition = _mockPosition;
    _currentAddress = _mockAddress;
    _searchResults = [];
    _isSearching = false;
    notifyListeners();
  }
}