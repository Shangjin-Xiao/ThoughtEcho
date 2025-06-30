/// Mock LocationService for testing
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

import 'package:thoughtecho/services/location_service.dart';

class MockLocationService extends ChangeNotifier {
  Position? _currentPosition;
  String? _currentAddress;
  bool _hasLocationPermission = false;
  bool _isLocationServiceEnabled = false;
  bool _isLoading = false;
  List<CityInfo> _searchResults = [];
  bool _isSearching = false;
  String? _lastError;

  // Getters
  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get isLoading => _isLoading;
  List<CityInfo> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get lastError => _lastError;

  /// Initialize mock location service
  Future<void> initialize() async {
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Set default mock location (Beijing)
    _currentPosition = Position(
      latitude: 39.9042,
      longitude: 116.4074,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
    
    _currentAddress = '北京市朝阳区';
    _hasLocationPermission = true;
    _isLocationServiceEnabled = true;
    
    notifyListeners();
  }

  /// Request location permission
  Future<bool> requestPermission() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _hasLocationPermission = true;
    notifyListeners();
    return true;
  }

  /// Check location permission
  Future<bool> checkPermission() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return _hasLocationPermission;
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    _isLoading = true;
    notifyListeners();
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!_hasLocationPermission) {
      _lastError = '位置权限被拒绝';
      _isLoading = false;
      notifyListeners();
      throw Exception('位置权限被拒绝');
    }
    
    if (!_isLocationServiceEnabled) {
      _lastError = '位置服务未启用';
      _isLoading = false;
      notifyListeners();
      throw Exception('位置服务未启用');
    }
    
    // Return mock position
    _currentPosition = Position(
      latitude: 39.9042 + (DateTime.now().millisecond / 100000), // Add slight variation
      longitude: 116.4074 + (DateTime.now().millisecond / 100000),
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
    
    _isLoading = false;
    notifyListeners();
    return _currentPosition;
  }

  /// Get address from coordinates
  Future<String?> getAddressFromCoordinates(double latitude, double longitude) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Mock address based on coordinates
    if (latitude >= 39.8 && latitude <= 40.2 && longitude >= 116.2 && longitude <= 116.6) {
      _currentAddress = '北京市朝阳区';
    } else if (latitude >= 31.1 && latitude <= 31.4 && longitude >= 121.3 && longitude <= 121.7) {
      _currentAddress = '上海市浦东新区';
    } else if (latitude >= 22.4 && latitude <= 22.8 && longitude >= 113.8 && longitude <= 114.5) {
      _currentAddress = '广东省深圳市南山区';
    } else {
      _currentAddress = '未知位置';
    }
    
    notifyListeners();
    return _currentAddress;
  }

  /// Search cities
  Future<List<CityInfo>> searchCities(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return _searchResults;
    }
    
    _isSearching = true;
    notifyListeners();
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Mock search results
    final mockCities = [
      CityInfo(
        name: '北京',
        fullName: '中国北京市',
        lat: 39.9042,
        lon: 116.4074,
        country: '中国',
        province: '北京市',
      ),
      CityInfo(
        name: '上海',
        fullName: '中国上海市',
        lat: 31.2304,
        lon: 121.4737,
        country: '中国',
        province: '上海市',
      ),
      CityInfo(
        name: '深圳',
        fullName: '中国广东省深圳市',
        lat: 22.5431,
        lon: 114.0579,
        country: '中国',
        province: '广东省',
      ),
      CityInfo(
        name: '杭州',
        fullName: '中国浙江省杭州市',
        lat: 30.2741,
        lon: 120.1551,
        country: '中国',
        province: '浙江省',
      ),
    ];
    
    _searchResults = mockCities
        .where((city) => city.name.contains(query) || city.fullName.contains(query))
        .toList();
    
    _isSearching = false;
    notifyListeners();
    return _searchResults;
  }

  /// Select city
  Future<void> selectCity(CityInfo city) async {
    await Future.delayed(const Duration(milliseconds: 100));
    
    _currentPosition = Position(
      latitude: city.lat,
      longitude: city.lon,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
    
    _currentAddress = city.fullName;
    notifyListeners();
  }

  /// Enable location service
  void enableLocationService() {
    _isLocationServiceEnabled = true;
    notifyListeners();
  }

  /// Disable location service
  void disableLocationService() {
    _isLocationServiceEnabled = false;
    notifyListeners();
  }

  /// Set permission status
  void setPermissionStatus(bool granted) {
    _hasLocationPermission = granted;
    notifyListeners();
  }

  /// Simulate error
  void simulateError(String error) {
    _lastError = error;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Set mock position
  void setMockPosition(double latitude, double longitude, {String? address}) {
    _currentPosition = Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
    
    if (address != null) {
      _currentAddress = address;
    }
    
    notifyListeners();
  }

  /// Get formatted address
  String getFormattedAddress() {
    return _currentAddress ?? '未知位置';
  }

  /// Get coordinates string
  String getCoordinatesString() {
    if (_currentPosition == null) return '未知坐标';
    return '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
  }
}

/// Mock CityInfo class for testing
class CityInfo {
  final String name;
  final String fullName;
  final double lat;
  final double lon;
  final String country;
  final String province;

  CityInfo({
    required this.name,
    required this.fullName,
    required this.lat,
    required this.lon,
    required this.country,
    required this.province,
  });

  @override
  String toString() => fullName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CityInfo &&
        other.name == name &&
        other.fullName == fullName &&
        other.lat == lat &&
        other.lon == lon;
  }

  @override
  int get hashCode => Object.hash(name, fullName, lat, lon);
}