import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../services/large_file_manager.dart';
import '../utils/app_logger.dart';
import './path_security_utils.dart';

/// ZIP流式处理器
///
/// 专门处理大ZIP文件的创建和解压，避免内存溢出
class ZipStreamProcessor {
  /// 流式创建ZIP文件（增强版，支持大文件安全处理）
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
    return await LargeFileManager.executeWithMemoryProtection(
      () async => _performZipCreation(
        outputPath,
        files,
        onProgress: onProgress,
        cancelToken: cancelToken,
      ),
      operationName: 'ZIP文件创建',
    );
  }

  /// 执行受保护的ZIP创建操作
  static Future<void> _performZipCreation(
    String outputPath,
    Map<String, String> files, {
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<void>();
    Isolate? isolate;
    Timer? cancelTimer;

    try {
      logDebug('开始流式创建ZIP: $outputPath');
      cancelToken?.throwIfCancelled();

      isolate = await Isolate.spawn(_createZipInIsolate, {
        'sendPort': receivePort.sendPort,
        'outputPath': outputPath,
        'files': files,
      });

      receivePort.listen((message) {
        if (message is Map) {
          final type = message['type'];
          if (type == 'progress') {
            onProgress?.call(
              message['current'] as int,
              message['total'] as int,
            );
          } else if (type == 'done' && !completer.isCompleted) {
            completer.complete();
          } else if (type == 'error' && !completer.isCompleted) {
            completer.completeError(
              Exception(message['error']),
              StackTrace.fromString(message['stackTrace'] as String? ?? ''),
            );
          }
        }
      });

      cancelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (cancelToken?.isCancelled == true && !completer.isCompleted) {
          isolate?.kill(priority: Isolate.immediate);
          completer.completeError(const CancelledException());
        }
      });

      await completer.future;
    } catch (e, s) {
      if (e is! CancelledException) {
        AppLogger.e(
          '流式创建ZIP失败',
          error: e,
          stackTrace: s,
          source: 'ZipStreamProcessor',
        );
      }
      rethrow;
    } finally {
      cancelTimer?.cancel();
      isolate?.kill();
      receivePort.close();
      logDebug('ZIP创建完成: $outputPath');
    }
  }

  static Future<void> _createZipInIsolate(Map<String, dynamic> args) async {
    final sendPort = args['sendPort'] as SendPort;
    final outputPath = args['outputPath'] as String;
    final files = Map<String, String>.from(args['files'] as Map);
    final encoder = ZipFileEncoder();

    try {
      encoder.create(outputPath);
      var processed = 0;

      for (final entry in files.entries) {
        final file = File(entry.value);
        if (file.existsSync()) {
          try {
            await encoder.addFile(file, entry.key);
          } catch (_) {
            if (entry.key == 'backup_data.json') rethrow;
          }
        }
        processed++;
        sendPort.send({
          'type': 'progress',
          'current': processed,
          'total': files.length,
        });
      }

      await encoder.close();
      sendPort.send({'type': 'done'});
    } catch (e, s) {
      try {
        await encoder.close();
      } catch (_) {}
      sendPort.send({
        'type': 'error',
        'error': e.toString(),
        'stackTrace': s.toString(),
      });
    }
  }

  /// 流式解压ZIP文件（增强版，支持大文件安全处理）
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
    return await LargeFileManager.executeWithMemoryProtection(
      () async => _performZipExtraction(
        zipPath,
        extractPath,
        onProgress: onProgress,
        cancelToken: cancelToken,
        fileFilter: fileFilter,
      ),
      operationName: 'ZIP文件解压',
    );
  }

  /// 执行受保护的ZIP解压操作
  static Future<void> _performZipExtraction(
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
          completer.completeError(
            Exception(message['error']),
            StackTrace.fromString(message['stackTrace'] ?? ''),
          );
        }
      });

      // 监听取消
      cancelToken?.throwIfCancelled();
      cancelListener() {
        if (cancelToken?.isCancelled ?? false) {
          isolate.kill(priority: Isolate.immediate);
          completer.completeError(const CancelledException());
        }
      }

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
        AppLogger.e(
          '流式解压ZIP失败',
          error: e,
          stackTrace: s,
          source: 'ZipStreamProcessor',
        );
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
      try {
        final decoder = ZipDecoder();

        // 使用 InputFileStream 流式读取 ZIP，不将整个文件加载到内存
        final inputStream = InputFileStream(zipPath);
        final archive = decoder.decodeStream(inputStream);

        final filesToProcess =
            archive.files.where((file) => file.isFile).toList();
        final totalFiles = filesToProcess.length;
        sendPort.send(totalFiles); // 1. 发送总文件数

        int processedCount = 0;
        for (final file in filesToProcess) {
          final outputPath = '$extractPath/${file.name}';

          // 安全检查：防止Zip Slip路径穿越漏洞
          PathSecurityUtils.validateExtractionPath(outputPath, extractPath);

          // 确保目录存在
          final outputDir = Directory(File(outputPath).parent.path);
          if (!await outputDir.exists()) {
            await outputDir.create(recursive: true);
          }

          // 使用 OutputFileStream 直接写入磁盘，不经过内存中转
          final outputStream = OutputFileStream(outputPath);
          file.writeContent(outputStream);
          outputStream.closeSync();

          processedCount++;
          sendPort.send(processedCount); // 2. 发送当前进度

          // 每处理5个文件，给系统一个喘息的机会
          if (processedCount % 5 == 0) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }

        inputStream.closeSync();
      } catch (e) {
        sendPort.send('解压失败: $e');
        rethrow;
      }

      sendPort.send('done'); // 3. 发送完成信号
    } catch (e, s) {
      sendPort.send({'error': e.toString(), 'stackTrace': s.toString()});
    }
  }

  /// 验证ZIP文件完整性（流式方式）
  ///
  /// [zipPath] - ZIP文件路径
  static Future<bool> validateZipFile(String zipPath) async {
    try {
      return await compute(_validateZipFileInIsolate, zipPath);
    } catch (e) {
      logDebug('ZIP文件验证失败: $zipPath, 错误: $e');
      return false;
    }
  }

  static bool _validateZipFileInIsolate(String zipPath) {
    final inputStream = InputFileStream(zipPath);
    try {
      return ZipDecoder().decodeStream(inputStream).isNotEmpty;
    } finally {
      inputStream.closeSync();
    }
  }

  /// 获取ZIP文件信息（流式方式）
  ///
  /// [zipPath] - ZIP文件路径
  static Future<ZipInfo?> getZipInfo(String zipPath) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return null;
      }

      try {
        // 使用流式解析 ZIP，不将整个文件加载到内存
        final inputStream = InputFileStream(zipPath);
        final archive = ZipDecoder().decodeStream(inputStream);

        int totalUncompressedSize = 0;
        int fileCount = 0;
        final fileNames = <String>[];

        for (final file in archive) {
          totalUncompressedSize += file.size;
          fileCount++;
          fileNames.add(file.name);
        }

        inputStream.closeSync();

        final zipSize = await zipFile.length();

        return ZipInfo(
          compressedSize: zipSize,
          uncompressedSize: totalUncompressedSize,
          fileCount: fileCount,
          fileNames: fileNames,
        );
      } catch (e) {
        logDebug('ZIP信息获取失败: $zipPath, 错误: $e');
        return null;
      }
    } catch (e) {
      logDebug('获取ZIP信息失败: $zipPath, 错误: $e');
      return null;
    }
  }

  /// 检查ZIP是否包含特定文件（流式方式）
  ///
  /// [zipPath] - ZIP文件路径
  /// [fileName] - 要查找的文件名
  static Future<bool> containsFile(String zipPath, String fileName) async {
    try {
      return await compute(_containsFileInIsolate, {
        'zipPath': zipPath,
        'fileName': fileName,
      });
    } catch (e) {
      logDebug('检查ZIP文件内容失败: $zipPath, 错误: $e');
      return false;
    }
  }

  static bool _containsFileInIsolate(Map<String, String> args) {
    final inputStream = InputFileStream(args['zipPath']!);
    try {
      final archive = ZipDecoder().decodeStream(inputStream);
      return archive.any((file) => file.name == args['fileName']);
    } finally {
      inputStream.closeSync();
    }
  }

  /// 从ZIP中提取单个文件到内存（改进版）
  ///
  /// [zipPath] - ZIP文件路径
  /// [fileName] - 要提取的文件名
  static Future<Uint8List?> extractFileToMemory(
    String zipPath,
    String fileName,
  ) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return null;
      }

      try {
        // 使用流式解码
        final inputStream = InputFileStream(zipPath);
        final archive = ZipDecoder().decodeStream(inputStream);

        for (final file in archive) {
          if (file.name == fileName) {
            // 检查文件大小，避免将超大文件加载到内存
            const largeFileThreshold = 100 * 1024 * 1024; // 100MB

            if (file.size > largeFileThreshold) {
              inputStream.closeSync();
              logDebug(
                '文件过大，无法提取到内存: $fileName (${(file.size / 1024 / 1024).toStringAsFixed(1)}MB)',
              );
              throw Exception(
                '文件过大，无法提取到内存: ${(file.size / 1024 / 1024).toStringAsFixed(1)}MB',
              );
            }

            // 对于小文件，可以安全加载到内存
            final content = Uint8List.fromList(file.content as List<int>);
            inputStream.closeSync();
            return content;
          }
        }

        inputStream.closeSync();
        return null;
      } catch (e) {
        logDebug('从ZIP提取文件失败: $fileName, 错误: $e');
        return null;
      }
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
