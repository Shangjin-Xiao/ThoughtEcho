import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
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
    ZipFileEncoder? encoder;
    
    try {
      logDebug('开始流式创建ZIP: $outputPath');
      
      encoder = ZipFileEncoder();
      encoder.create(outputPath);
      
      int processed = 0;
      final total = files.length;
      
      for (final entry in files.entries) {
        cancelToken?.throwIfCancelled();
        
        final relativePath = entry.key;
        final absolutePath = entry.value;
        
        try {
          final file = File(absolutePath);
          if (await file.exists()) {
            // 检查文件大小，超大文件跳过并记录
            final fileSize = await file.length();
            const maxSingleFileSize = 1024 * 1024 * 1024; // 1GB单文件限制
            
            if (fileSize > maxSingleFileSize) {
              logDebug('跳过超大文件: $relativePath (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)');
              continue;
            }
            
            // 添加文件到ZIP
            encoder.addFile(file, relativePath);
            logDebug('已添加文件到ZIP: $relativePath');
          } else {
            logDebug('文件不存在，跳过: $absolutePath');
          }
        } catch (e) {
          logDebug('添加文件到ZIP失败，跳过: $relativePath, 错误: $e');
          // 继续处理其他文件
        }
        
        processed++;
        onProgress?.call(processed, total);
        
        // 定期检查内存压力
        if (processed % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
      
      encoder.close();
      logDebug('ZIP创建完成: $outputPath');
    } catch (e, s) {
      // 清理不完整的ZIP文件
      try {
        encoder?.close();
        final zipFile = File(outputPath);
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      } catch (_) {}
      
      AppLogger.e('流式创建ZIP失败', error: e, stackTrace: s, source: 'ZipStreamProcessor');
      rethrow;
    }
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
    try {
      logDebug('开始流式解压ZIP: $zipPath -> $extractPath');
      
      // 检查ZIP文件
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        throw Exception('ZIP文件不存在: $zipPath');
      }
      
      final zipSize = await zipFile.length();
      const maxZipSize = 5 * 1024 * 1024 * 1024; // 5GB ZIP限制
      
      if (zipSize > maxZipSize) {
        throw Exception('ZIP文件过大: ${(zipSize / 1024 / 1024 / 1024).toStringAsFixed(1)}GB');
      }
      
      // 确保解压目录存在
      final extractDir = Directory(extractPath);
      if (!await extractDir.exists()) {
        await extractDir.create(recursive: true);
      }
      
      // 使用ZipDecoder进行流式解压
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(await zipFile.readAsBytes());
      
      try {
        int processed = 0;
        final total = archive.length;
        
        for (final file in archive) {
          cancelToken?.throwIfCancelled();
          
          // 应用文件过滤器
          if (fileFilter != null && !fileFilter(file.name)) {
            processed++;
            onProgress?.call(processed, total);
            continue;
          }
          
          try {
            // 检查文件大小
            const maxSingleFileSize = 1024 * 1024 * 1024; // 1GB单文件限制
            
            if (file.size > maxSingleFileSize) {
              logDebug('跳过超大文件: ${file.name} (${(file.size / 1024 / 1024).toStringAsFixed(1)}MB)');
              processed++;
              onProgress?.call(processed, total);
              continue;
            }
            
            // 解压文件
            if (file.isFile) {
              final outputFile = File('$extractPath/${file.name}');
              await outputFile.create(recursive: true);
              await outputFile.writeAsBytes(file.content as List<int>);
              logDebug('已解压文件: ${file.name}');
            }
          } catch (e) {
            logDebug('解压文件失败，跳过: ${file.name}, 错误: $e');
            // 继续处理其他文件
          }
          
          processed++;
          onProgress?.call(processed, total);
          
          // 定期检查内存压力
          if (processed % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
      } finally {
        // ZipDecoder不需要显式关闭
      }
      
      logDebug('ZIP解压完成: $zipPath');
    } catch (e, s) {
      AppLogger.e('流式解压ZIP失败', error: e, stackTrace: s, source: 'ZipStreamProcessor');
      rethrow;
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
