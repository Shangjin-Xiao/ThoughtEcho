import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'app_logger.dart';

/// 流式文件选择器
/// 
/// 解决file_selector插件在处理大文件时的OOM问题
/// 通过流式处理和路径传递避免将整个文件加载到内存
class StreamFileSelector {
  static const MethodChannel _channel = MethodChannel('thoughtecho/file_selector');
  
  /// 选择视频文件（流式处理）
  static Future<XFile?> selectVideoFile() async {
    try {
      logDebug('开始流式选择视频文件...');
      
      // 首先尝试使用我们的原生实现
      if (await isNativeFileSelectorAvailable()) {
        final result = await _channel.invokeMethod('selectVideoFile', {
          'extensions': ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
          'allowMultiple': false,
        });
        
        if (result != null && result is String) {
          logDebug('原生选择文件成功: $result');
          return XFile(result);
        }
      }
      
      // 回退到标准file_selector，但只用于小文件
      logDebug('回退到标准file_selector');
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'videos',
        extensions: <String>['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
      );

      return await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    } catch (e) {
      logDebug('流式文件选择失败: $e');
      return null;
    }
  }
  
  /// 选择图片文件（流式处理）
  static Future<XFile?> selectImageFile() async {
    try {
      logDebug('开始流式选择图片文件...');
      
      // 首先尝试使用我们的原生实现
      if (await isNativeFileSelectorAvailable()) {
        final result = await _channel.invokeMethod('selectImageFile', {
          'extensions': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
          'allowMultiple': false,
        });
        
        if (result != null && result is String) {
          logDebug('原生选择图片成功: $result');
          return XFile(result);
        }
      }
      
      // 回退到标准file_selector
      logDebug('回退到标准file_selector');
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'images',
        extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
      );

      return await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    } catch (e) {
      logDebug('流式图片选择失败: $e');
      return null;
    }
  }
  
  /// 选择任意文件（流式处理）
  static Future<XFile?> selectFile({
    List<String>? extensions,
    String? description,
  }) async {
    try {
      logDebug('开始流式选择文件...');
      
      // 首先尝试使用我们的原生实现
      if (await isNativeFileSelectorAvailable()) {
        final result = await _channel.invokeMethod('selectFile', {
          'extensions': extensions ?? [],
          'description': description ?? 'All Files',
          'allowMultiple': false,
        });
        
        if (result != null && result is String) {
          logDebug('原生选择文件成功: $result');
          return XFile(result);
        }
      }
      
      // 回退到标准file_selector
      logDebug('回退到标准file_selector');
      final typeGroups = <XTypeGroup>[];
      if (extensions != null && extensions.isNotEmpty) {
        typeGroups.add(XTypeGroup(
          label: description ?? 'Files',
          extensions: extensions,
        ));
      } else {
        typeGroups.add(const XTypeGroup(label: 'All Files'));
      }

      return await openFile(acceptedTypeGroups: typeGroups);
    } catch (e) {
      logDebug('流式文件选择失败: $e');
      return null;
    }
  }
  
  /// 检查原生文件选择器是否可用
  static Future<bool> isNativeFileSelectorAvailable() async {
    try {
      final result = await _channel.invokeMethod('isAvailable');
      return result == true;
    } catch (e) {
      logDebug('检查原生文件选择器可用性失败: $e');
      return false;
    }
  }
}