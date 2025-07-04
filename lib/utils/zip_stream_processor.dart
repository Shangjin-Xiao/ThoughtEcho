import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../services/large_file_manager.dart';
import '../utils/app_logger.dart';

/// ZIP流式处理器
/// 
/// 专门处理大ZIP文件的创建和解压，避免内存溢出
class ZipStreamProcessor {
  /// 流式创建ZIP文件
  /// 
  /// [outputPath] - 输出ZIP文件路径
  /// [files] - 要添加的文件列表 {relativePath: absolutePath}
  /// [onProgress] - 进度回调 (current, total)
  /// [cancelToken] - 取消令牌
  static Future<void> createZipStreaming(
    String outputPath,
    Map<String, String> files, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final encoder = ZipFileEncoder();
    encoder.create(outputPath);
    
    try {
      logDebug('开始流式创建ZIP: $outputPath');
      int processed = 0;
      final total = files.length;

      for (final entry in files.entries) {
        cancelToken?.throwIfCancelled();
        final relativePath = entry.key;
        final absolutePath = entry.value;

        try {
          final file = File(absolutePath);
          if (await file.exists()) {
            // 使用新的流式方法添加文件
            await _addFileStreaming(encoder, file, relativePath);
            logDebug('已通过流式方法添加文件到ZIP: $relativePath');
          } else {
            logDebug('文件不存在，跳过: $absolutePath');
          }
        } catch (e) {
          logDebug('添加文件到ZIP失败，跳过: $relativePath, 错误: $e');
        }

        processed++;
        onProgress?.call(processed, total);
        
        // 短暂延迟以允许其他事件处理
        if (processed % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
    } catch (e, s) {
      AppLogger.e('流式创建ZIP失败', error: e, stackTrace: s, source: 'ZipStreamProcessor');
      rethrow;
    } finally {
      encoder.close();
      logDebug('ZIP创建完成: $outputPath');
    }
  }

  /// 内部辅助方法：以流的方式添加文件到ZIP
  static Future<void> _addFileStreaming(ZipFileEncoder encoder, File file, String relativePath) async {
    final stat = await file.stat();
    final fileStream = InputFileStream(file.path);
    final archiveFile = ArchiveFile.stream(
      relativePath,
      stat.size,
      fileStream,
    );
    archiveFile.lastModTime = stat.modified.millisecondsSinceEpoch;
    archiveFile.mode = stat.mode;
    
    encoder.addArchiveFile(archiveFile);
    // fileStream will be closed by the encoder
  }
  
  /// 流式解压ZIP文件
  /// 
  /// [zipPath] - ZIP文件路径
  /// [extractPath] - 解压目标目录
  /// [onProgress] - 进度回调 (current, total)
  /// [cancelToken] - 取消令牌
  /// [fileFilter] - 文件过滤器，返回true表示解压该文件
  static Future<void> extractZipStreaming(
    String zipPath,
    String extractPath, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
    bool Function(String fileName)? fileFilter,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    try {
      logDebug('开始流式解压ZIP: $zipPath -> $extractPath');
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        throw Exception('ZIP文件不存在: $zipPath');
      }

      final isolate = await Isolate.spawn(_extractInIsolate, {
        'sendPort': receivePort.sendPort,
        'zipPath': zipPath,
        'extractPath': extractPath,
      });

      int totalFiles = 0;
      int processedFiles = 0;

      receivePort.listen((message) {
        if (message is int) {
          if (totalFiles == 0) {
            totalFiles = message;
          } else {
            processedFiles = message;
            onProgress?.call(processedFiles, totalFiles);
          }
        } else if (message is String && message == 'done') {
          completer.complete();
        } else if (message is Map && message.containsKey('error')) {
          completer.completeError(Exception(message['error']), StackTrace.fromString(message['stackTrace'] ?? ''));
        }
      });
      
      // 监听取消
      cancelToken?.throwIfCancelled();
      final cancelListener = () {
        if (cancelToken?.isCancelled ?? false) {
          isolate.kill(priority: Isolate.immediate);
          completer.completeError(const CancelledException());
        }
      };
      
      // 简单的轮询检查取消状态
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (completer.isCompleted) {
          timer.cancel();
        } else {
          cancelListener();
        }
      });

      await completer.future;

    } catch (e, s) {
      if (e is! CancelledException) {
        AppLogger.e('流式解压ZIP失败', error: e, stackTrace: s, source: 'ZipStreamProcessor');
      }
      rethrow;
    } finally {
      receivePort.close();
    }
  }

  /// 在Isolate中执行解压，并通过SendPort报告进度
  static void _extractInIsolate(Map<String, dynamic> args) async {
    final SendPort sendPort = args['sendPort'];
    final String zipPath = args['zipPath'];
    final String extractPath = args['extractPath'];

    try {
      final inputStream = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      
      final filesToProcess = archive.files.where((file) => file.isFile).toList();
      final totalFiles = filesToProcess.length;
      sendPort.send(totalFiles); // 1. 发送总文件数

      int processedCount = 0;
      for (final file in filesToProcess) {
        final outputStream = OutputFileStream('$extractPath/${file.name}');
        try {
          file.writeContent(outputStream);
        } finally {
          await outputStream.close();
        }
        processedCount++;
        sendPort.send(processedCount); // 2. 发送当前进度
      }
      
      await inputStream.close();
      sendPort.send('done'); // 3. 发送完成信号
    } catch (e, s) {
      sendPort.send({
        'error': e.toString(),
        'stackTrace': s.toString(),
      });
    }
  }
  
  /// 验证ZIP文件完整性
  /// 
  /// [zipPath] - ZIP文件路径
  static Future<bool> validateZipFile(String zipPath) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return false;
      }
      
      // 尝试打开ZIP文件
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(await zipFile.readAsBytes());
      
      // 检查是否能获取文件列表
      return archive.isNotEmpty;
    } catch (e) {
      logDebug('ZIP文件验证失败: $zipPath, 错误: $e');
      return false;
    }
  }
  
  /// 获取ZIP文件信息
  /// 
  /// [zipPath] - ZIP文件路径
  static Future<ZipInfo?> getZipInfo(String zipPath) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return null;
      }
      
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(await zipFile.readAsBytes());
      
      int totalUncompressedSize = 0;
      int fileCount = 0;
      final fileNames = <String>[];
      
      for (final file in archive) {
        totalUncompressedSize += file.size;
        fileCount++;
        fileNames.add(file.name);
      }
      
      final zipSize = await zipFile.length();
      
      return ZipInfo(
        compressedSize: zipSize,
        uncompressedSize: totalUncompressedSize,
        fileCount: fileCount,
        fileNames: fileNames,
      );
    } catch (e) {
      logDebug('获取ZIP信息失败: $zipPath, 错误: $e');
      return null;
    }
  }
  
  /// 检查ZIP是否包含特定文件
  /// 
  /// [zipPath] - ZIP文件路径
  /// [fileName] - 要查找的文件名
  static Future<bool> containsFile(String zipPath, String fileName) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return false;
      }
      
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(await zipFile.readAsBytes());
      
      for (final file in archive) {
        if (file.name == fileName) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      logDebug('检查ZIP文件内容失败: $zipPath, 错误: $e');
      return false;
    }
  }
  
  /// 从ZIP中提取单个文件到内存
  /// 
  /// [zipPath] - ZIP文件路径
  /// [fileName] - 要提取的文件名
  static Future<Uint8List?> extractFileToMemory(String zipPath, String fileName) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return null;
      }
      
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(await zipFile.readAsBytes());
      
      for (final file in archive) {
        if (file.name == fileName) {
          // 检查文件大小
          const maxMemoryFileSize = 100 * 1024 * 1024; // 100MB内存限制
          
          if (file.size > maxMemoryFileSize) {
            logDebug('文件过大，无法加载到内存: $fileName (${(file.size / 1024 / 1024).toStringAsFixed(1)}MB)');
            return null;
          }
          
          return Uint8List.fromList(file.content as List<int>);
        }
      }
      
      return null;
    } catch (e) {
      logDebug('从ZIP提取文件到内存失败: $fileName, 错误: $e');
      return null;
    }
  }
}

/// ZIP文件信息
class ZipInfo {
  final int compressedSize;
  final int uncompressedSize;
  final int fileCount;
  final List<String> fileNames;
  
  const ZipInfo({
    required this.compressedSize,
    required this.uncompressedSize,
    required this.fileCount,
    required this.fileNames,
  });
  
  double get compressionRatio => 
      uncompressedSize > 0 ? (compressedSize / uncompressedSize) : 0.0;
  
  String get compressedSizeFormatted => 
      '${(compressedSize / 1024 / 1024).toStringAsFixed(1)}MB';
  
  String get uncompressedSizeFormatted => 
      '${(uncompressedSize / 1024 / 1024).toStringAsFixed(1)}MB';
  
  @override
  String toString() {
    return 'ZipInfo(files: $fileCount, compressed: $compressedSizeFormatted, '
           'uncompressed: $uncompressedSizeFormatted, ratio: ${(compressionRatio * 100).toStringAsFixed(1)}%)';
  }
}
