/// 图像预处理服务
///
/// 针对手写和印刷体提供不同的预处理策略，提升 OCR 识别准确率

import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../utils/app_logger.dart';

/// 图像预处理配置
class PreprocessConfig {
  /// 是否进行二值化
  final bool binarize;

  /// 二值化阈值 (0-255)
  final int binarizeThreshold;

  /// 是否去噪
  final bool denoise;

  /// 是否增强对比度
  final bool enhanceContrast;

  /// 对比度增强因子
  final double contrastFactor;

  /// 是否锐化
  final bool sharpen;

  /// 是否倾斜校正
  final bool deskew;

  /// 目标 DPI（用于调整分辨率）
  final int? targetDpi;

  const PreprocessConfig({
    this.binarize = true,
    this.binarizeThreshold = 128,
    this.denoise = true,
    this.enhanceContrast = true,
    this.contrastFactor = 1.5,
    this.sharpen = true,
    this.deskew = false,
    this.targetDpi = 300,
  });

  /// 印刷体预处理配置
  static const printed = PreprocessConfig(
    binarize: true,
    binarizeThreshold: 128,
    denoise: true,
    enhanceContrast: true,
    contrastFactor: 1.5,
    sharpen: true,
    deskew: true,
    targetDpi: 300,
  );

  /// 手写体预处理配置（更激进的处理）
  static const handwritten = PreprocessConfig(
    binarize: true,
    binarizeThreshold: 140, // 稍高的阈值，避免笔画断开
    denoise: true,
    enhanceContrast: true,
    contrastFactor: 2.0, // 更强的对比度
    sharpen: true,
    deskew: false, // 手写一般不需要倾斜校正
    targetDpi: 400, // 更高分辨率保留笔画细节
  );

  /// 低质量图片预处理配置
  static const lowQuality = PreprocessConfig(
    binarize: true,
    binarizeThreshold: 120,
    denoise: true,
    enhanceContrast: true,
    contrastFactor: 2.5,
    sharpen: true,
    deskew: true,
    targetDpi: 400,
  );
}

/// 图像预处理服务
class ImagePreprocessor {
  /// 预处理图像文件
  /// 
  /// [imagePath] 原始图像路径
  /// [config] 预处理配置
  /// 返回预处理后的图像路径
  static Future<String> preprocessImage(
    String imagePath, {
    PreprocessConfig config = PreprocessConfig.printed,
  }) async {
    try {
      logInfo('开始图像预处理: $imagePath', source: 'ImagePreprocessor');

      // 读取图像
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) {
        logError('无法解码图像: $imagePath', source: 'ImagePreprocessor');
        return imagePath; // 返回原图
      }

      // 1. 调整分辨率
      if (config.targetDpi != null) {
        image = _resizeForDpi(image, config.targetDpi!);
        logInfo('分辨率调整完成', source: 'ImagePreprocessor');
      }

      // 2. 转换为灰度图
      image = img.grayscale(image);
      logInfo('灰度转换完成', source: 'ImagePreprocessor');

      // 3. 去噪
      if (config.denoise) {
        image = _denoise(image);
        logInfo('去噪完成', source: 'ImagePreprocessor');
      }

      // 4. 增强对比度
      if (config.enhanceContrast) {
        image = img.adjustColor(image, contrast: config.contrastFactor);
        logInfo('对比度增强完成', source: 'ImagePreprocessor');
      }

      // 5. 锐化
      if (config.sharpen) {
        image = img.convolution(image, [
          -1, -1, -1,
          -1,  9, -1,
          -1, -1, -1,
        ]);
        logInfo('锐化完成', source: 'ImagePreprocessor');
      }

      // 6. 二值化
      if (config.binarize) {
        image = _binarize(image, config.binarizeThreshold);
        logInfo('二值化完成', source: 'ImagePreprocessor');
      }

      // 7. 倾斜校正
      if (config.deskew) {
        // 注意：倾斜校正算法较复杂，这里简化处理
        // 实际项目中可能需要更复杂的算法
        logInfo('跳过倾斜校正（需要更复杂的算法）', source: 'ImagePreprocessor');
      }

      // 保存预处理后的图像
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = path.join(
        tempDir.path,
        'preprocessed_$timestamp.png',
      );

      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodePng(image));

      logInfo('图像预处理完成: $outputPath', source: 'ImagePreprocessor');
      return outputPath;
    } catch (e) {
      logError('图像预处理失败: $e', source: 'ImagePreprocessor');
      return imagePath; // 失败时返回原图
    }
  }

  /// 调整图像分辨率以达到目标 DPI
  static img.Image _resizeForDpi(img.Image image, int targetDpi) {
    // 假设原始 DPI 为 72（常见默认值）
    const sourceDpi = 72;
    final scale = targetDpi / sourceDpi;

    if (scale <= 1.0) {
      return image; // 不需要放大
    }

    final newWidth = (image.width * scale).round();
    final newHeight = (image.height * scale).round();

    return img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.cubic,
    );
  }

  /// 去噪处理（中值滤波）
  static img.Image _denoise(img.Image image) {
    // 使用中值滤波去噪，保留边缘
    return img.medianBlur(image, radius: 1);
  }

  /// 二值化处理
  static img.Image _binarize(img.Image image, int threshold) {
    // 自适应阈值二值化
    final result = img.Image.from(image);

    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final gray = pixel.r.toInt(); // 已经是灰度图

        // 应用阈值
        final newValue = gray > threshold ? 255 : 0;
        result.setPixelRgb(x, y, newValue, newValue, newValue);
      }
    }

    return result;
  }

  /// 自动检测图像类型（印刷体/手写体）
  /// 
  /// 返回建议的预处理配置
  static Future<PreprocessConfig> detectImageType(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        return PreprocessConfig.printed; // 默认返回印刷体配置
      }

      // 简单启发式检测：
      // 1. 计算边缘密度 - 手写体边缘更不规则
      // 2. 计算笔画粗细变化 - 手写体变化更大
      // 这里简化为检查对比度和边缘复杂度

      final gray = img.grayscale(image);
      final edges = _detectEdges(gray);
      final edgeDensity = _calculateEdgeDensity(edges);

      logInfo('边缘密度: $edgeDensity', source: 'ImagePreprocessor');

      // 手写体通常边缘密度较低（笔画更粗糙）
      if (edgeDensity < 0.15) {
        logInfo('检测为手写体', source: 'ImagePreprocessor');
        return PreprocessConfig.handwritten;
      } else {
        logInfo('检测为印刷体', source: 'ImagePreprocessor');
        return PreprocessConfig.printed;
      }
    } catch (e) {
      logError('图像类型检测失败: $e', source: 'ImagePreprocessor');
      return PreprocessConfig.printed;
    }
  }

  /// 边缘检测（简化版 Sobel 算子）
  static img.Image _detectEdges(img.Image image) {
    return img.sobel(image);
  }

  /// 计算边缘密度
  static double _calculateEdgeDensity(img.Image edges) {
    int edgePixels = 0;
    int totalPixels = edges.width * edges.height;

    for (int y = 0; y < edges.height; y++) {
      for (int x = 0; x < edges.width; x++) {
        final pixel = edges.getPixel(x, y);
        if (pixel.r > 128) {
          // 亮像素认为是边缘
          edgePixels++;
        }
      }
    }

    return edgePixels / totalPixels;
  }

  /// 批量预处理多张图片
  static Future<List<String>> preprocessBatch(
    List<String> imagePaths, {
    PreprocessConfig? config,
  }) async {
    final results = <String>[];

    for (final path in imagePaths) {
      final processedConfig = config ?? await detectImageType(path);
      final processedPath = await preprocessImage(path, config: processedConfig);
      results.add(processedPath);
    }

    return results;
  }

  /// 清理临时预处理文件
  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('preprocessed_')) {
          await entity.delete();
        }
      }

      logInfo('临时预处理文件已清理', source: 'ImagePreprocessor');
    } catch (e) {
      logError('清理临时文件失败: $e', source: 'ImagePreprocessor');
    }
  }
}
