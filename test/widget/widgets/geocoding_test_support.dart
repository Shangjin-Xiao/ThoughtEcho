// ignore_for_file: depend_on_referenced_packages

import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 位置相关 widget 测试共用的地理编码桩。
///
/// `_installAdminMockPlatform` 类的 helper 曾在两个测试文件里各存一份，
/// 改一边忘另一边就会漂移，收拢到这里统一引用。
Position mockPosition() => Position(
      longitude: 116.4074,
      latitude: 39.9042,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

/// 返回固定中文四级地址的地理编码桩，供静态本地反查走成功分支。
class AdminMockGeocodingPlatform extends GeocodingPlatform
    with MockPlatformInterfaceMixin {
  int placemarkCalls = 0;

  @override
  Future<void> setLocaleIdentifier(String localeIdentifier) async {}

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    String? localeIdentifier,
  }) async {
    placemarkCalls++;
    return [
      Placemark(
        country: '中国',
        administrativeArea: '北京市',
        locality: '北京市',
        subLocality: '西城区',
      ),
    ];
  }
}

/// 装上桩并返回之前的平台实例（可能为 null，即之前未设置）。
/// 调用方只在非 null 时恢复，避免把桩当成"之前的状态"装回去。
GeocodingPlatform? installAdminMockPlatform([
  GeocodingPlatform? mock,
]) {
  GeocodingPlatform? previous;
  try {
    previous = GeocodingPlatform.instance;
  } catch (_) {
    previous = null;
  }
  GeocodingPlatform.instance = mock ?? AdminMockGeocodingPlatform();
  return previous;
}

/// 把之前平台实例装回去；之前未设置（null）时什么都不做。
void restoreAdminMockPlatform(GeocodingPlatform? previous) {
  if (previous != null) {
    GeocodingPlatform.instance = previous;
  }
}
