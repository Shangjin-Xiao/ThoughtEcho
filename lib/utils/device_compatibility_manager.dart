import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// 设备兼容性管理器
/// 专门处理32位设备和低端设备的兼容性问题
class DeviceCompatibilityManager {
  static final Logger _logger = Logger('DeviceCompatibilityManager');
  static DeviceCompatibilityManager? _instance;
  static DeviceCompatibilityManager get instance => _instance ??= DeviceCompatibilityManager._();
  
  DeviceCompatibilityManager._();
  
  bool? _is64BitDevice;
  bool? _isLowEndDevice;
  
  /// 检查是否为64位设备
  Future<bool> is64BitDevice() async {
    if (_is64BitDevice != null) return _is64BitDevice!;
    
    try {
      if (Platform.isAndroid) {
        // 通过MethodChannel调用原生方法检测
        const platform = MethodChannel('com.shangjin.thoughtecho/device_info');
        try {
          final result = await platform.invokeMethod('is64BitDevice');
          _is64BitDevice = result as bool? ?? false;
        } catch (e) {
          _logger.warning('无法通过MethodChannel检测设备架构，使用备用方法: $e');
          // 备用检测方法
          _is64BitDevice = await _detectArchitectureFallback();
        }
      } else {
        // iOS设备默认为64位（iOS 11+已不支持32位）
        _is64BitDevice = true;
      }
    } catch (e) {
      _logger.severe('检测设备架构时出错: $e');
      _is64BitDevice = false; // 保守起见，当作32位处理
    }
    
    _logger.info('设备架构检测结果: ${_is64BitDevice! ? '64位' : '32位'}');
    return _is64BitDevice!;
  }
  
  /// 备用架构检测方法
  Future<bool> _detectArchitectureFallback() async {
    try {
      // 通过系统信息推断
      if (Platform.isAndroid) {
        // Android 5.0+ (API 21+) 大多数设备支持64位
        // 但这只是一个粗略的估计
        return true; // 现代Android设备大多为64位
      }
      return true;
    } catch (e) {
      _logger.warning('备用架构检测失败: $e');
      return false;
    }
  }
  
  /// 检查是否为低端设备
  Future<bool> isLowEndDevice() async {
    if (_isLowEndDevice != null) return _isLowEndDevice!;
    
    try {
      // 综合判断设备性能
      final is64Bit = await is64BitDevice();
      
      // 32位设备通常性能较低
      if (!is64Bit) {
        _isLowEndDevice = true;
        _logger.info('检测到32位设备，标记为低端设备');
        return _isLowEndDevice!;
      }
      
      // 其他性能指标判断（可以根据需要扩展）
      _isLowEndDevice = false;
      
    } catch (e) {
      _logger.severe('检测设备性能时出错: $e');
      _isLowEndDevice = true; // 保守起见，当作低端设备处理
    }
    
    return _isLowEndDevice!;
  }
  
  /// 获取设备兼容性配置
  Future<DeviceCompatibilityConfig> getCompatibilityConfig() async {
    final is64Bit = await is64BitDevice();
    final isLowEnd = await isLowEndDevice();
    
    return DeviceCompatibilityConfig(
      is64BitDevice: is64Bit,
      isLowEndDevice: isLowEnd,
      enableHardwareAcceleration: is64Bit, // 64位设备启用硬件加速
      maxConcurrentOperations: isLowEnd ? 2 : 4, // 低端设备限制并发操作
      enableImageCaching: !isLowEnd, // 低端设备禁用图片缓存
      maxMemoryUsage: isLowEnd ? 128 * 1024 * 1024 : 256 * 1024 * 1024, // 内存限制
      enableAnimations: !isLowEnd, // 低端设备禁用动画
    );
  }
  
  /// 应用兼容性设置
  Future<void> applyCompatibilitySettings() async {
    try {
      final config = await getCompatibilityConfig();
      
      _logger.info('应用设备兼容性配置:');
      _logger.info('- 64位设备: ${config.is64BitDevice}');
      _logger.info('- 低端设备: ${config.isLowEndDevice}');
      _logger.info('- 硬件加速: ${config.enableHardwareAcceleration}');
      _logger.info('- 最大并发操作: ${config.maxConcurrentOperations}');
      _logger.info('- 图片缓存: ${config.enableImageCaching}');
      _logger.info('- 最大内存使用: ${config.maxMemoryUsage ~/ (1024 * 1024)}MB');
      _logger.info('- 动画效果: ${config.enableAnimations}');
      
      // 这里可以根据配置调整应用行为
      // 例如：设置图片缓存大小、调整动画效果等
      
    } catch (e) {
      _logger.severe('应用兼容性设置时出错: $e');
    }
  }
}

/// 设备兼容性配置
class DeviceCompatibilityConfig {
  final bool is64BitDevice;
  final bool isLowEndDevice;
  final bool enableHardwareAcceleration;
  final int maxConcurrentOperations;
  final bool enableImageCaching;
  final int maxMemoryUsage;
  final bool enableAnimations;
  
  const DeviceCompatibilityConfig({
    required this.is64BitDevice,
    required this.isLowEndDevice,
    required this.enableHardwareAcceleration,
    required this.maxConcurrentOperations,
    required this.enableImageCaching,
    required this.maxMemoryUsage,
    required this.enableAnimations,
  });
}
