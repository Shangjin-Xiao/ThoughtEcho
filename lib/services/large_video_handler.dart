import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../utils/app_logger.dart';
import 'large_file_manager.dart';

/// 大视频文件处理器
/// 
/// 专门处理大视频文件的导入、导出和优化，包括：
/// - 内存安全的视频文件处理
/// - 视频文件预检查和验证
/// - 渐进式加载和缓存策略
/// - 错误恢复和重试机制
class LargeVideoHandler {
  static const int _videoChunkSize = 1024 * 1024; // 1MB块大小
  static const int _maxRetryAttempts = 3;
  
  /// 安全导入大视频文件
  /// 
  /// [sourcePath] - 源视频文件路径
  /// [targetDirectory] - 目标目录
  /// [onProgress] - 进度回调 (0.0 - 1.0)
  /// [onStatusUpdate] - 状态更新回调
  /// [cancelToken] - 取消令牌
  static Future<String?> importLargeVideoSafely(
    String sourcePath,
    String targetDirectory, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    CancelToken? cancelToken,
  }) async {
    try {
      onStatusUpdate?.call('正在检查视频文件...');
      
      // 预检查视频文件
      final preCheckResult = await _preCheckVideoFile(sourcePath);
      if (!preCheckResult.isValid) {
        throw Exception(preCheckResult.errorMessage);
      }
      
      onStatusUpdate?.call('正在准备导入...');
      
      // 生成目标文件路径
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(sourcePath)}';
      final targetPath = path.join(targetDirectory, fileName);
      
      // 确保目标目录存在
      final targetDir = Directory(targetDirectory);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      onStatusUpdate?.call('正在复制视频文件...');
      
      // 使用内存安全的方式复制文件
      await _copyVideoFileWithMemoryProtection(
        sourcePath,
        targetPath,
        fileSize: preCheckResult.fileSize ?? 0,
        onProgress: onProgress,
        onStatusUpdate: onStatusUpdate,
        cancelToken: cancelToken,
      );
      
      onStatusUpdate?.call('导入完成');
      logDebug('大视频文件导入成功: $sourcePath -> $targetPath');
      
      return targetPath;
    } catch (e) {
      logDebug('大视频文件导入失败: $e');
      onStatusUpdate?.call('导入失败: $e');
      return null;
    }
  }
  
  /// 预检查视频文件
  static Future<VideoPreCheckResult> _preCheckVideoFile(String filePath) async {
    try {
      final file = File(filePath);
      
      // 检查文件是否存在
      if (!await file.exists()) {
        return const VideoPreCheckResult(
          isValid: false,
          errorMessage: '视频文件不存在',
        );
      }
      
      // 获取文件大小
      final fileSize = await file.length();
      if (fileSize == 0) {
        return const VideoPreCheckResult(
          isValid: false,
          errorMessage: '视频文件为空',
        );
      }
      
      // 检查文件扩展名
      final extension = path.extension(filePath).toLowerCase();
      final supportedExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.3gp', '.m4v'];
      if (!supportedExtensions.contains(extension)) {
        return VideoPreCheckResult(
          isValid: false,
          errorMessage: '不支持的视频格式: $extension',
        );
      }
      
      // 检查文件是否可读
      try {
        final stream = file.openRead(0, 1024); // 读取前1KB
        await stream.first;
      } catch (e) {
        return VideoPreCheckResult(
          isValid: false,
          errorMessage: '无法读取视频文件: $e',
        );
      }
      
      // 检查文件头，简单验证是否为有效的视频文件
      final isValidVideo = await _validateVideoFileHeader(file);
      if (!isValidVideo) {
        return const VideoPreCheckResult(
          isValid: false,
          errorMessage: '文件可能已损坏或不是有效的视频文件',
        );
      }
      
      return VideoPreCheckResult(
        isValid: true,
        fileSize: fileSize,
        extension: extension,
      );
    } catch (e) {
      return VideoPreCheckResult(
        isValid: false,
        errorMessage: '检查视频文件时出错: $e',
      );
    }
  }
  
  /// 验证视频文件头
  static Future<bool> _validateVideoFileHeader(File file) async {
    try {
      // 读取文件的前几个字节来检查文件签名
      final bytes = await file.openRead(0, 32).first;
      
      // 检查常见的视频文件签名
      if (bytes.length >= 4) {
        // MP4文件签名检查
        if (bytes.length >= 8) {
          final fourthByte = bytes[4];
          final fifthByte = bytes[5];
          final sixthByte = bytes[6];
          final seventhByte = bytes[7];
          
          // ftyp (MP4)
          if (fourthByte == 0x66 && fifthByte == 0x74 && 
              sixthByte == 0x79 && seventhByte == 0x70) {
            return true;
          }
        }
        
        // AVI文件签名 (RIFF)
        if (bytes[0] == 0x52 && bytes[1] == 0x49 && 
            bytes[2] == 0x46 && bytes[3] == 0x46) {
          return true;
        }
        
        // MOV文件通常也使用ftyp
        // WebM文件签名 (1A 45 DF A3)
        if (bytes.length >= 4 && bytes[0] == 0x1A && bytes[1] == 0x45 && 
            bytes[2] == 0xDF && bytes[3] == 0xA3) {
          return true;
        }
      }
      
      // 如果没有匹配到已知签名，但文件扩展名正确，仍然允许
      return true;
    } catch (e) {
      logDebug('验证视频文件头失败: $e');
      return true; // 验证失败时默认允许
    }
  }
  
  /// 使用内存保护机制复制视频文件
  /// 使用内存保护机制复制视频文件
  /// 
  /// 增强版本：更智能的重试机制，更好的内存管理，动态调整块大小
  static Future<void> _copyVideoFileWithMemoryProtection(
    String sourcePath,
    String targetPath, {
    required int fileSize,
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    CancelToken? cancelToken,
  }) async {
    int retryCount = 0;
    int adaptiveChunkSize = _calculateOptimalChunkSize(fileSize);
    
    // 预先清理内存
    await LargeFileManager.emergencyMemoryCleanup();

    while (retryCount < _maxRetryAttempts) {
      try {
        // 使用LargeFileManager的内存保护机制
        await LargeFileManager.executeWithMemoryProtection(
          () async {
            await _performVideoCopy(
              sourcePath,
              targetPath,
              fileSize: fileSize,
              chunkSize: adaptiveChunkSize,
              onProgress: onProgress,
              onStatusUpdate: onStatusUpdate,
              cancelToken: cancelToken,
            );
          },
          operationName: '视频文件复制',
          maxRetries: 0, // 我们在这里自己处理重试
        );
        
        return; // 成功复制，退出循环
      } on OutOfMemoryError catch (e) {
        retryCount++;
        logDebug('视频复制遇到内存不足 (尝试 $retryCount/$_maxRetryAttempts): $e');
        
        // 减小块大小，降低内存使用
        adaptiveChunkSize = (adaptiveChunkSize * 0.5).round();
        if (adaptiveChunkSize < 64 * 1024) { // 最小64KB
          adaptiveChunkSize = 64 * 1024;
        }
        
        logDebug('调整块大小为 ${adaptiveChunkSize / 1024}KB');

        if (retryCount >= _maxRetryAttempts) {
          throw Exception('多次尝试后仍然内存不足，请关闭其他应用后重试');
        }

        onStatusUpdate?.call('内存不足，正在重试 ($retryCount/$_maxRetryAttempts)...');

        // 清理可能的临时文件
        try {
          final tempFile = File(targetPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}

        // 等待更长时间让系统回收内存
        await Future.delayed(Duration(seconds: retryCount * 2));

        // 触发垃圾回收
        await LargeFileManager.emergencyMemoryCleanup();
      } catch (e) {
        // 其他错误直接抛出
        rethrow;
      }
    }
  }
  
  /// 根据文件大小计算最佳块大小
  static int _calculateOptimalChunkSize(int fileSize) {
    if (fileSize > 1024 * 1024 * 1024) { // 1GB以上
      return 512 * 1024; // 512KB
    } else if (fileSize > 500 * 1024 * 1024) { // 500MB以上
      return 1 * 1024 * 1024; // 1MB
    } else if (fileSize > 100 * 1024 * 1024) { // 100MB以上
      return 2 * 1024 * 1024; // 2MB
    } else {
      return 4 * 1024 * 1024; // 4MB
    }
  }
  
  /// 执行实际的视频文件复制
  static Future<void> _performVideoCopy(
    String sourcePath,
    String targetPath, {
    required int fileSize,
    int? chunkSize,
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
    CancelToken? cancelToken,
  }) async {
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);
    
    // 使用传入的块大小或根据文件大小动态调整
    int actualChunkSize = chunkSize ?? _videoChunkSize;
    if (chunkSize == null) {
      if (fileSize > 500 * 1024 * 1024) { // 500MB以上
        actualChunkSize = 2 * 1024 * 1024; // 2MB
      } else if (fileSize > 100 * 1024 * 1024) { // 100MB以上
        actualChunkSize = 1024 * 1024; // 1MB
      } else {
        actualChunkSize = 512 * 1024; // 512KB
      }
    }
    
    logDebug('使用块大小: ${actualChunkSize / 1024}KB 处理 ${fileSize / (1024 * 1024)}MB 文件');
    
    int copiedBytes = 0;
    
    try {
      final RandomAccessFile reader = await sourceFile.open(mode: FileMode.read);
      final IOSink writer = targetFile.openWrite();
      
      try {
        while (copiedBytes < fileSize) {
          // 检查取消状态
          if (cancelToken?.isCancelled == true) {
            // 清理不完整的目标文件
            try {
              if (await targetFile.exists()) {
                await targetFile.delete();
              }
            } catch (_) {}
            throw const CancelledException();
          }
          
          // 计算本次读取的大小
          final remainingBytes = fileSize - copiedBytes;
          final currentChunkSize = remainingBytes < actualChunkSize ? remainingBytes : actualChunkSize;
          
          // 读取数据块
          final buffer = Uint8List(currentChunkSize);
          final bytesRead = await reader.readInto(buffer);
          
          if (bytesRead <= 0) break;
          
          // 写入数据
          if (bytesRead < currentChunkSize) {
            writer.add(buffer.sublist(0, bytesRead));
          } else {
            writer.add(buffer);
          }
          
          copiedBytes += bytesRead;
          
          // 更新进度
          final progress = copiedBytes / fileSize;
          onProgress?.call(progress);
          
          // 定期刷新和内存检查
          if (chunkSize != null && chunkSize > 0 && copiedBytes % (chunkSize * 10) == 0) {
            await writer.flush();
            
            // 对于大文件，定期检查内存压力
            if (fileSize > 100 * 1024 * 1024) {
              await Future.delayed(const Duration(milliseconds: 1));
            }
          }
          
          // 状态更新 - 修复modulo操作避免除零错误
          if (chunkSize != null && chunkSize > 0 && copiedBytes % (chunkSize * 20) == 0) {
            final progressPercent = (progress * 100).toInt();
            onStatusUpdate?.call('正在复制... $progressPercent%');
          }
        }
        
        await writer.flush();
        
        // 验证复制完整性
        final targetSize = await targetFile.length();
        if (targetSize != fileSize) {
          throw Exception('文件复制不完整: 期望 $fileSize 字节，实际 $targetSize 字节');
        }
        
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
      rethrow;
    }
  }
  
  /// 获取视频文件信息
  static Future<VideoFileInfo?> getVideoFileInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      
      final fileSize = await file.length();
      final fileName = path.basename(filePath);
      final extension = path.extension(filePath);
      
      return VideoFileInfo(
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        extension: extension,
        fileSizeMB: fileSize / (1024 * 1024),
      );
    } catch (e) {
      logDebug('获取视频文件信息失败: $e');
      return null;
    }
  }
  
  /// 检查设备是否有足够内存处理指定大小的视频
  static bool canHandleVideoSize(int fileSizeBytes) {
    final fileSizeMB = fileSizeBytes / (1024 * 1024);
    
    // 基于经验的内存需求估算
    // 视频播放通常需要文件大小的2-3倍内存
    final estimatedMemoryMB = fileSizeMB * 2.5;
    
    // 简单的设备内存检查（这里可以根据实际情况调整）
    if (estimatedMemoryMB > 1024) { // 超过1GB内存需求
      return false;
    }
    
    return true;
  }
}

/// 视频预检查结果
class VideoPreCheckResult {
  final bool isValid;
  final String? errorMessage;
  final int? fileSize;
  final String? extension;
  
  const VideoPreCheckResult({
    required this.isValid,
    this.errorMessage,
    this.fileSize,
    this.extension,
  });
}

/// 视频文件信息
class VideoFileInfo {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String extension;
  final double fileSizeMB;
  
  const VideoFileInfo({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.extension,
    required this.fileSizeMB,
  });
  
  @override
  String toString() {
    return 'VideoFileInfo(fileName: $fileName, size: ${fileSizeMB.toStringAsFixed(1)}MB)';
  }
}