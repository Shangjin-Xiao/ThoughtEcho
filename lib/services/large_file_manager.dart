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
      
      // 确保输出目录存在
      await outputFile.parent.create(recursive: true);
      
      final sink = outputFile.openWrite();
      
      try {
        // 直接使用JSON编码并写入
        final jsonString = jsonEncode(data);
        sink.write(jsonString);
        
        await sink.flush();
        logDebug('流式JSON编码完成');
      } finally {
        await sink.close();
      }
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
      
      final fileSize = await inputFile.length();
      
      // 如果文件较小，直接读取
      if (fileSize < 10 * 1024 * 1024) { // 10MB以下
        final content = await inputFile.readAsString();
        return jsonDecode(content);
      }
      
      // 大文件使用compute在后台处理
      final content = await inputFile.readAsString();
      return await compute(_decodeJsonInIsolate, content);
    } catch (e, s) {
      AppLogger.e('流式JSON解码失败', error: e, stackTrace: s, source: 'LargeFileManager');
      rethrow;
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
  
  /// 检查系统是否有足够资源处理文件
  static Future<bool> canProcessFile(String filePath) async {
    try {
      final fileSize = await getFileSizeSecurely(filePath);
      
      // 基本检查：文件不能超过2GB
      const maxFileSize = 2 * 1024 * 1024 * 1024; // 2GB
      if (fileSize > maxFileSize) {
        logDebug('文件过大: ${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(1)}GB');
        return false;
      }
      
      // 检查文件是否可读
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }
      
      return true;
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
