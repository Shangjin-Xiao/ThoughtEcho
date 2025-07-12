import 'dart:io';
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
        try {
          final result = await _channel.invokeMethod('selectVideoFile', {
            'extensions': ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
            'allowMultiple': false,
          }).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              logDebug('原生文件选择超时');
              return null;
            },
          );

          if (result != null && result is String) {
            logDebug('原生选择视频文件成功: $result');
            // 立即验证文件是否存在
            final file = File(result);
            if (await file.exists()) {
              final fileSize = await file.length();
              logDebug('文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
              return XFile(result);
            } else {
              logDebug('原生选择的文件不存在: $result');
              throw Exception('选择的文件不存在');
            }
          }
        } catch (e) {
          logDebug('原生文件选择失败，回退到标准方法: $e');
        }
      }

      // 回退到标准file_selector
      logDebug('使用标准file_selector选择视频文件');
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'videos',
        extensions: <String>['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
      );

      final result = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      if (result != null) {
        logDebug('标准文件选择成功: ${result.path}');
      }
      return result;
    } catch (e) {
      logDebug('视频文件选择失败: $e');
      return null;
    }
  }
  
  /// 选择图片文件（流式处理）
  static Future<XFile?> selectImageFile() async {
    try {
      logDebug('开始流式选择图片文件...');

      // 首先尝试使用我们的原生实现
      if (await isNativeFileSelectorAvailable()) {
        try {
          final result = await _channel.invokeMethod('selectImageFile', {
            'extensions': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
            'allowMultiple': false,
          }).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              logDebug('原生图片选择超时');
              return null;
            },
          );

          if (result != null && result is String) {
            logDebug('原生选择图片文件成功: $result');
            // 立即验证文件是否存在
            final file = File(result);
            if (await file.exists()) {
              final fileSize = await file.length();
              logDebug('图片文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
              return XFile(result);
            } else {
              logDebug('原生选择的图片文件不存在: $result');
              throw Exception('选择的图片文件不存在');
            }
          }
        } catch (e) {
          logDebug('原生图片选择失败，回退到标准方法: $e');
        }
      }

      // 回退到标准file_selector
      logDebug('使用标准file_selector选择图片文件');
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'images',
        extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
      );

      final result = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      if (result != null) {
        logDebug('标准图片选择成功: ${result.path}');
      }
      return result;
    } catch (e) {
      logDebug('图片文件选择失败: $e');
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
        try {
          final result = await _channel.invokeMethod('selectFile', {
            'extensions': extensions ?? [],
            'description': description ?? 'All Files',
            'allowMultiple': false,
          }).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              logDebug('原生文件选择超时');
              return null;
            },
          );

          if (result != null && result is String) {
            logDebug('原生选择文件成功: $result');
            // 立即验证文件是否存在
            final file = File(result);
            if (await file.exists()) {
              final fileSize = await file.length();
              logDebug('文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
              return XFile(result);
            } else {
              logDebug('原生选择的文件不存在: $result');
              throw Exception('选择的文件不存在');
            }
          }
        } catch (e) {
          logDebug('原生文件选择失败，回退到标准方法: $e');
        }
      }

      // 回退到标准file_selector
      logDebug('使用标准file_selector选择文件');
      final typeGroups = <XTypeGroup>[];
      if (extensions != null && extensions.isNotEmpty) {
        typeGroups.add(XTypeGroup(
          label: description ?? 'Files',
          extensions: extensions,
        ));
      } else {
        typeGroups.add(const XTypeGroup(label: 'All Files'));
      }

      final result = await openFile(acceptedTypeGroups: typeGroups);
      if (result != null) {
        logDebug('标准文件选择成功: ${result.path}');
      }
      return result;
    } catch (e) {
      logDebug('文件选择失败: $e');
      return null;
    }
  }
  
  /// 检查原生文件选择器是否可用
  static Future<bool> isNativeFileSelectorAvailable() async {
    try {
      // 添加超时机制，避免长时间等待
      final result = await _channel.invokeMethod('isAvailable').timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          logDebug('原生文件选择器检查超时');
          return false;
        },
      );
      return result == true;
    } catch (e) {
      logDebug('检查原生文件选择器可用性失败: $e');
      return false;
    }
  }
}