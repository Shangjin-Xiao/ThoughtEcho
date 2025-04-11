import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/http_utils.dart';
import 'local_geocoding_service.dart'; // 导入本地地理编码服务

// 本地地点数据结构
class Province {
  final String name;
  final List<City> cities;
  
  Province({required this.name, required this.cities});
}

class City {
  final String name;
  final List<District> districts;
  final double lat;
  final double lon;
  
  City({required this.name, required this.districts, required this.lat, required this.lon});
}

class District {
  final String name;
  final double lat;
  final double lon;
  
  District({required this.name, required this.lat, required this.lon});
}

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
  
  // 本地数据相关
  bool _useLocalData = false; // 是否使用本地数据而非网络
  List<Province> _provinces = []; // 省份列表
  Province? _selectedProvince; // 当前选择的省份
  City? _selectedCity; // 当前选择的城市
  District? _selectedDistrict; // 当前选择的区县

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get isLoading => _isLoading;
  List<CityInfo> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  bool get useLocalData => _useLocalData;
  List<Province> get provinces => _provinces;
  Province? get selectedProvince => _selectedProvince;
  City? get selectedCity => _selectedCity;
  District? get selectedDistrict => _selectedDistrict;

  // 地址组件
  String? _country;
  String? _province;
  String? _city;
  String? _district;

  String? get country => _country;
  String? get province => _province; 
  String? get city => _city;
  String? get district => _district;
  
  // 热门城市列表 - 包含全球主要城市
  final List<CityInfo> popularCities = [
    // 中国城市
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
    // 亚洲城市
    CityInfo(
      name: '东京', 
      fullName: '日本, 东京', 
      lat: 35.6762, 
      lon: 139.6503,
      country: '日本',
      province: '东京'
    ),
    CityInfo(
      name: '首尔', 
      fullName: '韩国, 首尔', 
      lat: 37.5665, 
      lon: 126.9780,
      country: '韩国',
      province: '首尔特别市'
    ),
    CityInfo(
      name: '新加坡', 
      fullName: '新加坡', 
      lat: 1.3521, 
      lon: 103.8198,
      country: '新加坡',
      province: ''
    ),
    // 欧洲城市
    CityInfo(
      name: '伦敦', 
      fullName: '英国, 伦敦', 
      lat: 51.5074, 
      lon: -0.1278,
      country: '英国',
      province: '英格兰'
    ),
    CityInfo(
      name: '巴黎', 
      fullName: '法国, 巴黎', 
      lat: 48.8566, 
      lon: 2.3522,
      country: '法国',
      province: '法兰西岛'
    ),
    CityInfo(
      name: '柏林', 
      fullName: '德国, 柏林', 
      lat: 52.5200, 
      lon: 13.4050,
      country: '德国',
      province: '柏林'
    ),
    // 北美洲城市
    CityInfo(
      name: '纽约', 
      fullName: '美国, 纽约', 
      lat: 40.7128, 
      lon: -74.0060,
      country: '美国',
      province: '纽约州'
    ),
    CityInfo(
      name: '洛杉矶', 
      fullName: '美国, 加利福尼亚, 洛杉矶', 
      lat: 34.0522, 
      lon: -118.2437,
      country: '美国',
      province: '加利福尼亚'
    ),
    CityInfo(
      name: '多伦多', 
      fullName: '加拿大, 安大略, 多伦多', 
      lat: 43.6532, 
      lon: -79.3832,
      country: '加拿大',
      province: '安大略'
    ),
    // 大洋洲城市
    CityInfo(
      name: '悉尼', 
      fullName: '澳大利亚, 新南威尔士, 悉尼', 
      lat: -33.8688, 
      lon: 151.2093,
      country: '澳大利亚',
      province: '新南威尔士'
    ),
  ];

  // 初始化位置服务
  Future<void> init() async {
    debugPrint('开始初始化位置服务');
    try {
      // 初始化本地数据
      _initLocalData();
      
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (_isLocationServiceEnabled) {
        debugPrint('位置服务已启用');
        final permission = await Geolocator.checkPermission();
        _hasLocationPermission = (permission == LocationPermission.whileInUse || 
                                permission == LocationPermission.always);
        debugPrint('位置权限状态: $_hasLocationPermission');
        
        if (_hasLocationPermission) {
          // 默认先使用低精度定位，获取快速结果
          getCurrentLocation(highAccuracy: false).then((position) {
            debugPrint('初始化时获取位置: ${position?.latitude}, ${position?.longitude}');
          });
        }
      } else {
        debugPrint('位置服务未启用');
      }
      
      // 默认使用本地数据，避免网络请求
      _useLocalData = true;
      
      notifyListeners();
    } catch (e) {
      debugPrint('初始化位置服务错误: $e');
    }
  }
  
  // 初始化本地地点数据
  void _initLocalData() {
    // 添加中国主要省份和城市数据
    _provinces = [
      Province(name: '北京', cities: [
        City(name: '北京市', lat: 39.9042, lon: 116.4074, districts: [
          District(name: '朝阳区', lat: 39.9219, lon: 116.4439),
          District(name: '海淀区', lat: 39.9631, lon: 116.3017),
          District(name: '东城区', lat: 39.9286, lon: 116.4166),
          District(name: '西城区', lat: 39.9126, lon: 116.3656),
        ]),
      ]),
      Province(name: '上海', cities: [
        City(name: '上海市', lat: 31.2304, lon: 121.4737, districts: [
          District(name: '浦东新区', lat: 31.2231, lon: 121.5438),
          District(name: '徐汇区', lat: 31.1889, lon: 121.4365),
          District(name: '黄浦区', lat: 31.2317, lon: 121.4852),
          District(name: '静安区', lat: 31.2304, lon: 121.4551),
        ]),
      ]),
      Province(name: '广东', cities: [
        City(name: '广州市', lat: 23.1291, lon: 113.2644, districts: [
          District(name: '天河区', lat: 23.1254, lon: 113.3619),
          District(name: '越秀区', lat: 23.1289, lon: 113.2644),
          District(name: '海珠区', lat: 23.0838, lon: 113.3172),
        ]),
        City(name: '深圳市', lat: 22.5431, lon: 114.0579, districts: [
          District(name: '南山区', lat: 22.5329, lon: 113.9258),
          District(name: '福田区', lat: 22.5410, lon: 114.0550),
          District(name: '罗湖区', lat: 22.5482, lon: 114.1350),
        ]),
      ]),
      Province(name: '浙江', cities: [
        City(name: '杭州市', lat: 30.2741, lon: 120.1551, districts: [
          District(name: '西湖区', lat: 30.2595, lon: 120.1304),
          District(name: '上城区', lat: 30.2427, lon: 120.1693),
          District(name: '下城区', lat: 30.2812, lon: 120.1809),
        ]),
        City(name: '宁波市', lat: 29.8683, lon: 121.5440, districts: [
          District(name: '海曙区', lat: 29.8708, lon: 121.5510),
          District(name: '江北区', lat: 29.8869, lon: 121.5550),
        ]),
      ]),
      Province(name: '江苏', cities: [
        City(name: '南京市', lat: 32.0603, lon: 118.7969, districts: [
          District(name: '鼓楼区', lat: 32.0660, lon: 118.7700),
          District(name: '玄武区', lat: 32.0486, lon: 118.7980),
        ]),
        City(name: '苏州市', lat: 31.2990, lon: 120.5853, districts: [
          District(name: '姑苏区', lat: 31.3117, lon: 120.6170),
          District(name: '吴中区', lat: 31.2639, lon: 120.6324),
        ]),
      ]),
      Province(name: '四川', cities: [
        City(name: '成都市', lat: 30.5728, lon: 104.0668, districts: [
          District(name: '锦江区', lat: 30.6571, lon: 104.0835),
          District(name: '青羊区', lat: 30.6739, lon: 104.0617),
        ]),
      ]),
    ];
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
  Future<Position?> getCurrentLocation({bool highAccuracy = false}) async {
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
      
      debugPrint('开始获取位置，使用${highAccuracy ? "高" : "低"}精度模式...');
      
      // 使用LocalGeocodingService获取位置
      _currentPosition = await LocalGeocodingService.getCurrentPosition(
        highAccuracy: highAccuracy
      );
      
      if (_currentPosition != null) {
        debugPrint('位置获取成功: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}');
        // 使用本地解析方法获取地址
        await getAddressFromLatLng();
      } else {
        debugPrint('无法获取当前位置');
      }
      
      _isLoading = false;
      notifyListeners();
      return _currentPosition;
    } catch (e) {
      _isLoading = false;
      debugPrint('获取位置失败: $e');
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
      
      // 使用系统SDK获取地址信息
      final addressInfo = await LocalGeocodingService.getAddressFromCoordinates(
        _currentPosition!.latitude, 
        _currentPosition!.longitude
      );
      
      // 如果本地解析成功
      if (addressInfo != null) {
        _country = addressInfo['country'];
        _province = addressInfo['province'];
        _city = addressInfo['city'];
        _district = addressInfo['district'];
        _currentAddress = addressInfo['formatted_address'];
        
        debugPrint('本地地址解析成功: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)');
        notifyListeners();
        return;
      }
      
      // 如果本地解析失败且允许使用网络，尝试使用在线服务
      if (!_useLocalData) {
        try {
          await _getAddressFromLatLngOnline();
        } catch (e) {
          debugPrint('在线地址解析失败: $e');
        }
      }
    } catch (e) {
      debugPrint('获取地址信息失败: $e');
    }
  }
  
  // 使用在线服务获取地址（备用方法）
  Future<void> _getAddressFromLatLngOnline() async {
    try {
      final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=${_currentPosition!.latitude}&lon=${_currentPosition!.longitude}&zoom=18&addressdetails=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept-Language': 'zh-CN,zh;q=0.9', 'User-Agent': 'MindTrace App'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
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
          
          debugPrint('在线地址解析成功: $_currentAddress');
        }
      }
    } catch (e) {
      throw Exception('在线地址解析调用失败: $e');
    }
  }

  // 设置是否使用本地数据
  void setUseLocalData(bool useLocal) {
    _useLocalData = useLocal;
    notifyListeners();
  }
  
  // 搜索城市
  Future<List<CityInfo>> searchCity(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return _searchResults;
    }
    
    // 如果设置为使用本地数据或检测到网络不可用，则使用本地搜索
    if (_useLocalData) {
      return _searchCityLocal(query);
    } else {
      try {
        return await _searchCityOnline(query);
      } catch (e) {
        debugPrint('在线搜索失败，切换到本地搜索: $e');
        // 如果在线搜索失败，自动尝试本地搜索
        return _searchCityLocal(query);
      }
    }
  }

  // 本地搜索城市
  List<CityInfo> _searchCityLocal(String query) {
    _isSearching = true;
    notifyListeners();
    
    query = query.toLowerCase();
    List<CityInfo> results = [];
    
    // 1. 首先搜索热门城市
    results.addAll(popularCities.where((city) => 
        city.name.toLowerCase().contains(query) || 
        city.fullName.toLowerCase().contains(query)));
    
    // 2. 然后搜索本地省份、城市和区县数据
    for (var province in _provinces) {
      if (province.name.toLowerCase().contains(query)) {
        // 如果省名匹配，添加该省的所有城市
        for (var city in province.cities) {
          results.add(CityInfo(
            name: city.name,
            fullName: '中国, ${province.name}, ${city.name}',
            lat: city.lat,
            lon: city.lon,
            country: '中国',
            province: province.name,
          ));
        }
      } else {
        // 搜索城市
        for (var city in province.cities) {
          if (city.name.toLowerCase().contains(query)) {
            results.add(CityInfo(
              name: city.name,
              fullName: '中国, ${province.name}, ${city.name}',
              lat: city.lat,
              lon: city.lon,
              country: '中国',
              province: province.name,
            ));
          } else {
            // 搜索区县
            for (var district in city.districts) {
              if (district.name.toLowerCase().contains(query)) {
                results.add(CityInfo(
                  name: district.name,
                  fullName: '中国, ${province.name}, ${city.name}, ${district.name}',
                  lat: district.lat,
                  lon: district.lon,
                  country: '中国',
                  province: province.name,
                ));
              }
            }
          }
        }
      }
    }
    
    // 去重
    final Map<String, CityInfo> uniqueResults = {};
    for (var city in results) {
      uniqueResults[city.fullName] = city;
    }
    
    _searchResults = uniqueResults.values.toList();
    _isSearching = false;
    notifyListeners();
    return _searchResults;
  }

  // 在线搜索城市
  Future<List<CityInfo>> _searchCityOnline(String query) async {
    _isSearching = true;
    notifyListeners();
    
    try {
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
    } catch (e) {
      _searchResults = [];
      debugPrint('搜索城市发生错误: $e');
      // 重新抛出异常以便外部处理
      throw e;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
    
    return _searchResults;
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