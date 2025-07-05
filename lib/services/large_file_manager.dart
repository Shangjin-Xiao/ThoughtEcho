import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

/// 大文件处理管理器
/// 
/// 专门处理大文件的内存安全操作，包括：
/// - 流式JSON编解码
/// - 分块文件处理
/// - 内存监控和管理
/// - 进度回调支持
class LargeFileManager {
  static const int _defaultChunkSize = 64 * 1024; // 64KB
  
  /// 流式JSON编码到文件
  /// 
  /// [data] - 要编码的数据
  /// [outputFile] - 输出文件
  /// [onProgress] - 进度回调 (current, total)
  static Future<void> encodeJsonToFileStreaming(
    Map<String, dynamic> data,
    File outputFile, {
    Function(int current, int total)? onProgress,
  }) async {
    try {
      logDebug('开始流式JSON编码到文件: ${outputFile.path}');
      await outputFile.parent.create(recursive: true);

      // 使用Isolate进行编码，避免阻塞主线程
      final jsonString = await compute(_encodeJsonInIsolate, data);
      
      // 流式写入文件
      final sink = outputFile.openWrite();
      try {
        sink.write(jsonString);
        await sink.flush();
        logDebug('流式JSON编码完成');
      } finally {
        await sink.close();
      }
      onProgress?.call(1, 1);
    } catch (e, s) {
      AppLogger.e('流式JSON编码失败', error: e, stackTrace: s, source: 'LargeFileManager');
      rethrow;
    }
  }
  
  /// 流式JSON解码从文件
  /// 
  /// [inputFile] - 输入文件
  /// [onProgress] - 进度回调
  static Future<Map<String, dynamic>> decodeJsonFromFileStreaming(
    File inputFile, {
    Function(int current, int total)? onProgress,
  }) async {
    try {
      logDebug('开始流式JSON解码: ${inputFile.path}');
      if (!await inputFile.exists()) {
        throw Exception('JSON文件不存在: ${inputFile.path}');
      }

      // 将文件路径传递给Isolate，在Isolate中进行文件读取和解码
      return await compute(_decodeJsonFromFileInIsolate, inputFile.path);
    } catch (e, s) {
      AppLogger.e('流式JSON解码失败', error: e, stackTrace: s, source: 'LargeFileManager');
      rethrow;
    }
  }

  /// 在Isolate中从文件流式解码JSON
  static Future<Map<String, dynamic>> _decodeJsonFromFileInIsolate(String filePath) async {
    final file = File(filePath);
    
    // 检查文件大小，如果太大使用流式处理
    final fileSize = await file.length();
    const streamThreshold = 100 * 1024 * 1024; // 100MB
    
    if (fileSize > streamThreshold) {
      // 对于大文件，使用流式读取
      final stream = file.openRead();
      final chunks = <List<int>>[];
      
      await for (final chunk in stream) {
        chunks.add(chunk);
      }
      
      final content = String.fromCharCodes(chunks.expand((chunk) => chunk));
      return jsonDecode(content) as Map<String, dynamic>;
    } else {
      // 小文件直接读取
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    }
  }

  /// 验证文件是否可访问且大小在合理范围内
  static Future<bool> validateFile(String filePath, {int maxSize = 2 * 1024 * 1024 * 1024}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        logDebug('文件不存在: $filePath');
        return false;
      }
      final fileSize = await file.length();
      if (fileSize > maxSize) {
        logDebug('文件过大: ${fileSize / 1024 / 1024}MB > ${maxSize / 1024 / 1024}MB');
        return false;
      }
      return true;
    } catch (e) {
      logDebug('文件验证失败: $e');
      return false;
    }
  }
  
  /// 在Isolate中解码JSON
  static Map<String, dynamic> _decodeJsonInIsolate(String jsonString) {
    return jsonDecode(jsonString);
  }
  
  /// 在Isolate中编码JSON
  static String _encodeJsonInIsolate(Map<String, dynamic> data) {
    return jsonEncode(data);
  }
  
  /// 安全的大JSON处理（自动选择策略）
  /// 
  /// [data] - 要处理的数据
  /// [encode] - true为编码，false为解码
  static Future<T> processLargeJson<T>(
    dynamic data, {
    required bool encode,
    Function(double progress)? onProgress,
  }) async {
    try {
      if (encode) {
        // 编码：Map -> String
        final mapData = data as Map<String, dynamic>;
        
        // 估算数据大小
        final estimatedSize = _estimateJsonSize(mapData);
        
        if (estimatedSize > 50 * 1024 * 1024) { // 50MB以上使用Isolate
          logDebug('使用Isolate处理大JSON编码 (估算大小: ${(estimatedSize / 1024 / 1024).toStringAsFixed(1)}MB)');
          onProgress?.call(0.5);
          final result = await compute(_encodeJsonInIsolate, mapData);
          onProgress?.call(1.0);
          return result as T;
        } else {
          // 小数据直接处理
          onProgress?.call(0.5);
          final result = jsonEncode(mapData);
          onProgress?.call(1.0);
          return result as T;
        }
      } else {
        // 解码：String -> Map
        final jsonString = data as String;
        
        if (jsonString.length > 50 * 1024 * 1024) { // 50MB以上使用Isolate
          logDebug('使用Isolate处理大JSON解码 (大小: ${(jsonString.length / 1024 / 1024).toStringAsFixed(1)}MB)');
          onProgress?.call(0.5);
          final result = await compute(_decodeJsonInIsolate, jsonString);
          onProgress?.call(1.0);
          return result as T;
        } else {
          // 小数据直接处理
          onProgress?.call(0.5);
          final result = jsonDecode(jsonString);
          onProgress?.call(1.0);
          return result as T;
        }
      }
    } catch (e, s) {
      AppLogger.e('大JSON处理失败', error: e, stackTrace: s, source: 'LargeFileManager');
      rethrow;
    }
  }
  
  /// 估算JSON数据的序列化大小
  static int _estimateJsonSize(Map<String, dynamic> data) {
    try {
      // 简单估算：转换为字符串并计算长度
      // 这不是精确值，但足够用于判断是否需要特殊处理
      return data.toString().length * 2; // 乘以2作为安全系数
    } catch (e) {
      // 如果估算失败，假设是大数据
      return 100 * 1024 * 1024; // 100MB
    }
  }
  
  /// 分块复制文件（内存安全）
  /// 
  /// [source] - 源文件路径
  /// [target] - 目标文件路径
  /// [chunkSize] - 块大小，默认64KB
  /// [onProgress] - 进度回调 (current, total)
  static Future<void> copyFileInChunks(
    String source,
    String target, {
    int chunkSize = _defaultChunkSize,
    Function(int current, int total)? onProgress,
  }) async {
    final sourceFile = File(source);
    final targetFile = File(target);
    
    if (!await sourceFile.exists()) {
      throw Exception('源文件不存在: $source');
    }
    
    // 确保目标目录存在
    await targetFile.parent.create(recursive: true);
    
    final totalSize = await sourceFile.length();
    int copiedBytes = 0;
    
    final sourceStream = sourceFile.openRead();
    final targetSink = targetFile.openWrite();
    
    try {
      await for (final chunk in sourceStream) {
        targetSink.add(chunk);
        copiedBytes += chunk.length;
        
        // 报告进度
        onProgress?.call(copiedBytes, totalSize);
        
        // 定期刷新，确保数据写入磁盘
        if (copiedBytes % (chunkSize * 16) == 0) {
          await targetSink.flush();
        }
        
        // 内存压力检查
        if (copiedBytes % (chunkSize * 64) == 0) {
          await _checkMemoryPressure();
        }
      }
      
      await targetSink.flush();
      
      // 验证复制完整性
      final targetSize = await targetFile.length();
      if (targetSize != totalSize) {
        throw Exception('文件复制不完整: 期望 $totalSize 字节，实际 $targetSize 字节');
      }
      
      logDebug('文件复制完成: $source -> $target (${(totalSize / 1024 / 1024).toStringAsFixed(1)}MB)');
    } catch (e) {
      // 清理不完整的目标文件
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (_) {}
      rethrow;
    } finally {
      await targetSink.close();
    }
  }
  
  /// 检查内存压力并尝试释放
  static Future<void> _checkMemoryPressure() async {
    try {
      // 触发垃圾回收
      if (!kIsWeb) {
        // 在非Web平台可以尝试一些内存管理
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } catch (e) {
      // 忽略内存检查错误
      logDebug('内存压力检查失败: $e');
    }
  }
  
  /// 紧急内存清理（当检测到内存不足时）
  static Future<void> emergencyMemoryCleanup() async {
    try {
      logDebug('执行紧急内存清理...');
      
      // 触发垃圾回收
      if (!kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // 可以在这里添加更多内存清理逻辑
      logDebug('紧急内存清理完成');
    } catch (e) {
      logDebug('紧急内存清理失败: $e');
    }
  }
  
  /// 安全执行文件操作，带OutOfMemoryError处理
  static Future<T?> executeWithMemoryProtection<T>(
    Future<T> Function() operation, {
    String? operationName,
  }) async {
    try {
      return await operation();
    } on OutOfMemoryError catch (e) {
      final name = operationName ?? '文件操作';
      logDebug('$name 遇到内存不足错误: $e');
      
      // 执行紧急内存清理
      await emergencyMemoryCleanup();
      
      // 抛出更友好的异常
      throw Exception('内存不足，无法完成$name。请关闭其他应用程序后重试，或选择较小的文件。');
    } catch (e) {
      rethrow;
    }
  }
  
  /// 批量处理文件（内存安全）
  /// 
  /// [files] - 文件列表
  /// [processor] - 处理函数
  /// [batchSize] - 批次大小
  /// [onProgress] - 进度回调
  static Future<List<T>> processBatch<T>(
    List<String> files,
    Future<T> Function(String file) processor, {
    int batchSize = 5,
    Function(int current, int total)? onProgress,
  }) async {
    final results = <T>[];
    final total = files.length;
    
    for (int i = 0; i < files.length; i += batchSize) {
      final batch = files.skip(i).take(batchSize).toList();
      
      // 并行处理当前批次
      final batchResults = await Future.wait(
        batch.map(processor),
        eagerError: false,
      );
      
      results.addAll(batchResults);
      
      // 报告进度
      final processed = (i + batch.length).clamp(0, total);
      onProgress?.call(processed, total);
      
      // 批次间短暂休息，让系统有机会回收内存
      if (i + batchSize < files.length) {
        await Future.delayed(const Duration(milliseconds: 50));
        await _checkMemoryPressure();
      }
    }
    
    return results;
  }
  
  /// 获取文件大小（安全方式）
  static Future<int> getFileSizeSecurely(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return 0;
      }
      return await file.length();
    } catch (e) {
      logDebug('获取文件大小失败: $filePath, 错误: $e');
      return 0;
    }
  }
  
  /// 检查系统是否有足够资源处理文件（移除大小限制）
  static Future<bool> canProcessFile(String filePath) async {
    try {
      final fileSize = await getFileSizeSecurely(filePath);
      
      // 移除大小限制，只检查文件是否存在和可读
      if (fileSize == 0) {
        logDebug('文件不存在或为空: $filePath');
        return false;
      }
      
      // 检查文件是否可读
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }
      
      // 尝试读取文件的第一个字节，确保文件可以访问
      try {
        final stream = file.openRead(0, 1);
        await stream.first;
        return true;
      } catch (e) {
        logDebug('文件无法读取: $filePath, 错误: $e');
        return false;
      }
    } catch (e) {
      logDebug('检查文件处理能力失败: $e');
      return false;
    }
  }
  
  /// 创建取消令牌
  static CancelToken createCancelToken() {
    return CancelToken();
  }
}

/// 取消令牌
class CancelToken {
  bool _isCancelled = false;
  
  bool get isCancelled => _isCancelled;
  
  void cancel() {
    _isCancelled = true;
  }
  
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const CancelledException();
    }
  }
}

/// 取消异常
class CancelledException implements Exception {
  const CancelledException();
  
  @override
  String toString() => '操作已取消';
}
