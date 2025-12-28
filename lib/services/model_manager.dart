import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

enum AppModelType {
  gemma,
  whisperTiny,
  whisperBase,
  tesseractChi,
  tesseractEng,
}

enum ModelStatus {
  notDownloaded,
  downloading,
  ready,
  error,
}

class ModelManager extends ChangeNotifier {
  static final ModelManager _instance = ModelManager._internal();
  static ModelManager get instance => _instance;

  ModelManager._internal();

  final Map<AppModelType, ModelStatus> _statuses = {
    AppModelType.gemma: ModelStatus.notDownloaded,
    AppModelType.whisperTiny: ModelStatus.notDownloaded,
    AppModelType.whisperBase: ModelStatus.notDownloaded,
    AppModelType.tesseractChi: ModelStatus.notDownloaded,
    AppModelType.tesseractEng: ModelStatus.notDownloaded,
  };

  final Map<AppModelType, double> _progress = {};

  final Map<AppModelType, String> _modelUrls = {
    // Placeholder URLs - in real implementation, replace with actual direct download links
    AppModelType.gemma: 'https://huggingface.co/rahulSyd/gemma-2b-it-gpu-int4/resolve/main/gemma-2b-it-gpu-int4.bin',
    AppModelType.whisperTiny: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
    AppModelType.whisperBase: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2',
    AppModelType.tesseractChi: 'https://github.com/tesseract-ocr/tessdata_fast/raw/main/chi_sim.traineddata',
    AppModelType.tesseractEng: 'https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata',
  };

  ModelStatus getStatus(AppModelType type) => _statuses[type] ?? ModelStatus.notDownloaded;
  double getProgress(AppModelType type) => _progress[type] ?? 0.0;

  Future<void> initialize() async {
    for (var type in AppModelType.values) {
      if (await isModelReady(type)) {
        _statuses[type] = ModelStatus.ready;
      }
    }
    notifyListeners();
  }

  Future<String> getModelPath(AppModelType type) async {
    final dir = await getApplicationSupportDirectory();
    final modelDir = Directory('${dir.path}/models/${type.name}');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    // Return specific filenames based on type
    switch (type) {
      case AppModelType.gemma:
        return '${modelDir.path}/gemma-2b-it-gpu-int4.bin';
      case AppModelType.whisperTiny:
        return '${modelDir.path}/sherpa-onnx-whisper-tiny/tiny-encoder.onnx'; // Assuming extracted structure
      case AppModelType.whisperBase:
        return '${modelDir.path}/sherpa-onnx-whisper-base/base-encoder.onnx';
      case AppModelType.tesseractChi:
        return '${modelDir.path}/chi_sim.traineddata';
      case AppModelType.tesseractEng:
        return '${modelDir.path}/eng.traineddata';
    }
  }

  Future<String> getModelDir(AppModelType type) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/models/${type.name}';
  }

  Future<bool> isModelReady(AppModelType type) async {
    final path = await getModelPath(type);
    return File(path).exists();
  }

  Future<void> downloadModel(AppModelType type) async {
    if (_statuses[type] == ModelStatus.downloading) return;

    try {
      _statuses[type] = ModelStatus.downloading;
      _progress[type] = 0.0;
      notifyListeners();

      final url = _modelUrls[type];
      if (url == null) throw Exception('No URL for model $type');

      final savePath = await getModelPath(type);
      final dio = Dio();

      // Determine if we need to extract
      final isArchive = url.endsWith('.tar.bz2') || url.endsWith('.zip');
      final downloadPath = isArchive ? '$savePath.tmp' : savePath;

      await dio.download(
        url,
        downloadPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _progress[type] = received / total;
            notifyListeners();
          }
        },
      );

      if (isArchive) {
        final bytes = File(downloadPath).readAsBytesSync();
        final archive = url.endsWith('.tar.bz2')
            ? TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes))
            : ZipDecoder().decodeBytes(bytes);

        final extractDir = File(savePath).parent.path;
        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            File('$extractDir/$filename')
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            Directory('$extractDir/$filename').create(recursive: true);
          }
        }
        File(downloadPath).deleteSync(); // Clean up archive
      }

      _statuses[type] = ModelStatus.ready;
      UnifiedLogService.instance.log(
        UnifiedLogLevel.info,
        'Model downloaded successfully: ${type.name}',
        source: 'ModelManager',
      );
    } catch (e) {
      _statuses[type] = ModelStatus.error;
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Failed to download model ${type.name}: $e',
        source: 'ModelManager',
        error: e,
      );
    } finally {
      notifyListeners();
    }
  }

  Future<void> importModel(AppModelType type, String sourcePath) async {
    try {
      final destPath = await getModelPath(type);
      final sourceFile = File(sourcePath);

      if (await sourceFile.exists()) {
        await sourceFile.copy(destPath);
        _statuses[type] = ModelStatus.ready;
        notifyListeners();

        UnifiedLogService.instance.log(
          UnifiedLogLevel.info,
          'Model imported successfully: ${type.name}',
          source: 'ModelManager',
        );
      } else {
        throw Exception('Source file not found');
      }
    } catch (e) {
       UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Failed to import model ${type.name}: $e',
        source: 'ModelManager',
        error: e,
      );
      rethrow;
    }
  }
}
