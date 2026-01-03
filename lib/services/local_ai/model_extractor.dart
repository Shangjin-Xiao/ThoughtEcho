/// 模型解压工具
///
/// 负责解压 tar.bz2 等压缩格式的模型文件

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

import '../../utils/app_logger.dart';

/// 模型解压工具
class ModelExtractor {
  /// 解压 tar.bz2 文件
  ///
  /// [archivePath] 压缩文件路径
  /// [extractDir] 解压目标目录
  /// [onProgress] 进度回调 (0.0 - 1.0)
  /// 
  /// 返回解压后的根目录路径
  static Future<String> extractTarBz2(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) async {
    logInfo('开始解压: $archivePath -> $extractDir', source: 'ModelExtractor');

    try {
      // 进度回调仅用于 UI 提示；真正的解压会在后台 isolate 中完成。
      onProgress?.call(0.05);

      final extractedPath = await Isolate.run(() async {
        // 读取压缩文件（注意：此处仍为一次性读入；但放在 isolate 中可避免阻塞 UI）
        final file = File(archivePath);
        if (!await file.exists()) {
          throw Exception('archive_not_found');
        }

        final bytes = await file.readAsBytes();

        // 解压 bzip2
        final bzip2Decoded = BZip2Decoder().decodeBytes(bytes);

        // 解压 tar
        final archive = TarDecoder().decodeBytes(bzip2Decoded);

        // 确保目标目录存在
        final destDir = Directory(extractDir);
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }

        // 提取文件
        String? rootDir;

        for (final archiveFile in archive.files) {
          final fileName = archiveFile.name;

          // 跳过目录条目
          if (archiveFile.isFile) {
            // 提取根目录名
            final parts = fileName.split('/');
            if (parts.isNotEmpty && rootDir == null) {
              rootDir = parts[0];
            }

            final outputPath = path.join(extractDir, fileName);
            final outputFile = File(outputPath);

            // 确保父目录存在
            await outputFile.parent.create(recursive: true);

            // 写入文件
            await outputFile.writeAsBytes(archiveFile.content as List<int>);
          }
        }

        return rootDir != null ? path.join(extractDir, rootDir) : extractDir;
      });

      onProgress?.call(1.0);
      logInfo('解压完成: $extractedPath', source: 'ModelExtractor');
      return extractedPath;
    } catch (e) {
      logError('解压失败: $e', source: 'ModelExtractor');
      rethrow;
    }
  }

  /// 解压 tar.gz 文件
  static Future<String> extractTarGz(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) async {
    logInfo('开始解压: $archivePath -> $extractDir', source: 'ModelExtractor');

    try {
      onProgress?.call(0.05);

      final extractedPath = await Isolate.run(() async {
        final file = File(archivePath);
        if (!await file.exists()) {
          throw Exception('archive_not_found');
        }

        final bytes = await file.readAsBytes();

        // 解压 gzip
        final gzipDecoded = GZipDecoder().decodeBytes(bytes);

        // 解压 tar
        final archive = TarDecoder().decodeBytes(gzipDecoded);

        // 确保目标目录存在
        final destDir = Directory(extractDir);
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }

        // 提取文件
        String? rootDir;

        for (final archiveFile in archive.files) {
          final fileName = archiveFile.name;

          if (archiveFile.isFile) {
            final parts = fileName.split('/');
            if (parts.isNotEmpty && rootDir == null) {
              rootDir = parts[0];
            }

            final outputPath = path.join(extractDir, fileName);
            final outputFile = File(outputPath);

            await outputFile.parent.create(recursive: true);
            await outputFile.writeAsBytes(archiveFile.content as List<int>);
          }
        }

        return rootDir != null ? path.join(extractDir, rootDir) : extractDir;
      });

      onProgress?.call(1.0);
      logInfo('解压完成: $extractedPath', source: 'ModelExtractor');
      return extractedPath;
    } catch (e) {
      logError('解压失败: $e', source: 'ModelExtractor');
      rethrow;
    }
  }

  /// 根据文件扩展名自动选择解压方法
  static Future<String> extract(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) async {
    if (archivePath.endsWith('.tar.bz2') || archivePath.endsWith('.tbz2')) {
      return extractTarBz2(archivePath, extractDir, onProgress: onProgress);
    } else if (archivePath.endsWith('.tar.gz') || archivePath.endsWith('.tgz')) {
      return extractTarGz(archivePath, extractDir, onProgress: onProgress);
    } else {
      throw Exception('不支持的压缩格式: $archivePath');
    }
  }

  /// 检查 Whisper 模型目录是否完整
  ///
  /// Whisper 模型需要包含:
  /// - *-encoder.onnx (或 encoder.onnx)
  /// - *-decoder.onnx (或 decoder.onnx)
  /// - *-tokens.txt (或 tokens.txt)
  static Future<WhisperModelFiles?> validateWhisperModel(String modelDir) async {
    final dir = Directory(modelDir);
    if (!await dir.exists()) {
      return null;
    }

    String? encoderPath;
    String? decoderPath;
    String? tokensPath;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final name = path.basename(entity.path).toLowerCase();
        
        if (name.endsWith('-encoder.onnx') || name == 'encoder.onnx') {
          encoderPath = entity.path;
        } else if (name.endsWith('-decoder.onnx') || name == 'decoder.onnx') {
          decoderPath = entity.path;
        } else if (name.endsWith('-tokens.txt') || name == 'tokens.txt') {
          tokensPath = entity.path;
        }
      }
    }

    if (encoderPath != null && decoderPath != null && tokensPath != null) {
      return WhisperModelFiles(
        encoder: encoderPath,
        decoder: decoderPath,
        tokens: tokensPath,
      );
    }

    return null;
  }

  /// 查找 Tesseract traineddata 文件
  static Future<List<String>> findTrainedDataFiles(String dir) async {
    final directory = Directory(dir);
    if (!await directory.exists()) {
      return [];
    }

    final files = <String>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.traineddata')) {
        files.add(entity.path);
      }
    }

    return files;
  }
}

/// Whisper 模型文件路径
class WhisperModelFiles {
  final String encoder;
  final String decoder;
  final String tokens;

  const WhisperModelFiles({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  @override
  String toString() {
    return 'WhisperModelFiles(encoder: $encoder, decoder: $decoder, tokens: $tokens)';
  }
}
