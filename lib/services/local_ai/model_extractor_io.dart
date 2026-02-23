import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import '../../utils/app_logger.dart';

/// 模型解压工具
class ModelExtractor {
  /// 解压文件 (支持 .zip, .tar, .tar.gz, .tar.bz2)
  static Future<String> extract(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) async {
    logInfo('开始解压(extractFileToDisk): $archivePath -> $extractDir',
        source: 'ModelExtractor');

    try {
      onProgress?.call(0.1);

      await Isolate.run(() async {
        await extractFileToDisk(archivePath, extractDir);
      });

      onProgress?.call(1.0);
      return _findRootExtractPath(extractDir);
    } catch (e) {
      logError('解压失败: $e', source: 'ModelExtractor');
      rethrow;
    }
  }

  static Future<String> extractTarBz2(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) =>
      extract(archivePath, extractDir, onProgress: onProgress);

  static Future<String> extractTarGz(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) =>
      extract(archivePath, extractDir, onProgress: onProgress);

  static Future<String> _findRootExtractPath(String extractDir) async {
    final dir = Directory(extractDir);
    if (!await dir.exists()) return extractDir;

    final entities = await dir.list().toList();
    final visibleEntities = entities.where((e) {
      final name = path.basename(e.path);
      return !name.startsWith('.');
    }).toList();

    if (visibleEntities.length == 1 && visibleEntities.first is Directory) {
      return visibleEntities.first.path;
    }
    return extractDir;
  }

  /// 检查 Whisper 模型目录是否完整
  static Future<WhisperModelFiles?> validateWhisperModel(
      String modelDir) async {
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
