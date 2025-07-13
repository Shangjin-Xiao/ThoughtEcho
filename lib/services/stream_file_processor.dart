import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import '../utils/device_memory_manager.dart';

/// 流式文件处理器
/// 
/// 使用真正的流式处理替代分块读取，避免在内存中保存大量数据
/// 支持内存压力监控和自适应处理策略
class StreamFileProcessor {
  static const int _minChunkSize = 4 * 1024; // 4KB 最小块大小
  static const int _maxChunkSize = 1024 * 1024; // 1MB 最大块大小
  static const int _defaultChunkSize = 64 * 1024; // 64KB 默认块大小
  
  final DeviceMemoryManager _memoryManager = DeviceMemoryManager();
  
  /// 流式复制文件
  /// 
  /// [source] - 源文件路径
  /// [target] - 目标文件路径
  /// [onProgress] - 进度回调 (current, total)
  /// [onMemoryPressure] - 内存压力回调 (pressureLevel)
  /// [cancelToken] - 取消令牌
  Future<void> streamCopyFile(
    String source,
    String target, {
    Function(int current, int total)? onProgress,
    Function(int pressureLevel)? onMemoryPressure,
    StreamCancelToken? cancelToken,
  }) async {
    final sourceFile = File(source);
    final targetFile = File(target);
    
    if (!await sourceFile.exists()) {
      throw FileSystemException('源文件不存在', source);
    }
    
    // 确保目标目录存在
    await targetFile.parent.create(recursive: true);
    
    final totalSize = await sourceFile.length();
    int copiedBytes = 0;
    
    // 根据文件大小和内存状态确定初始块大小
    int chunkSize = await _calculateOptimalChunkSize(totalSize);
    
    RandomAccessFile? reader;
    IOSink? writer;
    
    try {
      reader = await sourceFile.open(mode: FileMode.read);
      writer = targetFile.openWrite();
      
      while (copiedBytes < totalSize) {
        // 检查取消状态
        cancelToken?.throwIfCancelled();
        
        // 检查内存压力并调整块大小
        final pressureLevel = await _memoryManager.getMemoryPressureLevel();
        if (pressureLevel > 1) {
          chunkSize = await _adjustChunkSizeForPressure(chunkSize, pressureLevel);
          onMemoryPressure?.call(pressureLevel);
        }
        
        // 计算本次读取的大小
        final remainingBytes = totalSize - copiedBytes;
        final currentChunkSize = remainingBytes < chunkSize ? remainingBytes : chunkSize;
        
        // 流式读取数据
        final chunk = await reader.read(currentChunkSize);
        if (chunk.isEmpty) {
          break; // 文件结束
        }
        
        // 流式写入数据
        writer.add(chunk);
        
        copiedBytes += chunk.length;
        
        // 报告进度
        onProgress?.call(copiedBytes, totalSize);
        
        // 在高内存压力下，每次写入后都刷新缓冲区
        if (pressureLevel >= 2) {
          await writer.flush();
          
          // 给系统一些时间进行垃圾回收
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
      
      // 确保所有数据都写入磁盘
      await writer.flush();
      
    } finally {
      // 清理资源
      await reader?.close();
      await writer?.close();
    }
  }
  
  /// 流式处理大文件（通用处理器）
  /// 
  /// [filePath] - 文件路径
  /// [processor] - 数据处理函数
  /// [onProgress] - 进度回调
  /// [cancelToken] - 取消令牌
  Future<T> streamProcessFile<T>(
    String filePath,
    Future<T> Function(Stream<Uint8List> dataStream, int totalSize) processor, {
    Function(int current, int total)? onProgress,
    StreamCancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', filePath);
    }
    
    final totalSize = await file.length();
    
    // 创建数据流
    final dataStream = _createFileStream(file, totalSize, onProgress, cancelToken);
    
    // 使用处理器处理数据流
    return await processor(dataStream, totalSize);
  }
  
  /// 创建文件数据流
  Stream<Uint8List> _createFileStream(
    File file,
    int totalSize,
    Function(int current, int total)? onProgress,
    StreamCancelToken? cancelToken,
  ) async* {
    RandomAccessFile? reader;
    int readBytes = 0;
    
    try {
      reader = await file.open(mode: FileMode.read);
      int chunkSize = await _calculateOptimalChunkSize(totalSize);
      
      while (readBytes < totalSize) {
        // 检查取消状态
        cancelToken?.throwIfCancelled();
        
        // 动态调整块大小
        final pressureLevel = await _memoryManager.getMemoryPressureLevel();
        if (pressureLevel > 1) {
          chunkSize = await _adjustChunkSizeForPressure(chunkSize, pressureLevel);
        }
        
        // 计算本次读取大小
        final remainingBytes = totalSize - readBytes;
        final currentChunkSize = remainingBytes < chunkSize ? remainingBytes : chunkSize;
        
        // 读取数据块
        final chunk = await reader.read(currentChunkSize);
        if (chunk.isEmpty) {
          break;
        }
        
        readBytes += chunk.length;
        
        // 报告进度
        onProgress?.call(readBytes, totalSize);
        
        // 产出数据块
        yield Uint8List.fromList(chunk);
        
        // 在高内存压力下暂停一下
        if (pressureLevel >= 2) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }
    } finally {
      await reader?.close();
    }
  }
  
  /// 计算最优块大小
  Future<int> _calculateOptimalChunkSize(int fileSize) async {
    try {
      final memoryPressure = await _memoryManager.getMemoryPressureLevel();
      final availableMemory = await _memoryManager.getAvailableMemory();
      
      // 基础块大小计算
      int baseChunkSize = _defaultChunkSize;
      
      // 根据内存压力调整
      switch (memoryPressure) {
        case 0: // 正常
          baseChunkSize = _defaultChunkSize;
          break;
        case 1: // 中等压力
          baseChunkSize = _defaultChunkSize ~/ 2;
          break;
        case 2: // 高压力
          baseChunkSize = _defaultChunkSize ~/ 4;
          break;
        case 3: // 临界状态
          baseChunkSize = _minChunkSize;
          break;
      }
      
      // 根据可用内存调整
      final maxSafeChunkSize = (availableMemory * 0.01).toInt(); // 可用内存的1%
      baseChunkSize = baseChunkSize.clamp(_minChunkSize, maxSafeChunkSize);
      
      // 根据文件大小调整
      if (fileSize < 10 * 1024 * 1024) { // 小于10MB
        baseChunkSize = baseChunkSize.clamp(_minChunkSize, 128 * 1024);
      } else if (fileSize > 1024 * 1024 * 1024) { // 大于1GB
        baseChunkSize = baseChunkSize.clamp(_minChunkSize, 32 * 1024);
      }
      
      return baseChunkSize.clamp(_minChunkSize, _maxChunkSize);
    } catch (e) {
      logDebug('计算最优块大小失败: $e');
      return _minChunkSize; // 出错时使用最小块大小
    }
  }
  
  /// 根据内存压力调整块大小
  Future<int> _adjustChunkSizeForPressure(int currentChunkSize, int pressureLevel) async {
    switch (pressureLevel) {
      case 2: // 高压力
        return (currentChunkSize * 0.5).toInt().clamp(_minChunkSize, _maxChunkSize);
      case 3: // 临界状态
        return _minChunkSize;
      default:
        return currentChunkSize;
    }
  }
}

/// 流式处理取消令牌
class StreamCancelToken {
  bool _isCancelled = false;
  
  bool get isCancelled => _isCancelled;
  
  void cancel() {
    _isCancelled = true;
  }
  
  void throwIfCancelled() {
    if (_isCancelled) {
      throw StreamCancelledException('操作已取消');
    }
  }
}

/// 流式处理取消异常
class StreamCancelledException implements Exception {
  final String message;
  
  const StreamCancelledException(this.message);
  
  @override
  String toString() => 'StreamCancelledException: $message';
}
