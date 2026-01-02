import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import '../../models/local_ai_model_config.dart';
import '../../utils/app_logger.dart';

/// Manager for local AI model imports and downloads
/// 
/// Handles:
/// - Importing user-selected model files
/// - Validating model file formats
/// - Managing model storage directories
/// - Tracking model status
class LocalAIModelManager extends ChangeNotifier {
  bool _isImporting = false;
  double _importProgress = 0.0;
  String? _error;

  /// Whether an import is in progress
  bool get isImporting => _isImporting;

  /// Import progress (0.0 - 1.0)
  double get importProgress => _importProgress;

  /// Error message if operation failed
  String? get error => _error;

  /// Base directory for storing local AI models
  Future<String> get modelsDirectory async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(path.join(documentsDir.path, 'local_ai_models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  /// Get directory for a specific model type
  Future<String> getModelTypeDirectory(LocalAIModelType type) async {
    final baseDir = await modelsDirectory;
    final typeDir = Directory(path.join(baseDir, type.name));
    if (!await typeDir.exists()) {
      await typeDir.create(recursive: true);
    }
    return typeDir.path;
  }

  /// Import an embedding model (.tflite file and vocab.txt)
  /// 
  /// Returns the updated model info or null if failed
  Future<LocalAIModelInfo?> importEmbeddingModel() async {
    _isImporting = true;
    _importProgress = 0.0;
    _error = null;
    notifyListeners();

    try {
      // Pick .tflite model file
      final modelResult = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
        dialogTitle: 'Select TFLite Embedding Model (.tflite)',
      );

      if (modelResult == null || modelResult.files.isEmpty) {
        _error = 'No model file selected';
        return null;
      }

      final modelFile = modelResult.files.first;
      if (!modelFile.name.endsWith('.tflite')) {
        _error = 'Please select a .tflite file';
        return null;
      }

      _importProgress = 0.2;
      notifyListeners();

      // Pick vocabulary file
      final vocabResult = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
        dialogTitle: 'Select Vocabulary File (vocab.txt)',
      );

      if (vocabResult == null || vocabResult.files.isEmpty) {
        _error = 'No vocabulary file selected';
        return null;
      }

      _importProgress = 0.4;
      notifyListeners();

      // Copy files to model directory
      final modelDir = await getModelTypeDirectory(LocalAIModelType.embedding);
      
      final destModelPath = path.join(modelDir, 'model.tflite');
      final destVocabPath = path.join(modelDir, 'vocab.txt');

      // Copy model file
      if (modelFile.path != null) {
        await File(modelFile.path!).copy(destModelPath);
      } else if (modelFile.readStream != null) {
        final destFile = File(destModelPath);
        final sink = destFile.openWrite();
        await modelFile.readStream!.pipe(sink);
      }

      _importProgress = 0.7;
      notifyListeners();

      // Copy vocab file
      final vocabFile = vocabResult.files.first;
      if (vocabFile.path != null) {
        await File(vocabFile.path!).copy(destVocabPath);
      } else if (vocabFile.readStream != null) {
        final destFile = File(destVocabPath);
        final sink = destFile.openWrite();
        await vocabFile.readStream!.pipe(sink);
      }

      _importProgress = 0.9;
      notifyListeners();

      // Get file size
      final modelStat = await File(destModelPath).stat();
      
      _importProgress = 1.0;
      notifyListeners();

      logDebug('Embedding model imported successfully');
      
      return LocalAIModelInfo(
        id: 'user_embedding_model',
        name: modelFile.name.replaceAll('.tflite', ''),
        type: LocalAIModelType.embedding,
        modelPath: destModelPath,
        vocabPath: destVocabPath,
        fileSize: modelStat.size,
        version: 'user_import',
        status: LocalAIModelStatus.ready,
        lastUpdated: DateTime.now(),
      );

    } catch (e) {
      _error = 'Import failed: $e';
      logDebug('Error importing embedding model: $e');
      return null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  /// Import an ASR model (Whisper ONNX directory)
  /// 
  /// Returns the updated model info or null if failed
  Future<LocalAIModelInfo?> importASRModel() async {
    _isImporting = true;
    _importProgress = 0.0;
    _error = null;
    notifyListeners();

    try {
      // Pick model directory or zip file
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Whisper ONNX Model Directory',
      );

      if (result == null) {
        _error = 'No directory selected';
        return null;
      }

      _importProgress = 0.3;
      notifyListeners();

      final sourceDir = Directory(result);
      if (!await sourceDir.exists()) {
        _error = 'Selected directory does not exist';
        return null;
      }

      // Validate model structure
      final entries = await sourceDir.list().toList();
      final hasOnnxFile = entries.any((e) => e.path.endsWith('.onnx'));
      
      if (!hasOnnxFile) {
        _error = 'No .onnx files found in the selected directory';
        return null;
      }

      _importProgress = 0.5;
      notifyListeners();

      // Copy to model directory
      final modelDir = await getModelTypeDirectory(LocalAIModelType.asr);
      final destDir = Directory(path.join(modelDir, 'whisper'));
      
      if (await destDir.exists()) {
        await destDir.delete(recursive: true);
      }
      await destDir.create(recursive: true);

      // Copy files
      int totalSize = 0;
      for (final entry in entries) {
        if (entry is File) {
          final destPath = path.join(destDir.path, path.basename(entry.path));
          await entry.copy(destPath);
          totalSize += await entry.length();
        }
      }

      _importProgress = 1.0;
      notifyListeners();

      logDebug('ASR model imported successfully');

      return LocalAIModelInfo(
        id: 'user_asr_model',
        name: 'Whisper ONNX',
        type: LocalAIModelType.asr,
        modelPath: destDir.path,
        fileSize: totalSize,
        version: 'user_import',
        status: LocalAIModelStatus.ready,
        lastUpdated: DateTime.now(),
      );

    } catch (e) {
      _error = 'Import failed: $e';
      logDebug('Error importing ASR model: $e');
      return null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  /// Import OCR model files (Tesseract traineddata or PaddleOCR)
  /// 
  /// [usePaddleOCR] - If true, expects PaddleOCR model structure
  Future<LocalAIModelInfo?> importOCRModel({bool usePaddleOCR = false}) async {
    _isImporting = true;
    _importProgress = 0.0;
    _error = null;
    notifyListeners();

    try {
      if (usePaddleOCR) {
        return await _importPaddleOCRModel();
      } else {
        return await _importTesseractModel();
      }
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<LocalAIModelInfo?> _importTesseractModel() async {
    // Pick .traineddata files
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
      withReadStream: true,
      dialogTitle: 'Select Tesseract Language Files (.traineddata)',
    );

    if (result == null || result.files.isEmpty) {
      _error = 'No traineddata files selected';
      return null;
    }

    // Validate files
    final traineddataFiles = result.files.where(
      (f) => f.name.endsWith('.traineddata')
    ).toList();

    if (traineddataFiles.isEmpty) {
      _error = 'Please select .traineddata files';
      return null;
    }

    _importProgress = 0.3;
    notifyListeners();

    // Copy to tessdata directory
    final modelDir = await getModelTypeDirectory(LocalAIModelType.ocr);
    final tessdataDir = Directory(path.join(modelDir, 'tessdata'));
    
    if (!await tessdataDir.exists()) {
      await tessdataDir.create(recursive: true);
    }

    int totalSize = 0;
    final languages = <String>[];
    int processed = 0;

    for (final file in traineddataFiles) {
      final destPath = path.join(tessdataDir.path, file.name);
      
      if (file.path != null) {
        await File(file.path!).copy(destPath);
        totalSize += await File(file.path!).length();
      } else if (file.readStream != null) {
        final destFile = File(destPath);
        final sink = destFile.openWrite();
        await file.readStream!.pipe(sink);
        totalSize += await destFile.length();
      }

      languages.add(file.name.replaceAll('.traineddata', ''));
      processed++;
      _importProgress = 0.3 + (0.7 * processed / traineddataFiles.length);
      notifyListeners();
    }

    logDebug('Tesseract model imported: ${languages.join(", ")}');

    return LocalAIModelInfo(
      id: 'user_ocr_tesseract',
      name: 'Tesseract (${languages.join("+")})',
      type: LocalAIModelType.ocr,
      modelPath: tessdataDir.path,
      fileSize: totalSize,
      version: 'user_import',
      status: LocalAIModelStatus.ready,
      lastUpdated: DateTime.now(),
    );
  }

  Future<LocalAIModelInfo?> _importPaddleOCRModel() async {
    // Pick model directory
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select PaddleOCR Model Directory',
    );

    if (result == null) {
      _error = 'No directory selected';
      return null;
    }

    _importProgress = 0.3;
    notifyListeners();

    final sourceDir = Directory(result);
    if (!await sourceDir.exists()) {
      _error = 'Selected directory does not exist';
      return null;
    }

    // Validate PaddleOCR structure
    final entries = await sourceDir.list().toList();
    final hasModelFiles = entries.any((e) => 
      e.path.endsWith('.nb') || e.path.endsWith('.onnx')
    );

    if (!hasModelFiles) {
      _error = 'No valid PaddleOCR model files found';
      return null;
    }

    _importProgress = 0.5;
    notifyListeners();

    // Copy to model directory
    final modelDir = await getModelTypeDirectory(LocalAIModelType.ocr);
    final paddleDir = Directory(path.join(modelDir, 'paddleocr'));
    
    if (await paddleDir.exists()) {
      await paddleDir.delete(recursive: true);
    }
    await paddleDir.create(recursive: true);

    int totalSize = 0;
    for (final entry in entries) {
      if (entry is File) {
        final destPath = path.join(paddleDir.path, path.basename(entry.path));
        await entry.copy(destPath);
        totalSize += await entry.length();
      }
    }

    _importProgress = 1.0;
    notifyListeners();

    logDebug('PaddleOCR model imported successfully');

    return LocalAIModelInfo(
      id: 'user_ocr_paddleocr',
      name: 'PaddleOCR Lite',
      type: LocalAIModelType.ocr,
      modelPath: paddleDir.path,
      fileSize: totalSize,
      version: 'user_import',
      status: LocalAIModelStatus.ready,
      lastUpdated: DateTime.now(),
    );
  }

  /// Delete a model
  Future<bool> deleteModel(LocalAIModelType type) async {
    try {
      final modelDir = await getModelTypeDirectory(type);
      final dir = Directory(modelDir);
      
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        logDebug('Deleted ${type.name} model');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      logDebug('Error deleting model: $e');
      return false;
    }
  }

  /// Check if a model type is installed
  Future<bool> isModelInstalled(LocalAIModelType type) async {
    try {
      final modelDir = await getModelTypeDirectory(type);
      final dir = Directory(modelDir);
      
      if (!await dir.exists()) {
        return false;
      }

      final entries = await dir.list().toList();
      return entries.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get storage usage for all models
  Future<Map<String, int>> getStorageUsage() async {
    final usage = <String, int>{};
    
    for (final type in LocalAIModelType.values) {
      try {
        final modelDir = await getModelTypeDirectory(type);
        final dir = Directory(modelDir);
        
        if (await dir.exists()) {
          int size = 0;
          await for (final entry in dir.list(recursive: true)) {
            if (entry is File) {
              size += await entry.length();
            }
          }
          usage[type.name] = size;
        } else {
          usage[type.name] = 0;
        }
      } catch (e) {
        usage[type.name] = 0;
      }
    }

    return usage;
  }

  /// Format file size to human readable string
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
