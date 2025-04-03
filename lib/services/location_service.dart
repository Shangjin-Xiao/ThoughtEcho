import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/http_utils.dart';

class CityInfo {
  final String name; // 城市名称
  final String fullName; // 完整名称包括国家和省份
  final double lat; // 纬度
  final double lon; // 经度
  final String country; // 国家
  final String province; // 省/州
  
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
}

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  String? _currentAddress;
  bool _hasLocationPermission = false;
  bool _isLocationServiceEnabled = false;
  bool _isLoading = false;
  
  // 城市搜索结果
  List<CityInfo> _searchResults = [];
  bool _isSearching = false;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get isLoading => _isLoading;
  List<CityInfo> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  // 地址组件
  String? _country;
  String? _province;
  String? _city;
  String? _district;

  String? get country => _country;
  String? get province => _province; 
  String? get city => _city;
  String? get district => _district;
  
  // 热门城市列表
  final List<CityInfo> popularCities = [
    CityInfo(
      name: '北京', 
      fullName: '中国, 北京', 
      lat: 39.9042, 
      lon: 116.4074,
      country: '中国',
      province: '北京'
    ),
    CityInfo(
      name: '上海', 
      fullName: '中国, 上海', 
      lat: 31.2304, 
      lon: 121.4737,
      country: '中国',
      province: '上海'
    ),
    CityInfo(
      name: '广州', 
      fullName: '中国, 广东, 广州', 
      lat: 23.1291, 
      lon: 113.2644,
      country: '中国',
      province: '广东'
    ),
    CityInfo(
      name: '深圳', 
      fullName: '中国, 广东, 深圳', 
      lat: 22.5431, 
      lon: 114.0579,
      country: '中国',
      province: '广东'
    ),
    CityInfo(
      name: '杭州', 
      fullName: '中国, 浙江, 杭州', 
      lat: 30.2741, 
      lon: 120.1551,
      country: '中国',
      province: '浙江'
    ),
  ];

  // 初始化位置服务
  Future<void> init() async {
    debugPrint('开始初始化位置服务');
    try {
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (_isLocationServiceEnabled) {
        debugPrint('位置服务已启用');
        final permission = await Geolocator.checkPermission();
        _hasLocationPermission = (permission == LocationPermission.whileInUse || 
                                permission == LocationPermission.always);
        debugPrint('位置权限状态: $_hasLocationPermission');
        
        if (_hasLocationPermission) {
          // 尝试获取位置
          getCurrentLocation().then((position) {
            debugPrint('初始化时获取位置: ${position?.latitude}, ${position?.longitude}');
          });
        }
      } else {
        debugPrint('位置服务未启用');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('初始化位置服务错误: $e');
    }
  }

  // 检查位置权限
  Future<bool> checkLocationPermission() async {
    try {
      // 检查位置服务是否启用
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      
      if (!_isLocationServiceEnabled) {
        return false;
      }
      
      // 检查位置权限状态
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _hasLocationPermission = false;
          notifyListeners();
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        _hasLocationPermission = false;
        notifyListeners();
        return false;
      }
      
      _hasLocationPermission = (permission == LocationPermission.whileInUse || 
                              permission == LocationPermission.always);
      
      notifyListeners();
      return _hasLocationPermission;
    } catch (e) {
      debugPrint('检查位置权限失败: $e');
      _hasLocationPermission = false;
      notifyListeners();
      return false;
    }
  }

  // 请求位置权限
  Future<bool> requestLocationPermission() async {
    try {
      var status = await Permission.location.request();
      _hasLocationPermission = status.isGranted;
      notifyListeners();
      return _hasLocationPermission;
    } catch (e) {
      debugPrint('请求位置权限失败: $e');
      return false;
    }
  }

  // 获取当前位置
  Future<Position?> getCurrentLocation() async {
    if (!_isLocationServiceEnabled) {
      debugPrint('获取位置时，位置服务未启用');
      return null;
    }
    
    if (!_hasLocationPermission) {
      debugPrint('获取位置时，未获得位置权限');
      return null;
    }

    try {
      _isLoading = true;
      notifyListeners();
      
      debugPrint('开始获取位置...');
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      
      debugPrint('位置获取成功: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}');
      await getAddressFromLatLng();
      
      _isLoading = false;
      notifyListeners();
      return _currentPosition;
    } catch (e) {
      _isLoading = false;
      debugPrint('获取位置失败: $e');
      
      // 尝试使用最后一次已知位置
      try {
        debugPrint('尝试获取最后一次已知位置...');
        _currentPosition = await Geolocator.getLastKnownPosition();
        if (_currentPosition != null) {
          debugPrint('已获取最后一次已知位置: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}');
          await getAddressFromLatLng();
        } else {
          debugPrint('无法获取最后一次已知位置');
        }
      } catch (e2) {
        debugPrint('获取最后一次已知位置失败: $e2');
      }
      
      notifyListeners();
      return _currentPosition;
    }
  }

  // 根据经纬度获取地址信息
  Future<void> getAddressFromLatLng() async {
    if (_currentPosition == null) {
      debugPrint('没有位置信息，无法获取地址');
      return;
    }

    try {
      debugPrint('开始通过经纬度获取地址信息...');
      final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=${_currentPosition!.latitude}&lon=${_currentPosition!.longitude}&zoom=18&addressdetails=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept-Language': 'zh-CN,zh;q=0.9', 'User-Agent': 'MindTrace App'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('OpenStreetMap响应: ${response.body.substring(0, 200)}...');
        
        // 解析国家、省、市、区信息
        if (data.containsKey('address')) {
          final address = data['address'];
          _country = address['country'];
          _province = address['state'] ?? address['province'];
          _city = address['city'] ?? address['county'] ?? address['town'] ?? address['village'];
          _district = address['district'] ?? address['suburb'];
          
          // 组合完整地址显示
          _currentAddress = '$_country, $_province, $_city';
          if (_district != null && _district!.isNotEmpty) {
            _currentAddress = '$_currentAddress, $_district';
          }
          
          debugPrint('地址解析成功: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)');
        } else {
          debugPrint('响应中没有地址信息');
        }
        
        notifyListeners();
      } else {
        debugPrint('OpenStreetMap API请求失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('获取地址信息失败: $e');
    }
  }

  // 搜索城市
  Future<List<CityInfo>> searchCity(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return _searchResults;
    }
    
    try {
      _isSearching = true;
      notifyListeners();
      
      // 使用OpenStreetMap的Nominatim API搜索城市
      final url = 'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=10&featuretype=city';
      
      final response = await HttpUtils.secureGet(
        url,
        headers: {'Accept-Language': 'zh-CN,zh;q=0.9', 'User-Agent': 'MindTrace App'},
        timeoutSeconds: 15
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _searchResults = data.map((item) {
          // 提取地址信息
          final address = item['address'];
          final String cityName = address['city'] ?? address['town'] ?? address['village'] ?? item['name'];
          final String country = address['country'] ?? '';
          final String state = address['state'] ?? address['province'] ?? '';
          
          // 构建完整地址 - 国家, 省/州, 城市
          final String fullName = [country, state, cityName].where((part) => part.isNotEmpty).join(', ');
          
          return CityInfo(
            name: cityName,
            fullName: fullName,
            lat: double.parse(item['lat']),
            lon: double.parse(item['lon']),
            country: country,
            province: state,
          );
        }).toList();
      } else {
        _searchResults = [];
        debugPrint('搜索城市失败: ${response.statusCode}, ${response.body}');
      }
      
      _isSearching = false;
      notifyListeners();
      return _searchResults;
    } catch (e) {
      _isSearching = false;
      _searchResults = [];
      debugPrint('搜索城市发生错误: $e');
      notifyListeners();
      return _searchResults;
    }
  }
  
  // 使用选定的城市信息设置位置
  void setSelectedCity(CityInfo city) {
    // 手动设置位置组件
    _country = city.country;
    _province = city.province;
    _city = city.name;
    _district = null;
    
    // 更新地址字符串
    _currentAddress = '${city.country}, ${city.province}, ${city.name}';
    
    // 创建一个模拟的Position对象来保持API一致性
    _currentPosition = Position(
      latitude: city.lat,
      longitude: city.lon,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    
    notifyListeners();
  }
  
  // 获取格式化位置(国家,省份,城市,区县)
  String getFormattedLocation() {
    if (_currentAddress == null) return '';
    return '$_country,$_province,$_city${_district != null ? ',$_district' : ''}';
  }

  // 从格式化的位置字符串解析地址组件
  void parseLocationString(String? locationString) {
    if (locationString == null || locationString.isEmpty) {
      _country = null;
      _province = null;
      _city = null;
      _district = null;
      _currentAddress = null;
      return;
    }
    
    final parts = locationString.split(',');
    if (parts.length >= 3) {
      _country = parts[0];
      _province = parts[1];
      _city = parts[2];
      _district = parts.length >= 4 ? parts[3] : null;
      
      // 构建显示地址
      _currentAddress = '$_country, $_province, $_city';
      if (_district != null && _district!.isNotEmpty) {
        _currentAddress = '$_currentAddress, $_district';
      }
    }
  }
} 