import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  String? _currentAddress;
  bool _hasLocationPermission = false;
  bool _isLocationServiceEnabled = false;
  bool _isLoading = false;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get isLoading => _isLoading;

  // 地址组件
  String? _country;
  String? _province;
  String? _city;
  String? _district;

  String? get country => _country;
  String? get province => _province; 
  String? get city => _city;
  String? get district => _district;

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

  // 获取格式化的位置字符串 (国家,省/州,城市,区/县)
  String? getFormattedLocation() {
    if (_country == null || _province == null || _city == null) return null;
    
    String location = '$_country,$_province,$_city';
    if (_district != null && _district!.isNotEmpty) {
      location = '$location,$_district';
    }
    
    return location;
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