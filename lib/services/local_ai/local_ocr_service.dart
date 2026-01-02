import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../utils/app_logger.dart';

/// Service for local OCR text recognition using Google ML Kit
/// 
/// Uses google_mlkit_text_recognition which provides on-device OCR:
/// - iOS: Uses MLKit text recognition
/// - Android: Uses ML Kit text recognition
/// 
/// Supports multiple scripts: Latin, Chinese, Devanagari, Japanese, Korean
/// No model downloads required - models are built into the package.
class LocalOCRService extends ChangeNotifier {
  TextRecognizer? _textRecognizer;
  
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isRecognizing = false;
  String? _error;
  TextRecognitionScript _script = TextRecognitionScript.chinese;

  /// Whether the service is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Whether initialization is in progress  
  bool get isInitializing => _isInitializing;

  /// Whether recognition is in progress
  bool get isRecognizing => _isRecognizing;

  /// Error message if initialization failed
  String? get error => _error;

  /// Current recognition script
  TextRecognitionScript get script => _script;

  /// Supported image formats
  static const List<String> supportedFormats = [
    'jpg',
    'jpeg',
    'png',
    'bmp',
    'webp'
  ];

  /// Initialize OCR service
  /// 
  /// [script] - Text recognition script (default: Chinese)
  Future<void> initialize([TextRecognitionScript? script]) async {
    if (_isInitializing) {
      logDebug('OCR service is already initializing');
      return;
    }

    _isInitializing = true;
    _error = null;
    notifyListeners();

    try {
      _script = script ?? TextRecognitionScript.chinese;
      _textRecognizer = TextRecognizer(script: _script);
      
      _isInitialized = true;
      logDebug('OCR service initialized successfully with script: $_script');
      
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
  /// Returns the recognized text or null if failed
  Future<RecognizedText?> recognizeFromFile(String imagePath) async {
    if (!_isInitialized) {
      logDebug('OCR service not initialized, initializing now...');
      await initialize();
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
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      
      logDebug('OCR completed. Recognized ${recognizedText.blocks.length} text blocks');
      return recognizedText;
      
    } catch (e) {
      logDebug('Error during OCR: $e');
      _error = e.toString();
      return null;
    } finally {
      _isRecognizing = false;
      notifyListeners();
    }
  }

  /// Recognize text from image bytes
  /// 
  /// [bytes] - Image data as bytes
  /// Returns the recognized text or null if failed
  Future<RecognizedText?> recognizeFromBytes(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    if (!_isInitialized) {
      logDebug('OCR service not initialized, initializing now...');
      await initialize();
    }

    _isRecognizing = true;
    notifyListeners();

    try {
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: ui.Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );
      
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      
      logDebug('OCR completed. Recognized ${recognizedText.blocks.length} text blocks');
      return recognizedText;
      
    } catch (e) {
      logDebug('Error during OCR: $e');
      _error = e.toString();
      return null;
    } finally {
      _isRecognizing = false;
      notifyListeners();
    }
  }

  /// Extract plain text from OCR result
  String extractPlainText(RecognizedText recognizedText) {
    return recognizedText.text;
  }

  /// Extract text by blocks with coordinates
  List<TextBlock> extractTextBlocks(RecognizedText recognizedText) {
    return recognizedText.blocks;
  }

  /// Change recognition script
  /// 
  /// Note: Requires reinitialization
  Future<void> changeScript(TextRecognitionScript newScript) async {
    if (_script == newScript) {
      return;
    }

    _textRecognizer?.close();
    _textRecognizer = null;
    _isInitialized = false;
    await initialize(newScript);
  }

  @override
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    _isInitialized = false;
    super.dispose();
  }
}

/// OCR Result with structured information
class OCRResult {
  /// Full recognized text
  final String fullText;
  
  /// Individual text blocks with positions
  final List<OCRTextBlock> blocks;
  
  /// Confidence score (0.0 - 1.0) if available
  final double? confidence;

  const OCRResult({
    required this.fullText,
    required this.blocks,
    this.confidence,
  });

  Map<String, dynamic> toJson() {
    return {
      'fullText': fullText,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'confidence': confidence,
    };
  }
}

/// Individual text block with position
class OCRTextBlock {
  /// Text content
  final String text;
  
  /// Bounding box (left, top, right, bottom)
  final List<double> boundingBox;
  
  /// Confidence score (0.0 - 1.0) if available
  final double? confidence;

  const OCRTextBlock({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'boundingBox': boundingBox,
      'confidence': confidence,
    };
  }
}
