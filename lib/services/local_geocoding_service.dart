import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geocode/geocode.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math'; // 导入数学库，用于三角函数计算

/// 本地地理编码服务类
/// 优先使用系统级SDK获取地理位置并进行反向地理编码
class LocalGeocodingService {
  // 使用默认地理编码库
  static final GeoCode _geoCode = GeoCode();
  
  // 缓存相关
  static const _geocodeCacheKey = 'geocode_cache';
  static const _cacheDuration = Duration(days: 30); // 地理编码缓存30天

  /// 获取当前位置（经纬度）
  /// [highAccuracy]: 是否使用高精度定位
  /// 返回位置对象，如果获取失败返回null
  static Future<Position?> getCurrentPosition({bool highAccuracy = false}) async {
    try {
      // 检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('位置服务未启用');
        return null;
      }

      // 检查位置权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('位置权限被拒绝');
          return null;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('位置权限被永久拒绝');
        return null;
      }

      // 根据精度要求设置参数
      final accuracy = highAccuracy ? LocationAccuracy.high : LocationAccuracy.reduced;
      final timeout = highAccuracy ? const Duration(seconds: 10) : const Duration(seconds: 5);

      // 获取位置
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout,
        forceAndroidLocationManager: !highAccuracy,
      );
      
      debugPrint('成功获取位置: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      // 如果获取当前位置失败，尝试获取最后已知位置
      try {
        debugPrint('获取当前位置失败，尝试获取最后已知位置');
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          debugPrint('成功获取最后已知位置: ${lastPosition.latitude}, ${lastPosition.longitude}');
          return lastPosition;
        }
      } catch (e) {
        debugPrint('获取最后已知位置失败: $e');
      }
      
      debugPrint('获取位置失败: $e');
      return null;
    }
  }

  /// 通过经纬度获取地址信息
  /// [latitude]: 纬度
  /// [longitude]: 经度
  /// 返回包含地址信息的Map，如果失败返回null
  static Future<Map<String, String?>?> getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      // 首先尝试从缓存读取
      final cachedAddress = await _getFromCache(latitude, longitude);
      if (cachedAddress != null) {
        debugPrint('使用缓存的地理编码数据');
        return cachedAddress;
      }
      
      // 首先尝试使用系统提供的地理编码功能
      try {
        final placemarks = await geocoding.placemarkFromCoordinates(
          latitude, 
          longitude,
          localeIdentifier: 'zh_CN', // 尝试使用中文
        );
        
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          
          // 构建地址信息，确保所有值都是字符串类型或null
          final addressInfo = <String, String?>{
            'country': place.country,
            'province': place.administrativeArea,
            'city': place.locality ?? place.subAdministrativeArea,
            'district': place.subLocality,
            'street': place.thoroughfare,
            'formatted_address': _formatAddress(place),
            'source': 'system', // 标记数据来源
          };
          
          // 缓存结果
          await _saveToCache(latitude, longitude, addressInfo);
          
          return addressInfo;
        }
      } catch (e) {
        debugPrint('系统地理编码失败，尝试使用备用方法: $e');
      }
      
      // 如果系统方法失败，使用GeoCode库
      try {
        final address = await _geoCode.reverseGeocoding(
          latitude: latitude, 
          longitude: longitude,
        );
        
        final addressInfo = <String, String?>{
          'country': address.countryName,
          'province': address.region,
          'city': address.city,
          // 将 int? 类型转换为 String?
          'district': address.streetNumber?.toString(),
          'street': address.streetAddress,
          'formatted_address': _formatAddressFromGeoCode(address),
          'source': 'geocode', // 标记数据来源
        };
        
        // 缓存结果
        await _saveToCache(latitude, longitude, addressInfo);
        
        return addressInfo;
      } catch (e) {
        debugPrint('备用地理编码也失败: $e');
      }
      
      // 所有方法都失败，尝试使用本地数据库估算
      final estimatedAddress = _estimateAddressFromCoordinates(latitude, longitude);
      if (estimatedAddress != null) {
        // 不缓存估算的结果，因为它不够精确
        return estimatedAddress;
      }
      
      return null;
    } catch (e) {
      debugPrint('获取地址信息失败: $e');
      return null;
    }
  }

  /// 从缓存读取地理编码数据
  static Future<Map<String, String?>?> _getFromCache(double latitude, double longitude) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_geocodeCacheKey);
      
      if (cacheJson != null) {
        final cacheData = json.decode(cacheJson) as Map<String, dynamic>;
        
        // 查找匹配项
        for (var entry in cacheData.entries) {
          final coords = entry.key.split(',');
          if (coords.length == 2) {
            final cachedLat = double.parse(coords[0]);
            final cachedLon = double.parse(coords[1]);
            
            // 如果在500米范围内视为同一位置
            if ((cachedLat - latitude).abs() < 0.005 && 
                (cachedLon - longitude).abs() < 0.005) {
              final addressData = entry.value as Map<String, dynamic>;
              final timestamp = DateTime.parse(addressData['timestamp'] as String);
              
              // 检查是否过期
              if (DateTime.now().difference(timestamp) < _cacheDuration) {
                // 转换成期望的格式，确保所有值都是String类型或null
                return {
                  'country': addressData['country'] as String?,
                  'province': addressData['province'] as String?,
                  'city': addressData['city'] as String?,
                  'district': addressData['district'] as String?,
                  'street': addressData['street'] as String?,
                  'formatted_address': addressData['formatted_address'] as String?,
                  'source': addressData['source'] as String?,
                };
              }
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('从缓存读取地理编码数据失败: $e');
      return null;
    }
  }

  /// 保存地理编码结果到缓存
  static Future<void> _saveToCache(double latitude, double longitude, Map<String, String?> addressInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> cacheData = {};
      
      // 读取现有缓存
      final cacheJson = prefs.getString(_geocodeCacheKey);
      if (cacheJson != null) {
        cacheData = json.decode(cacheJson) as Map<String, dynamic>;
      }
      
      // 添加新条目
      final key = '$latitude,$longitude';
      final dataWithTimestamp = Map<String, dynamic>.from(addressInfo)
        ..['timestamp'] = DateTime.now().toIso8601String();
      
      cacheData[key] = dataWithTimestamp;
      
      // 如果缓存太大，移除最老的条目
      if (cacheData.length > 100) {
        final sortedKeys = cacheData.keys.toList()
          ..sort((a, b) {
            final timeA = DateTime.parse((cacheData[a] as Map<String, dynamic>)['timestamp'] as String);
            final timeB = DateTime.parse((cacheData[b] as Map<String, dynamic>)['timestamp'] as String);
            return timeA.compareTo(timeB);
          });
        
        // 移除最老的20%条目
        final removeCount = (cacheData.length * 0.2).round();
        for (var i = 0; i < removeCount; i++) {
          if (i < sortedKeys.length) {
            cacheData.remove(sortedKeys[i]);
          }
        }
      }
      
      // 保存回缓存
      await prefs.setString(_geocodeCacheKey, json.encode(cacheData));
    } catch (e) {
      debugPrint('保存地理编码数据到缓存失败: $e');
    }
  }

  /// 使用系统提供的Placemark格式化地址
  static String _formatAddress(geocoding.Placemark place) {
    List<String> addressComponents = [];
    
    if (place.country != null && place.country!.isNotEmpty) {
      addressComponents.add(place.country!);
    }
    
    if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
      addressComponents.add(place.administrativeArea!);
    }
    
    if (place.locality != null && place.locality!.isNotEmpty) {
      addressComponents.add(place.locality!);
    } else if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty) {
      addressComponents.add(place.subAdministrativeArea!);
    }
    
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      addressComponents.add(place.subLocality!);
    }

    // 如果找不到详细地址，至少返回国家信息
    if (addressComponents.isEmpty && place.country != null) {
      return place.country!;
    }

    return addressComponents.join(', ');
  }

  /// 使用GeoCode库的Address格式化地址
  static String _formatAddressFromGeoCode(Address address) {
    List<String> addressComponents = [];
    
    if (address.countryName != null && address.countryName!.isNotEmpty) {
      addressComponents.add(address.countryName!);
    }
    
    if (address.region != null && address.region!.isNotEmpty) {
      addressComponents.add(address.region!);
    }
    
    if (address.city != null && address.city!.isNotEmpty) {
      addressComponents.add(address.city!);
    }
    
    return addressComponents.join(', ');
  }

  /// 基于经纬度范围估算位置
  /// 当所有在线和系统级方法都失败时使用
  static Map<String, String?>? _estimateAddressFromCoordinates(double latitude, double longitude) {
    // 中国主要城市及周边区域
    final cities = {
      // 北京
      '北京': {'lat': 39.9042, 'lon': 116.4074, 'province': '北京', 'country': '中国'},
      // 上海
      '上海': {'lat': 31.2304, 'lon': 121.4737, 'province': '上海', 'country': '中国'},
      // 广州
      '广州': {'lat': 23.1291, 'lon': 113.2644, 'province': '广东', 'country': '中国'},
      // 深圳
      '深圳': {'lat': 22.5431, 'lon': 114.0579, 'province': '广东', 'country': '中国'},
      // 成都
      '成都': {'lat': 30.5728, 'lon': 104.0668, 'province': '四川', 'country': '中国'},
      // 重庆
      '重庆': {'lat': 29.4316, 'lon': 106.9123, 'province': '重庆', 'country': '中国'},
      // 武汉
      '武汉': {'lat': 30.5928, 'lon': 114.3055, 'province': '湖北', 'country': '中国'},
      // 杭州
      '杭州': {'lat': 30.2741, 'lon': 120.1551, 'province': '浙江', 'country': '中国'},
      // 南京
      '南京': {'lat': 32.0603, 'lon': 118.7969, 'province': '江苏', 'country': '中国'},
      // 西安
      '西安': {'lat': 34.3416, 'lon': 108.9398, 'province': '陕西', 'country': '中国'},
      // 苏州
      '苏州': {'lat': 31.2990, 'lon': 120.5853, 'province': '江苏', 'country': '中国'},
      // 天津
      '天津': {'lat': 39.0851, 'lon': 117.1993, 'province': '天津', 'country': '中国'},
      // 青岛
      '青岛': {'lat': 36.0671, 'lon': 120.3826, 'province': '山东', 'country': '中国'},
      // 长沙
      '长沙': {'lat': 28.2282, 'lon': 112.9388, 'province': '湖南', 'country': '中国'},
      // 济南
      '济南': {'lat': 36.6510, 'lon': 117.1196, 'province': '山东', 'country': '中国'},
      // 沈阳
      '沈阳': {'lat': 41.8057, 'lon': 123.4315, 'province': '辽宁', 'country': '中国'},
      // 哈尔滨
      '哈尔滨': {'lat': 45.8038, 'lon': 126.5340, 'province': '黑龙江', 'country': '中国'},
    };

    // 找到最接近的城市
    String? closestCity;
    double minDistance = double.infinity;
    
    cities.forEach((city, data) {
      final cityLat = data['lat'] as double;
      final cityLon = data['lon'] as double;
      
      final distance = _calculateDistance(latitude, longitude, cityLat, cityLon);
      if (distance < minDistance) {
        minDistance = distance;
        closestCity = city;
      }
    });

    // 如果找到最接近的城市，并且距离小于200公里，返回估计地址
    if (closestCity != null && minDistance < 200) {
      final cityData = cities[closestCity]!;
      
      // 确保所有值都是String类型
      return {
        'country': cityData['country'] as String,
        'province': cityData['province'] as String,
        'city': closestCity,
        'district': null,
        'street': null,
        'formatted_address': '${cityData['country']}, ${cityData['province']}, $closestCity 附近',
      };
    } else {
      // 如果没有找到接近的城市，根据经纬度尝试确定大致所在国家和地区
      return _getGeneralLocation(latitude, longitude);
    }
  }

  /// 计算两点间的距离（公里）
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // 地球半径（公里）
    const radius = 6371.0;
    
    // 将角度转换为弧度
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    // 使用Haversine公式计算距离
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return radius * c;
  }

  /// 度数转弧度
  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  /// 基于经纬度确定大致地理位置
  static Map<String, String?>? _getGeneralLocation(double latitude, double longitude) {
    // 基于纬度简单划分区域
    String? country;
    String? region;
    
    // 极简的大陆/国家估计
    if (latitude > 22 && latitude < 50 && longitude > 75 && longitude < 135) {
      country = '中国';
      
      // 中国区域简单划分
      if (latitude > 40) {
        region = '华北/东北';
      } else if (latitude > 30) {
        region = '华中/华东';
      } else {
        region = '华南';
      }
      
      return {
        'country': country,
        'province': region,
        'city': null,
        'district': null,
        'formatted_address': '$country, $region 地区',
      };
    } else {
      // 国外区域，只能提供大致区域
      if (latitude > 0) {
        region = '北半球';
      } else {
        region = '南半球';
      }
      
      if (longitude > -30 && longitude < 60) {
        country = '欧非地区';
      } else if (longitude >= 60 && longitude < 150) {
        country = '亚洲/大洋洲';
      } else {
        country = '美洲地区';
      }
      
      return {
        'country': country,
        'province': region,
        'city': null,
        'district': null,
        'formatted_address': '$region, $country',
      };
    }
  }
}