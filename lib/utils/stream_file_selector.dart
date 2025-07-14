import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as desktop_selector;
import 'app_logger.dart';

/// 流式文件选择器 - 彻底修复版
///
/// 解决大文件OOM问题的核心策略：
/// 1. 移动端使用file_picker，设置withData: false避免读取文件内容
/// 2. 桌面端使用file_selector（更稳定）
/// 3. 只传递文件路径，不传递文件内容
/// 4. 真正的流式处理
class StreamFileSelector {
  static const MethodChannel _channel = MethodChannel(
    'thoughtecho/file_selector',
  );

  // 控制是否启用原生选择器的标志
  static bool _useNativeSelector = false;

  /// 选择视频文件（优化版）
  static Future<FilePickerResult?> selectVideoFile() async {
    try {
      logDebug('开始选择视频文件...');

      FilePickerResult? result;

      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS) {
        // 桌面端使用 file_selector
        const typeGroup = desktop_selector.XTypeGroup(
          label: 'videos',
          extensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
        );

        final file = await desktop_selector.openFile(
          acceptedTypeGroups: [typeGroup],
        );

        if (file != null) {
          // 创建兼容的 FilePickerResult
          result = FilePickerResult([
            PlatformFile(
              name: file.name,
              path: file.path,
              size: await File(file.path).length(),
            ),
          ]);
        }
      } else {
        // 移动端使用 file_picker，关键是设置 withData: false
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
          allowMultiple: false,
          withData: false, // 关键：不读取文件内容，只返回路径
          withReadStream: false, // 关键：不创建读取流
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        logDebug('视频文件选择成功: ${file.path}');

        // 验证文件并记录大小
        if (file.path != null) {
          try {
            final fileObj = File(file.path!);
            if (await fileObj.exists()) {
              final fileSize = await fileObj.length();
              logDebug(
                '文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
              );

              // 对于超大文件，给出警告但不阻止
              if (fileSize > 500 * 1024 * 1024) {
                // 500MB
                logDebug('警告：检测到超大文件，将使用流式处理');
              }
            }
          } catch (e) {
            logDebug('文件验证失败，但继续处理: $e');
          }
        }
      }

      return result;
    } catch (e) {
      logDebug('视频文件选择失败: $e');
      return null;
    }
  }

  /// 选择图片文件（优化版）
  static Future<FilePickerResult?> selectImageFile() async {
    try {
      logDebug('开始选择图片文件...');

      FilePickerResult? result;

      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS) {
        // 桌面端使用 file_selector
        const typeGroup = desktop_selector.XTypeGroup(
          label: 'images',
          extensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
        );

        final file = await desktop_selector.openFile(
          acceptedTypeGroups: [typeGroup],
        );

        if (file != null) {
          // 创建兼容的 FilePickerResult
          result = FilePickerResult([
            PlatformFile(
              name: file.name,
              path: file.path,
              size: await File(file.path).length(),
            ),
          ]);
        }
      } else {
        // 移动端使用 file_picker，关键是设置 withData: false
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
          allowMultiple: false,
          withData: false, // 关键：不读取文件内容，只返回路径
          withReadStream: false, // 关键：不创建读取流
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        logDebug('图片文件选择成功: ${file.path}');

        // 验证文件并记录大小
        if (file.path != null) {
          try {
            final fileObj = File(file.path!);
            if (await fileObj.exists()) {
              final fileSize = await fileObj.length();
              logDebug(
                '图片文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
              );

              // 对于超大图片文件，给出警告
              if (fileSize > 50 * 1024 * 1024) {
                // 50MB
                logDebug('警告：检测到超大图片文件，将使用流式处理');
              }
            }
          } catch (e) {
            logDebug('图片文件验证失败，但继续处理: $e');
          }
        }
      }

      return result;
    } catch (e) {
      logDebug('图片文件选择失败: $e');
      return null;
    }
  }

  /// 选择任意文件（优化版）
  static Future<FilePickerResult?> selectFile({
    List<String>? extensions,
    String? description,
  }) async {
    try {
      logDebug('开始选择文件...');

      FilePickerResult? result;

      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS) {
        // 桌面端使用 file_selector
        final typeGroups = <desktop_selector.XTypeGroup>[];
        if (extensions != null && extensions.isNotEmpty) {
          typeGroups.add(
            desktop_selector.XTypeGroup(
              label: description ?? 'Files',
              extensions: extensions,
            ),
          );
        } else {
          typeGroups.add(
            const desktop_selector.XTypeGroup(label: 'All Files'),
          );
        }

        final file = await desktop_selector.openFile(
          acceptedTypeGroups: typeGroups,
        );

        if (file != null) {
          // 创建兼容的 FilePickerResult
          result = FilePickerResult([
            PlatformFile(
              name: file.name,
              path: file.path,
              size: await File(file.path).length(),
            ),
          ]);
        }
      } else {
        // 移动端使用 file_picker，关键是设置 withData: false
        if (extensions != null && extensions.isNotEmpty) {
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: extensions,
            allowMultiple: false,
            withData: false, // 关键：不读取文件内容，只返回路径
            withReadStream: false, // 关键：不创建读取流
          );
        } else {
          result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: false,
            withData: false, // 关键：不读取文件内容，只返回路径
            withReadStream: false, // 关键：不创建读取流
          );
        }
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        logDebug('文件选择成功: ${file.path}');

        // 验证文件并记录大小
        if (file.path != null) {
          try {
            final fileObj = File(file.path!);
            if (await fileObj.exists()) {
              final fileSize = await fileObj.length();
              logDebug(
                '文件验证成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB',
              );

              // 对于超大文件，给出警告
              if (fileSize > 100 * 1024 * 1024) {
                // 100MB
                logDebug('警告：检测到超大文件，将使用流式处理');
              }
            }
          } catch (e) {
            logDebug('文件验证失败，但继续处理: $e');
          }
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
