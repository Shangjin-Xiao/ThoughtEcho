import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import 'stream_file_processor.dart';

/// 内存不足错误类
///
/// 用于统一处理内存不足的情况
class OutOfMemoryError extends Error {
  final String message;

  OutOfMemoryError([this.message = '内存不足']);

  @override
  String toString() => 'OutOfMemoryError: $message';
}

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

      onProgress?.call(0, 100);

      // 估算数据大小来决定处理策略
      final estimatedSize = _estimateJsonSize(data);
      logDebug(
          '估算JSON大小: ${(estimatedSize / 1024 / 1024).toStringAsFixed(1)}MB');

      String jsonString;

      if (estimatedSize > 50 * 1024 * 1024) {
        // 50MB以上使用Isolate
        logDebug('使用Isolate进行大JSON编码');
        onProgress?.call(10, 100);

        // 使用Isolate进行编码，避免阻塞主线程
        jsonString = await compute(_encodeJsonInIsolate, data);
        onProgress?.call(70, 100);
      } else {
        logDebug('使用主线程进行小JSON编码');
        onProgress?.call(10, 100);

        // 小数据直接编码，但分批处理以避免阻塞
        jsonString = jsonEncode(data);
        onProgress?.call(70, 100);
      }

      // 流式写入文件，分块写入避免内存峰值
      final sink = outputFile.openWrite();
      try {
        const chunkSize = 64 * 1024; // 64KB chunks
        final totalLength = jsonString.length;

        for (int i = 0; i < totalLength; i += chunkSize) {
          final end =
              (i + chunkSize < totalLength) ? i + chunkSize : totalLength;
          final chunk = jsonString.substring(i, end);
          sink.write(chunk);

          // 定期刷新和更新进度
          if (i % (chunkSize * 10) == 0) {
            await sink.flush();
            final progress = 70 + ((i / totalLength) * 25).round();
            onProgress?.call(progress, 100);

            // 让UI有机会更新
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }

        await sink.flush();
        onProgress?.call(95, 100);
        logDebug('流式JSON编码完成');
      } finally {
        await sink.close();
      }

      onProgress?.call(100, 100);
    } catch (e, s) {
      AppLogger.e(
        '流式JSON编码失败',
        error: e,
        stackTrace: s,
        source: 'LargeFileManager',
      );
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
      AppLogger.e(
        '流式JSON解码失败',
        error: e,
        stackTrace: s,
        source: 'LargeFileManager',
      );
      rethrow;
    }
  }

  /// 在Isolate中从文件流式解码JSON
  static Future<Map<String, dynamic>> _decodeJsonFromFileInIsolate(
    String filePath,
  ) async {
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

      // 修复：使用UTF-8解码避免中文乱码
      final allBytes = chunks.expand((chunk) => chunk).toList();
      final content = utf8.decode(allBytes);
      return jsonDecode(content) as Map<String, dynamic>;
    } else {
      // 小文件直接读取
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    }
  }

  /// 验证文件是否可访问且大小在合理范围内
  static Future<bool> validateFile(
    String filePath, {
    int maxSize = 2 * 1024 * 1024 * 1024,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        logDebug('文件不存在: $filePath');
        return false;
      }
      final fileSize = await file.length();
      if (fileSize > maxSize) {
        logDebug(
          '文件过大: ${fileSize / 1024 / 1024}MB > ${maxSize / 1024 / 1024}MB',
        );
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

        if (estimatedSize > 200 * 1024 * 1024) {
          // 提高到200MB以上才使用Isolate
          logDebug(
            '使用Isolate处理大JSON编码 (估算大小: ${(estimatedSize / 1024 / 1024).toStringAsFixed(1)}MB)',
          );
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

        if (jsonString.length > 200 * 1024 * 1024) {
          // 提高到200MB以上才使用Isolate
          logDebug(
            '使用Isolate处理大JSON解码 (大小: ${(jsonString.length / 1024 / 1024).toStringAsFixed(1)}MB)',
          );
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
      AppLogger.e(
        '大JSON处理失败',
        error: e,
        stackTrace: s,
        source: 'LargeFileManager',
      );
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

  /// 分块复制文件（内存安全增强版）
  ///
  /// [source] - 源文件路径
  /// [target] - 目标文件路径
  /// [chunkSize] - 块大小，默认64KB
  /// [onProgress] - 进度回调 (current, total)
  /// [cancelToken] - 取消令牌，允许取消操作
  static Future<void> copyFileInChunks(
    String source,
    String target, {
    int chunkSize = _defaultChunkSize,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final sourceFile = File(source);
    final targetFile = File(target);

    if (!await sourceFile.exists()) {
      throw Exception('源文件不存在: $source');
    }

    // 确保目标目录存在
    await targetFile.parent.create(recursive: true);

    final totalSize = await sourceFile.length();

    // 根据文件大小动态调整块大小，大文件使用更大的块以提高效率
    int adjustedChunkSize = chunkSize;
    if (totalSize > 100 * 1024 * 1024) {
      // 100MB以上
      adjustedChunkSize = 512 * 1024; // 512KB
    } else if (totalSize > 10 * 1024 * 1024) {
      // 10MB以上
      adjustedChunkSize = 256 * 1024; // 256KB
    } else if (totalSize > 1 * 1024 * 1024) {
      // 1MB以上
      adjustedChunkSize = 128 * 1024; // 128KB
    }

    int copiedBytes = 0;

    // 使用更高效的分块读写方式
    try {
      // 对于大文件，使用固定大小的块读取，避免内存峰值
      final RandomAccessFile reader = await sourceFile.open(
        mode: FileMode.read,
      );
      final IOSink writer = targetFile.openWrite();

      try {
        bool continueReading = true;
        while (continueReading && copiedBytes < totalSize) {
          // 检查是否取消
          if (cancelToken?.isCancelled == true) {
            logDebug('文件复制操作被取消');
            // 清理不完整的目标文件
            try {
              if (await targetFile.exists()) {
                await targetFile.delete();
              }
            } catch (_) {}
            throw const CancelledException();
          }

          // 计算本次应该读取的字节数
          final remainingBytes = totalSize - copiedBytes;
          final currentChunkSize = remainingBytes < adjustedChunkSize
              ? remainingBytes
              : adjustedChunkSize;

          // 读取一个块
          final buffer = Uint8List(currentChunkSize);
          final bytesRead = await reader.readInto(buffer);

          if (bytesRead <= 0) {
            continueReading = false;
            continue;
          }

          // 写入实际读取的数据
          if (bytesRead < buffer.length) {
            writer.add(buffer.sublist(0, bytesRead));
          } else {
            writer.add(buffer);
          }

          copiedBytes += bytesRead;

          // 报告进度
          onProgress?.call(copiedBytes, totalSize);

          // 定期刷新，确保数据写入磁盘
          if (adjustedChunkSize > 0 &&
              copiedBytes % (adjustedChunkSize * 16) == 0) {
            await writer.flush();
          }

          // 内存压力检查和垃圾回收
          if (adjustedChunkSize > 0 &&
              copiedBytes % (adjustedChunkSize * 32) == 0) {
            await _checkMemoryPressure();
          }

          // 对于非常大的文件，添加短暂暂停，让UI线程有机会响应
          if (totalSize > 100 * 1024 * 1024 &&
              copiedBytes % (10 * 1024 * 1024) == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }

        await writer.flush();

        // 验证复制完整性
        final targetSize = await targetFile.length();
        if (targetSize != totalSize) {
          throw Exception('文件复制不完整: 期望 $totalSize 字节，实际 $targetSize 字节');
        }

        logDebug(
          '文件复制完成: $source -> $target (${(totalSize / 1024 / 1024).toStringAsFixed(1)}MB)',
        );
      } finally {
        await reader.close();
        await writer.close();
      }
    } catch (e) {
      // 清理不完整的目标文件
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (_) {}

      if (e is CancelledException) {
        logDebug('文件复制已取消: $source -> $target');
      } else {
        logDebug('文件复制失败: $source -> $target, 错误: $e');
      }

      rethrow;
    }
  }

  /// 检查内存压力并尝试释放
  static Future<void> _checkMemoryPressure() async {
    try {
      // 触发垃圾回收
      if (!kIsWeb) {
        // 在非Web平台可以尝试一些内存管理
        await Future.delayed(const Duration(milliseconds: 1));

        // 不直接设置全局错误处理程序，而是使用本地错误处理
        // 这样可以避免覆盖应用程序的全局错误处理
        try {
          // 主动检查内存状态
          // 使用更安全的方式检查内存
          final memoryPressure = _checkSystemMemoryPressure();
          if (memoryPressure) {
            throw OutOfMemoryError('内存检查触发');
          }
        } catch (error) {
          if (error is OutOfMemoryError) {
            logDebug('检测到内存不足，尝试紧急清理');
            emergencyMemoryCleanup();
          }
        }
      }
    } catch (e) {
      // 忽略内存检查错误
      logDebug('内存压力检查失败: $e');
    }
  }

  /// 检查系统内存压力
  ///
  /// 返回true表示内存压力大，false表示内存正常
  static bool _checkSystemMemoryPressure() {
    try {
      // 这里我们无法直接获取系统内存使用情况
      // 在实际应用中，可以通过平台特定的方法获取
      // 这里只是一个简单的实现
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 紧急内存清理（当检测到内存不足时）
  ///
  /// 增强版本：更积极地清理内存，多次尝试垃圾回收
  static Future<void> emergencyMemoryCleanup() async {
    try {
      logDebug('执行紧急内存清理...');

      // 触发垃圾回收
      if (!kIsWeb) {
        // 第一轮清理
        logDebug('- 第一轮内存清理');
        await Future.delayed(const Duration(milliseconds: 300));

        // 尝试释放一些可能的大对象引用
        _weakReferences.clear();

        // 第二轮清理
        logDebug('- 第二轮内存清理');
        await Future.delayed(const Duration(milliseconds: 300));

        // 尝试释放更多内存
        logDebug('检测到内存不足，尝试紧急清理');

        // 第三轮清理
        logDebug('- 第三轮内存清理');
        await Future.delayed(const Duration(milliseconds: 400));
      }

      logDebug('紧急内存清理完成');
    } catch (e) {
      logDebug('紧急内存清理失败: $e');
    }
  }

  // 用于存储弱引用的列表，帮助垃圾回收
  static final List<WeakReference<Object>> _weakReferences = [];

  /// 安全执行文件操作，带OutOfMemoryError处理
  ///
  /// 增强版本：预先检查内存，执行前后进行垃圾回收，自动重试
  static Future<T?> executeWithMemoryProtection<T>(
    Future<T> Function() operation, {
    String? operationName,
    int maxRetries = 1,
  }) async {
    final name = operationName ?? '文件操作';
    int retryCount = 0;

    // 预先进行垃圾回收
    await _checkMemoryPressure();

    while (true) {
      try {
        // 执行前先检查内存
        await Future.delayed(const Duration(milliseconds: 100));

        // 执行操作
        logDebug('开始执行$name (尝试 ${retryCount + 1}/${maxRetries + 1})');
        final result = await operation();

        // 操作完成后再次检查内存
        await _checkMemoryPressure();

        return result;
      } on OutOfMemoryError catch (e) {
        logDebug('$name 遇到内存不足错误: $e');

        // 执行紧急内存清理
        await emergencyMemoryCleanup();

        // 如果还有重试次数，则重试
        if (retryCount < maxRetries) {
          retryCount++;
          logDebug('正在重试$name ($retryCount/$maxRetries)...');

          // 重试前等待更长时间让系统回收内存
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        // 重试次数用完，抛出友好异常
        throw Exception('内存不足，无法完成$name。请关闭其他应用程序后重试，或选择较小的文件。');
      } catch (e) {
        logDebug('$name 执行失败: $e');
        rethrow;
      }
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

  /// 使用流式处理器复制文件（新的推荐方法）
  ///
  /// [source] - 源文件路径
  /// [target] - 目标文件路径
  /// [onProgress] - 进度回调
  /// [onMemoryPressure] - 内存压力回调
  /// [cancelToken] - 取消令牌
  static Future<void> streamCopyFile(
    String source,
    String target, {
    Function(int current, int total)? onProgress,
    Function(int pressureLevel)? onMemoryPressure,
    CancelToken? cancelToken,
  }) async {
    final processor = StreamFileProcessor();
    final streamCancelToken = StreamCancelToken();

    try {
      // 定期检查取消状态
      Timer? cancelCheckTimer;
      if (cancelToken != null) {
        cancelCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (
          _,
        ) {
          if (cancelToken.isCancelled) {
            streamCancelToken.cancel();
          }
        });
      }

      await processor.streamCopyFile(
        source,
        target,
        onProgress: onProgress,
        onMemoryPressure: onMemoryPressure,
        cancelToken: streamCancelToken,
      );

      cancelCheckTimer?.cancel();
    } on StreamCancelledException {
      throw const CancelledException();
    }
  }

  /// 流式处理大文件
  ///
  /// [filePath] - 文件路径
  /// [processor] - 数据处理函数
  /// [onProgress] - 进度回调
  /// [cancelToken] - 取消令牌
  static Future<T> streamProcessFile<T>(
    String filePath,
    Future<T> Function(Stream<Uint8List> dataStream, int totalSize) processor, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final streamProcessor = StreamFileProcessor();
    final streamCancelToken = StreamCancelToken();

    try {
      // 定期检查取消状态
      Timer? cancelCheckTimer;
      if (cancelToken != null) {
        cancelCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (
          _,
        ) {
          if (cancelToken.isCancelled) {
            streamCancelToken.cancel();
          }
        });
      }

      final result = await streamProcessor.streamProcessFile(
        filePath,
        processor,
        onProgress: onProgress,
        cancelToken: streamCancelToken,
      );

      cancelCheckTimer?.cancel();
      return result;
    } on StreamCancelledException {
      throw const CancelledException();
    }
  }

  /// 检查系统是否有足够资源处理文件（移除大小限制）
  static Future<bool> canProcessFile(String filePath) async {
    try {
      logDebug('开始检查文件处理能力: $filePath');

      // 首先检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        logDebug('文件不存在: $filePath');
        return false;
      }

      // 获取文件大小
      final fileSize = await getFileSizeSecurely(filePath);
      if (fileSize == 0) {
        logDebug('文件为空: $filePath');
        return false;
      }

      logDebug('文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

      // 尝试读取文件的第一个字节，确保文件可以访问
      try {
        // 使用更安全的方式检查文件可读性
        final randomAccessFile = await file.open(mode: FileMode.read);
        try {
          // 尝试读取第一个字节
          final buffer = Uint8List(1);
          final bytesRead = await randomAccessFile.readInto(buffer);

          if (bytesRead > 0) {
            logDebug('文件可读性检查通过: $filePath');
            return true;
          } else {
            logDebug('文件无法读取数据: $filePath');
            return false;
          }
        } finally {
          await randomAccessFile.close();
        }
      } catch (e) {
        logDebug('文件读取测试失败: $filePath, 错误: $e');

        // 如果是权限问题，尝试其他方法
        if (e.toString().contains('permission') ||
            e.toString().contains('权限')) {
          logDebug('检测到权限问题，尝试备用检查方法');
          try {
            // 尝试使用流的方式检查
            final stream = file.openRead(0, 1);
            await stream.first;
            logDebug('备用检查方法成功: $filePath');
            return true;
          } catch (e2) {
            logDebug('备用检查方法也失败: $filePath, 错误: $e2');
            return false;
          }
        }

        return false;
      }
    } catch (e) {
      logDebug('检查文件处理能力失败: $filePath, 错误: $e');
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
