import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'app_logger.dart';

/// 流式文件选择器 - 彻底修复版
///
/// 解决大文件OOM问题的核心策略：
/// 1. 优先使用标准file_selector（更稳定）
/// 2. 只在必要时使用原生实现
/// 3. 避免双重文件选择
/// 4. 真正的流式处理
class StreamFileSelector {
  static const MethodChannel _channel = MethodChannel(
    'thoughtecho/file_selector',
  );

  // 控制是否启用原生选择器的标志
  static bool _useNativeSelector = false;

  /// 选择视频文件（优化版）
  static Future<XFile?> selectVideoFile() async {
    try {
      logDebug('开始选择视频文件...');

      // 直接使用标准file_selector，避免双重选择
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'videos',
        extensions: <String>['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
      );

      final result = await openFile(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );

      if (result != null) {
        logDebug('视频文件选择成功: ${result.path}');

        // 验证文件并记录大小
        try {
          final file = File(result.path);
          if (await file.exists()) {
            final fileSize = await file.length();
            logDebug(
              '文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
            );

            // 对于超大文件，给出警告但不阻止
            if (fileSize > 500 * 1024 * 1024) { // 500MB
              logDebug('警告：检测到超大文件，将使用流式处理');
            }
          }
        } catch (e) {
          logDebug('文件验证失败，但继续处理: $e');
        }
      }

      return result;
    } catch (e) {
      logDebug('视频文件选择失败: $e');
      return null;
    }
  }

  /// 选择图片文件（优化版）
  static Future<XFile?> selectImageFile() async {
    try {
      logDebug('开始选择图片文件...');

      // 直接使用标准file_selector，避免双重选择
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'images',
        extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
      );

      final result = await openFile(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );

      if (result != null) {
        logDebug('图片文件选择成功: ${result.path}');

        // 验证文件并记录大小
        try {
          final file = File(result.path);
          if (await file.exists()) {
            final fileSize = await file.length();
            logDebug(
              '图片文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
            );

            // 对于超大图片文件，给出警告
            if (fileSize > 50 * 1024 * 1024) { // 50MB
              logDebug('警告：检测到超大图片文件，将使用流式处理');
            }
          }
        } catch (e) {
          logDebug('图片文件验证失败，但继续处理: $e');
        }
      }

      return result;
    } catch (e) {
      logDebug('图片文件选择失败: $e');
      return null;
    }
  }

  /// 选择任意文件（优化版）
  static Future<XFile?> selectFile({
    List<String>? extensions,
    String? description,
  }) async {
    try {
      logDebug('开始选择文件...');

      // 直接使用标准file_selector，避免双重选择
      final typeGroups = <XTypeGroup>[];
      if (extensions != null && extensions.isNotEmpty) {
        typeGroups.add(
          XTypeGroup(label: description ?? 'Files', extensions: extensions),
        );
      } else {
        typeGroups.add(const XTypeGroup(label: 'All Files'));
      }

      final result = await openFile(acceptedTypeGroups: typeGroups);

      if (result != null) {
        logDebug('文件选择成功: ${result.path}');

        // 验证文件并记录大小
        try {
          final file = File(result.path);
          if (await file.exists()) {
            final fileSize = await file.length();
            logDebug(
              '文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
            );

            // 对于超大文件，给出警告
            if (fileSize > 100 * 1024 * 1024) { // 100MB
              logDebug('警告：检测到超大文件，将使用流式处理');
            }
          }
        } catch (e) {
          logDebug('文件验证失败，但继续处理: $e');
        }
      }

      return result;
    } catch (e) {
      logDebug('文件选择失败: $e');
      return null;
    }
  }

  /// 启用原生文件选择器（仅在需要时使用）
  static void enableNativeSelector() {
    _useNativeSelector = true;
    logDebug('已启用原生文件选择器');
  }

  /// 禁用原生文件选择器
  static void disableNativeSelector() {
    _useNativeSelector = false;
    logDebug('已禁用原生文件选择器');
  }

  /// 检查原生文件选择器是否可用（保留用于调试）
  static Future<bool> isNativeFileSelectorAvailable() async {
    if (!_useNativeSelector) return false;

    try {
      final result = await _channel
          .invokeMethod('isAvailable')
          .timeout(
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
