import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../utils/app_logger.dart';

/// Service for local OCR text recognition using user-imported models
/// 
/// Supports:
/// - Tesseract traineddata files for multi-language OCR
/// - PaddleOCR Lite models (~8MB, optimized for Chinese)
/// 
/// Note: flutter_tesseract_ocr or paddle_ocr_flutter is not added as a direct 
/// dependency. Users need to import their own model files for offline OCR.
class LocalOCRService extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isRecognizing = false;
  String? _error;
  String? _tessdataPath;
  List<String> _availableLanguages = [];
  OCREngineType _engineType = OCREngineType.tesseract;

  /// Whether the service is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Whether initialization is in progress  
  bool get isInitializing => _isInitializing;

  /// Whether recognition is in progress
  bool get isRecognizing => _isRecognizing;

  /// Error message if initialization failed
  String? get error => _error;

  /// Path to tessdata directory
  String? get tessdataPath => _tessdataPath;

  /// Available language codes
  List<String> get availableLanguages => List.unmodifiable(_availableLanguages);

  /// Current OCR engine type
  OCREngineType get engineType => _engineType;

  /// Supported image formats
  static const List<String> supportedFormats = [
    'jpg',
    'jpeg',
    'png',
    'bmp',
    'gif',
    'webp'
  ];

  /// Initialize OCR service with Tesseract traineddata
  /// 
  /// [tessdataPath] - Path to the tessdata directory containing .traineddata files
  /// [languages] - List of language codes to use (e.g., ['chi_sim', 'eng'])
  Future<void> initializeTesseract(
    String tessdataPath, {
    List<String> languages = const ['chi_sim', 'eng'],
  }) async {
    if (_isInitializing) {
      logDebug('OCR service is already initializing');
      return;
    }

    _isInitializing = true;
    _error = null;
    notifyListeners();

    try {
      // Validate tessdata path
      final tessdataDir = Directory(tessdataPath);
      if (!await tessdataDir.exists()) {
        throw Exception('Tessdata directory not found: $tessdataPath');
      }

      // Check for traineddata files
      final files = await tessdataDir.list().toList();
      final traineddataFiles = files
          .where((f) => f.path.endsWith('.traineddata'))
          .map((f) => f.path.split('/').last.replaceAll('.traineddata', ''))
          .toList();

      if (traineddataFiles.isEmpty) {
        throw Exception('No .traineddata files found in: $tessdataPath');
      }

      // Validate requested languages
      final missingLanguages = <String>[];
      for (final lang in languages) {
        if (!traineddataFiles.contains(lang)) {
          missingLanguages.add(lang);
        }
      }

      if (missingLanguages.isNotEmpty) {
        logDebug('Warning: Some requested languages not found: ${missingLanguages.join(", ")}');
      }

      _tessdataPath = tessdataPath;
      _availableLanguages = traineddataFiles;
      _engineType = OCREngineType.tesseract;
      _isInitialized = true;

      logDebug('OCR service initialized with Tesseract');
      logDebug('Available languages: ${traineddataFiles.join(", ")}');

    } catch (e) {
      _error = e.toString();
      logDebug('Failed to initialize OCR service: $e');
      _isInitialized = false;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Initialize OCR service with PaddleOCR model
  /// 
  /// [modelPath] - Path to the PaddleOCR model directory
  Future<void> initializePaddleOCR(String modelPath) async {
    if (_isInitializing) {
      logDebug('OCR service is already initializing');
      return;
    }

    _isInitializing = true;
    _error = null;
    notifyListeners();

    try {
      // Validate model path
      final modelDir = Directory(modelPath);
      if (!await modelDir.exists()) {
        throw Exception('PaddleOCR model directory not found: $modelPath');
      }

      // Check for required PaddleOCR model files
      final requiredFiles = [
        'det.nb',  // Detection model
        'cls.nb',  // Classification model
        'rec.nb',  // Recognition model
        'ppocr_keys_v1.txt',  // Dictionary
      ];

      // Also check for alternative file patterns
      final entries = await modelDir.list().toList();
      final hasDetModel = entries.any((e) => 
        e.path.contains('det') && (e.path.endsWith('.nb') || e.path.endsWith('.onnx'))
      );
      final hasRecModel = entries.any((e) => 
        e.path.contains('rec') && (e.path.endsWith('.nb') || e.path.endsWith('.onnx'))
      );

      if (!hasDetModel || !hasRecModel) {
        throw Exception(
          'Invalid PaddleOCR model structure at: $modelPath\n'
          'Expected detection and recognition models'
        );
      }

      _tessdataPath = modelPath;
      _availableLanguages = ['chinese', 'english'];  // PaddleOCR default
      _engineType = OCREngineType.paddleOCR;
      _isInitialized = true;

      logDebug('OCR service initialized with PaddleOCR');
      logDebug('Model path: $modelPath');

    } catch (e) {
      _error = e.toString();
      logDebug('Failed to initialize OCR service: $e');
      _isInitialized = false;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Recognize text from an image file
  /// 
  /// [imagePath] - Path to the image file
  /// [languages] - Language codes for Tesseract (ignored for PaddleOCR)
  /// 
  /// Note: This is a placeholder implementation.
  /// Full implementation requires flutter_tesseract_ocr or paddle_ocr_flutter.
  Future<OCRResult?> recognizeText(
    String imagePath, {
    List<String>? languages,
  }) async {
    if (!_isInitialized) {
      logDebug('OCR service not initialized');
      return null;
    }

    // Validate image file
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      logDebug('Image file not found: $imagePath');
      return null;
    }

    // Check file extension
    final extension = imagePath.split('.').last.toLowerCase();
    if (!supportedFormats.contains(extension)) {
      logDebug('Unsupported image format: $extension');
      return null;
    }

    _isRecognizing = true;
    notifyListeners();

    try {
      final stopwatch = Stopwatch()..start();

      // Placeholder for actual OCR
      // In production, this would use flutter_tesseract_ocr or paddle_ocr_flutter
      logDebug('OCR would happen here with ${_engineType.name}');
      logDebug('Image: $imagePath');
      logDebug('Tessdata/Model path: $_tessdataPath');
      
      if (_engineType == OCREngineType.tesseract) {
        logDebug('Languages: ${languages?.join("+") ?? _availableLanguages.join("+")}');
      }

      stopwatch.stop();

      // Return placeholder result
      return OCRResult(
        text: '',
        confidence: 0.0,
        processingTimeMs: stopwatch.elapsedMilliseconds,
        blocks: [],
      );

    } catch (e) {
      logDebug('Error during OCR: $e');
      return null;
    } finally {
      _isRecognizing = false;
      notifyListeners();
    }
  }

  /// Recognize text from image bytes
  /// 
  /// [imageBytes] - Raw image bytes
  /// [languages] - Language codes for Tesseract
  Future<OCRResult?> recognizeTextFromBytes(
    Uint8List imageBytes, {
    List<String>? languages,
  }) async {
    if (!_isInitialized) {
      logDebug('OCR service not initialized');
      return null;
    }

    // Save to temp file and process
    // This is a workaround for engines that don't support direct byte input
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.png');
    
    try {
      await tempFile.writeAsBytes(imageBytes);
      return await recognizeText(tempFile.path, languages: languages);
    } finally {
      // Cleanup temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Get model/engine information
  Map<String, dynamic>? getModelInfo() {
    if (!_isInitialized) {
      return null;
    }

    return {
      'engine': _engineType.name,
      'path': _tessdataPath,
      'languages': _availableLanguages,
      'status': 'ready',
    };
  }

  /// Dispose resources
  void disposeService() {
    _isInitialized = false;
    _tessdataPath = null;
    _availableLanguages = [];
    _isRecognizing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disposeService();
    super.dispose();
  }
}

/// OCR engine type
enum OCREngineType {
  /// Tesseract OCR engine
  tesseract,
  /// PaddleOCR engine
  paddleOCR,
}

/// Result of an OCR operation
class OCRResult {
  /// The recognized text
  final String text;
  
  /// Overall confidence score (0.0 - 1.0)
  final double confidence;
  
  /// Processing time in milliseconds
  final int processingTimeMs;
  
  /// Individual text blocks with bounding boxes
  final List<OCRTextBlock> blocks;

  const OCRResult({
    required this.text,
    this.confidence = 1.0,
    this.processingTimeMs = 0,
    this.blocks = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'confidence': confidence,
      'processingTimeMs': processingTimeMs,
      'blocks': blocks.map((b) => b.toJson()).toList(),
    };
  }
}

/// A block of text with position information
class OCRTextBlock {
  /// The text content
  final String text;
  
  /// Confidence score for this block
  final double confidence;
  
  /// Bounding box [x, y, width, height]
  final List<int> boundingBox;

  const OCRTextBlock({
    required this.text,
    this.confidence = 1.0,
    this.boundingBox = const [0, 0, 0, 0],
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'confidence': confidence,
      'boundingBox': boundingBox,
    };
  }
}
