import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geocode/geocode.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
// 导入数学库，用于三角函数计算
import '../utils/mmkv_ffi_fix.dart'; // 导入MMKV安全包装类
import '../utils/app_logger.dart'; // 导入日志工具

///import '../utils/app_logger.dart'; 本地地理编码服务类
/// 优先使用系统级SDK获取地理位置并进行反向地理编码
class LocalGeocodingService {
  // 使用默认地理编码库
  static final GeoCode _geoCode = GeoCode();

  // 串行化 setLocaleIdentifier + placemarkFromCoordinates，避免竞态
  static Future<void> _geocodingQueue = Future.value();

  static Future<T> _runSerialized<T>(Future<T> Function() task) {
    final next = _geocodingQueue.then((_) => task());
    _geocodingQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  // 缓存相关
  static const _geocodeCacheKey = 'geocode_cache';
  static const _cacheDuration = Duration(days: 30); // 地理编码缓存30天
  /// 获取当前位置（经纬度）
  /// [highAccuracy]: 是否使用高精度定位
  /// 返回位置对象，如果获取失败返回null
  static Future<Position?> getCurrentPosition({
    bool highAccuracy = false,
  }) async {
    try {
      // Windows平台使用geolocator_windows插件获取真实位置
      // 需要在Windows设置中启用位置服务：设置 > 隐私 > 位置
      // 检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logDebug('位置服务未启用');
        return null;
      }

      // 检查位置权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logDebug('位置权限被拒绝');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        logDebug('位置权限被永久拒绝');
        return null;
      }

      // 根据精度要求设置参数
      final accuracy =
          highAccuracy ? LocationAccuracy.high : LocationAccuracy.reduced;
      final timeout = highAccuracy
          ? const Duration(seconds: 10)
          : const Duration(seconds: 5);

      // 获取位置
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeout,
        ),
      );

      logDebug('成功获取位置: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      // 如果获取当前位置失败，尝试获取最后已知位置
      try {
        logDebug('获取当前位置失败，尝试获取最后已知位置');
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          logDebug(
            '成功获取最后已知位置: ${lastPosition.latitude}, ${lastPosition.longitude}',
          );
          return lastPosition;
        }
      } catch (e) {
        logDebug('获取最后已知位置失败: $e');
      }

      logDebug('获取位置失败: $e');
      return null;
    }
  }

  /// 通过经纬度获取地址信息
  /// [latitude]: 纬度
  /// [longitude]: 经度
  /// [localeCode]: 语言代码，如 'zh' 或 'en'，用于返回对应语言的地址
  /// 返回包含地址信息的Map，如果失败返回null
  static Future<Map<String, String?>?> getAddressFromCoordinates(
    double latitude,
    double longitude, {
    String? localeCode,
  }) async {
    try {
      // Windows平台：跳过系统地理编码（不支持），返回 null 让调用者使用在线服务
      if (!kIsWeb && Platform.isWindows) {
        logDebug('Windows平台：系统地理编码不支持，将使用在线服务');
        return null;
      }

      // 构建 locale identifier 用于系统地理编码
      final localeIdentifier = _buildLocaleIdentifier(localeCode);

      // 首先尝试从缓存读取（含语言匹配）
      final cachedAddress = await _getFromCache(
        latitude,
        longitude,
        localeIdentifier,
      );
      if (cachedAddress != null) {
        logDebug('使用缓存的地理编码数据');
        return cachedAddress;
      }

      // 使用系统提供的地理编码功能，通过 setLocaleIdentifier 控制返回语言
      // 串行化执行以避免全局 locale 状态的竞态条件
      try {
        final placemarks = await _runSerialized(() async {
          await geocoding.setLocaleIdentifier(localeIdentifier);
          return await geocoding.placemarkFromCoordinates(latitude, longitude);
        });

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;

          // 构建地址信息，确保所有值都是字符串类型或null
          final placeCountry = place.country?.trim();
          final placeProvince = place.administrativeArea?.trim();
          final placeLocality = place.locality?.trim();
          final placeSubAdminArea = place.subAdministrativeArea?.trim();
          final placeSubLocality = place.subLocality?.trim();
          final addressInfo = <String, String?>{
            'country': (placeCountry != null && placeCountry.isNotEmpty)
                ? placeCountry
                : null,
            'province': (placeProvince != null && placeProvince.isNotEmpty)
                ? placeProvince
                : null,
            'city': (placeLocality != null && placeLocality.isNotEmpty)
                ? placeLocality
                : ((placeSubAdminArea != null && placeSubAdminArea.isNotEmpty)
                    ? placeSubAdminArea
                    : null),
            'district':
                (placeSubLocality != null && placeSubLocality.isNotEmpty)
                    ? placeSubLocality
                    : null,
            'street': place.thoroughfare,
            'formatted_address': _formatAddress(place),
            'source': 'system', // 标记数据来源
          };

          // 缓存结果
          await _saveToCache(
            latitude,
            longitude,
            addressInfo,
            localeIdentifier,
          );

          return addressInfo;
        }
      } catch (e) {
        logDebug('系统地理编码失败，尝试使用备用方法: $e');
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
        await _saveToCache(latitude, longitude, addressInfo, localeIdentifier);

        return addressInfo;
      } catch (e) {
        logDebug('备用地理编码也失败: $e');
      }

      // 如果所有方法都失败，则返回null，不使用本地估算
      return null;
    } catch (e) {
      logDebug('获取地址信息失败: $e');
      return null;
    }
  }

  /// 从缓存读取地理编码数据（需匹配语言）
  static Future<Map<String, String?>?> _getFromCache(
    double latitude,
    double longitude,
    String localeIdentifier,
  ) async {
    try {
      // 使用MMKV
      final storage = SafeMMKV();
      await storage.initialize(); // 确保初始化
      final cacheJson = storage.getString(_geocodeCacheKey);

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

              // 检查语言是否匹配（旧缓存无 locale 字段则跳过）
              final cachedLocale = addressData['locale'] as String?;
              if (cachedLocale != null && cachedLocale != localeIdentifier) {
                continue;
              }

              final timestamp = DateTime.parse(
                addressData['timestamp'] as String,
              );

              // 检查是否过期
              if (DateTime.now().difference(timestamp) < _cacheDuration) {
                // 转换成期望的格式，确保所有值都是String类型或null
                return {
                  'country': addressData['country'] as String?,
                  'province': addressData['province'] as String?,
                  'city': addressData['city'] as String?,
                  'district': addressData['district'] as String?,
                  'street': addressData['street'] as String?,
                  'formatted_address':
                      addressData['formatted_address'] as String?,
                  'source': addressData['source'] as String?,
                };
              }
            }
          }
        }
      }

      return null;
    } catch (e) {
      logDebug('从MMKV缓存读取地理编码数据失败: $e');
      return null;
    }
  }

  /// 保存地理编码结果到缓存（含语言标识）
  static Future<void> _saveToCache(
    double latitude,
    double longitude,
    Map<String, String?> addressInfo,
    String localeIdentifier,
  ) async {
    try {
      // 使用MMKV
      final storage = SafeMMKV();
      await storage.initialize(); // 确保初始化
      Map<String, dynamic> cacheData = {};

      // 读取现有缓存
      final cacheJson = storage.getString(_geocodeCacheKey);
      if (cacheJson != null) {
        try {
          cacheData = json.decode(cacheJson) as Map<String, dynamic>;
        } catch (e) {
          logDebug('解析MMKV缓存失败，将创建新缓存: $e');
          cacheData = {}; // 解析失败则重置
        }
      }

      // 添加新条目（包含语言标识，避免切换语言后返回错误语言的缓存）
      final key = '$latitude,$longitude';
      final dataWithTimestamp = Map<String, dynamic>.from(addressInfo)
        ..['timestamp'] = DateTime.now().toIso8601String()
        ..['locale'] = localeIdentifier;

      cacheData[key] = dataWithTimestamp;

      // 如果缓存太大，移除最老的条目
      if (cacheData.length > 100) {
        final sortedKeys = cacheData.keys.toList()
          ..sort((a, b) {
            try {
              final timeA = DateTime.parse(
                (cacheData[a] as Map<String, dynamic>)['timestamp'] as String,
              );
              final timeB = DateTime.parse(
                (cacheData[b] as Map<String, dynamic>)['timestamp'] as String,
              );
              return timeA.compareTo(timeB);
            } catch (e) {
              // 处理解析时间戳可能出现的错误
              return 0;
            }
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
      await storage.setString(_geocodeCacheKey, json.encode(cacheData));
    } catch (e) {
      logDebug('保存地理编码数据到MMKV缓存失败: $e');
    }
  }

  /// 根据语言代码构建系统地理编码使用的 locale identifier
  /// 格式: languageCode_countryCode (如 'zh_CN', 'en_US', 'ja_JP')
  static String _buildLocaleIdentifier(String? localeCode) {
    final lang = (localeCode ?? '').toLowerCase().split(RegExp(r'[_-]')).first;
    switch (lang) {
      case 'zh':
        return 'zh_CN';
      case 'ja':
        return 'ja_JP';
      case 'ko':
        return 'ko_KR';
      case 'fr':
        return 'fr_FR';
      case 'en':
      default:
        return 'en_US';
    }
  }

  /// 使用系统提供的Placemark格式化地址
  static String _formatAddress(geocoding.Placemark place) {
    List<String> addressComponents = [];

    if (place.country != null && place.country!.isNotEmpty) {
      addressComponents.add(place.country!);
    }

    if (place.administrativeArea != null &&
        place.administrativeArea!.isNotEmpty) {
      addressComponents.add(place.administrativeArea!);
    }

    if (place.locality != null && place.locality!.isNotEmpty) {
      addressComponents.add(place.locality!);
    } else if (place.subAdministrativeArea != null &&
        place.subAdministrativeArea!.isNotEmpty) {
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
}
