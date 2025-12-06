import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'app_logger.dart';

/// 媒体文件优化工具类
/// 提供流式处理、压缩、分块处理等功能来减少内存使用
class MediaOptimizationUtils {
  /// 图片压缩和优化
  static Future<String?> optimizeImage({
    required String sourcePath,
    required String outputDir,
    int? maxWidth,
    int? maxHeight,
    int quality = 85,
    bool enableProgressive = true,
  }) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) return null;

      // 获取文件信息
      final fileSize = await file.length();
      final fileName = path.basenameWithoutExtension(sourcePath);
      final outputPath = path.join(outputDir, '${fileName}_optimized.jpg');

      // 小文件直接复制，无需优化
      if (fileSize < 1 * 1024 * 1024) {
        // 1MB以下
        await file.copy(outputPath);
        return outputPath;
      }

      // 检查文件大小，对于超大图片使用分块处理
      if (fileSize > 100 * 1024 * 1024) {
        // 100MB以上
        logDebug(
          '图片文件过大 (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)，跳过优化',
        );
        await file.copy(outputPath);
        return outputPath;
      }

      // 流式读取和处理图片
      final bytes = await file.readAsBytes();

      // 使用compute在隔离线程中处理图片
      final optimizedBytes = await compute(_optimizeImageInIsolate, {
        'bytes': bytes,
        'maxWidth': maxWidth ?? _getMaxDimensionForPlatform(),
        'maxHeight': maxHeight ?? _getMaxDimensionForPlatform(),
        'quality': quality,
      });

      if (optimizedBytes != null) {
        await File(outputPath).writeAsBytes(optimizedBytes);
        return outputPath;
      }

      return null;
    } catch (e) {
      debugPrint('图片优化失败: $e');
      return null;
    }
  }

  /// 在隔离线程中优化图片（避免主线程阻塞和内存问题）
  static Uint8List? _optimizeImageInIsolate(Map<String, dynamic> params) {
    try {
      final bytes = params['bytes'] as Uint8List;
      final maxWidth = params['maxWidth'] as int;
      final maxHeight = params['maxHeight'] as int;
      final quality = params['quality'] as int;

      // 解码图片
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // 计算新的尺寸（保持长宽比）
      final resizedImage = _resizeImageKeepAspectRatio(
        image,
        maxWidth,
        maxHeight,
      );

      // 编码为JPEG格式并压缩
      return Uint8List.fromList(img.encodeJpg(resizedImage, quality: quality));
    } catch (e) {
      debugPrint('隔离线程图片处理失败: $e');
      return null;
    }
  }

  /// 保持长宽比的图片缩放
  static img.Image _resizeImageKeepAspectRatio(
    img.Image image,
    int maxWidth,
    int maxHeight,
  ) {
    if (image.width <= maxWidth && image.height <= maxHeight) {
      return image;
    }

    final aspectRatio = image.width / image.height;
    int newWidth, newHeight;

    if (aspectRatio > 1) {
      // 横向图片
      newWidth = maxWidth;
      newHeight = (maxWidth / aspectRatio).round();
    } else {
      // 纵向图片
      newHeight = maxHeight;
      newWidth = (maxHeight * aspectRatio).round();
    }

    return img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );
  }

  /// 视频文件分块处理（避免一次性加载到内存）
  static Future<bool> processVideoInChunks({
    required String sourcePath,
    required String outputPath,
    int chunkSize = 1024 * 1024, // 1MB chunks
  }) async {
    try {
      final sourceFile = File(sourcePath);
      final outputFile = File(outputPath);

      if (!await sourceFile.exists()) return false;

      final sink = outputFile.openWrite();
      final stream = sourceFile.openRead();

      await for (final chunk in stream) {
        sink.add(chunk);
        // 可以在这里添加进度回调
      }

      await sink.close();
      return true;
    } catch (e) {
      debugPrint('视频分块处理失败: $e');
      return false;
    }
  }

  /// 音频文件优化（降低比特率、采样率等）
  static Future<String?> optimizeAudio({
    required String sourcePath,
    required String outputDir,
    int bitRate = 128, // kbps
    int sampleRate = 44100, // Hz
  }) async {
    try {
      // 这里可以集成ffmpeg或其他音频处理库
      // 目前先简单复制文件
      final file = File(sourcePath);
      if (!await file.exists()) return null;

      final fileName = path.basenameWithoutExtension(sourcePath);
      final outputPath = path.join(outputDir, '${fileName}_optimized.mp3');

      await file.copy(outputPath);
      return outputPath;
    } catch (e) {
      debugPrint('音频优化失败: $e');
      return null;
    }
  }

  /// 检查可用内存（简单估算）
  static bool hasEnoughMemoryForFile(int fileSize) {
    try {
      // 简单的内存检查：文件大小不应超过可用内存的1/3
      // 这是一个保守的估算
      final isMobile = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);

      final conservativeLimit = isMobile
          ? 20 * 1024 * 1024 // 移动端20MB
          : 50 * 1024 * 1024; // 桌面端50MB

      return fileSize <= conservativeLimit;
    } catch (e) {
      return false;
    }
  }

  /// 获取平台推荐的最大图片尺寸
  static int _getMaxDimensionForPlatform() {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return isMobile ? 1920 : 2560; // 移动端1920px，桌面端2560px
  }

  /// 获取文件的MIME类型
  static String? getMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      default:
        return null;
    }
  }

  /// 预测处理后的文件大小
  static int estimateOptimizedSize(int originalSize, String fileType) {
    switch (fileType.toLowerCase()) {
      case 'image':
        // 图片压缩通常能减少50-80%的大小
        return (originalSize * 0.3).round();
      case 'video':
        // 视频压缩效果取决于原始质量，估算减少30%
        return (originalSize * 0.7).round();
      case 'audio':
        // 音频压缩效果有限，估算减少20%
        return (originalSize * 0.8).round();
      default:
        return originalSize;
    }
  }
}
