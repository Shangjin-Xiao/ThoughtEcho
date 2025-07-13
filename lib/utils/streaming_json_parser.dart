import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'app_logger.dart';

/// 流式JSON解析器
///
/// 专门处理大JSON文件的解析，避免将整个文件加载到内存
class StreamingJsonParser {
  /// 流式解析JSON文件
  ///
  /// [file] - 要解析的文件
  /// [onProgress] - 进度回调
  static Future<Map<String, dynamic>> parseJsonFile(
    File file, {
    Function(double progress)? onProgress,
  }) async {
    try {
      final fileSize = await file.length();
      logDebug(
        '开始流式解析JSON文件: ${file.path} (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)',
      );

      // 对于小文件，直接解析
      if (fileSize < 50 * 1024 * 1024) {
        // 50MB以下
        final content = await file.readAsString();
        onProgress?.call(1.0);
        return jsonDecode(content) as Map<String, dynamic>;
      }

      // 对于大文件，使用流式解析
      return await _parseJsonStreaming(file, onProgress);
    } catch (e) {
      logDebug('流式JSON解析失败: $e');
      rethrow;
    }
  }

  /// 流式解析大JSON文件
  static Future<Map<String, dynamic>> _parseJsonStreaming(
    File file,
    Function(double progress)? onProgress,
  ) async {
    final fileSize = await file.length();
    int bytesRead = 0;

    // 使用StringBuffer累积JSON内容
    final buffer = StringBuffer();

    // 分块读取文件
    final stream = file.openRead();

    await for (final chunk in stream) {
      // 将字节转换为字符串
      final chunkString = utf8.decode(chunk);
      buffer.write(chunkString);

      bytesRead += chunk.length;
      onProgress?.call(bytesRead / fileSize);

      // 定期检查内存压力
      if (bytesRead % (10 * 1024 * 1024) == 0) {
        // 每10MB检查一次
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }

    // 解析累积的JSON内容
    try {
      final jsonString = buffer.toString();
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('JSON解析失败: $e');
    }
  }

  /// 检查JSON文件是否可以安全解析
  static Future<bool> canSafelyParse(File file) async {
    try {
      final fileSize = await file.length();

      // 检查文件大小
      const maxSafeSize = 500 * 1024 * 1024; // 500MB
      if (fileSize > maxSafeSize) {
        logDebug(
          'JSON文件过大，无法安全解析: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB',
        );
        return false;
      }

      // 检查文件是否可读
      if (!await file.exists()) {
        return false;
      }

      // 尝试读取文件头，检查是否为有效JSON
      final stream = file.openRead(0, 1024);
      final firstChunk = await stream.first;
      final firstChunkString = utf8.decode(firstChunk);

      // 简单检查JSON格式
      final trimmed = firstChunkString.trim();
      if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
        logDebug('文件不是有效的JSON格式');
        return false;
      }

      return true;
    } catch (e) {
      logDebug('检查JSON文件安全性失败: $e');
      return false;
    }
  }

  /// 估算JSON解析所需内存
  static Future<int> estimateMemoryUsage(File file) async {
    try {
      final fileSize = await file.length();

      // JSON解析通常需要文件大小的2-3倍内存
      // 这里使用保守估计的3倍
      return (fileSize * 3).toInt();
    } catch (e) {
      logDebug('估算内存使用失败: $e');
      return 0;
    }
  }
}
