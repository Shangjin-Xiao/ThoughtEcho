import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../utils/app_logger.dart';

/// Service for local speech recognition using user-imported models
/// 
/// Supports Whisper ONNX models (tiny ~39MB, base ~74MB) through sherpa_onnx.
/// Note: sherpa_onnx is not added as a direct dependency to keep the app lightweight.
/// Users can import their own Whisper ONNX models for offline speech recognition.
/// 
/// For now, this service provides the interface and model management,
/// with actual inference requiring the sherpa_onnx runtime to be available.
class LocalSpeechRecognitionService extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isRecognizing = false;
  String? _error;
  String? _modelPath;

  /// Whether the service is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Whether initialization is in progress  
  bool get isInitializing => _isInitializing;

  /// Whether recognition is in progress
  bool get isRecognizing => _isRecognizing;

  /// Error message if initialization failed
  String? get error => _error;

  /// Path to the current loaded model
  String? get modelPath => _modelPath;

  /// Supported audio formats
  static const List<String> supportedFormats = ['wav', 'mp3', 'm4a', 'flac'];

  /// Initialize the speech recognition service with a Whisper ONNX model
  /// 
  /// [modelPath] - Path to the Whisper ONNX model directory
  /// The directory should contain:
  /// - encoder.onnx
  /// - decoder.onnx  
  /// - tokens.txt
  Future<void> initialize(String modelPath) async {
    if (_isInitializing) {
      logDebug('Speech recognition service is already initializing');
      return;
    }

    _isInitializing = true;
    _error = null;
    notifyListeners();

    try {
      // Validate model path
      final modelDir = Directory(modelPath);
      if (!await modelDir.exists()) {
        throw Exception('Model directory not found: $modelPath');
      }

      // Check for required files (Whisper ONNX model structure)
      final requiredFiles = ['encoder.onnx', 'decoder.onnx', 'tokens.txt'];
      final optionalStructure = ['model.onnx', 'config.json']; // Alternative structure
      
      bool hasRequiredFiles = true;
      for (final file in requiredFiles) {
        final filePath = File('$modelPath/$file');
        if (!await filePath.exists()) {
          hasRequiredFiles = false;
          break;
        }
      }

      // Check for alternative single-model structure
      if (!hasRequiredFiles) {
        final modelFile = File('$modelPath/model.onnx');
        if (!await modelFile.exists()) {
          // Also check for other common patterns
          final entries = await modelDir.list().toList();
          final onnxFiles = entries.where((e) => e.path.endsWith('.onnx')).toList();
          if (onnxFiles.isEmpty) {
            throw Exception(
              'No valid Whisper ONNX model found in: $modelPath\n'
              'Expected files: ${requiredFiles.join(", ")} or model.onnx'
            );
          }
        }
      }

      _modelPath = modelPath;
      _isInitialized = true;
      logDebug('Speech recognition service initialized with model at: $modelPath');
      
      // Note: Actual sherpa_onnx initialization would happen here
      // For now, we just validate the model structure
      
    } catch (e) {
      _error = e.toString();
      logDebug('Failed to initialize speech recognition service: $e');
      _isInitialized = false;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Transcribe an audio file to text
  /// 
  /// [audioPath] - Path to the audio file
  /// Returns the transcribed text or null if failed
  /// 
  /// Note: This is a placeholder implementation.
  /// Full implementation requires sherpa_onnx runtime.
  Future<String?> transcribeFile(String audioPath) async {
    if (!_isInitialized) {
      logDebug('Speech recognition service not initialized');
      return null;
    }

    // Validate audio file
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      logDebug('Audio file not found: $audioPath');
      return null;
    }

    // Check file extension
    final extension = audioPath.split('.').last.toLowerCase();
    if (!supportedFormats.contains(extension)) {
      logDebug('Unsupported audio format: $extension');
      return null;
    }

    _isRecognizing = true;
    notifyListeners();

    try {
      // Placeholder for actual transcription
      // In production, this would use sherpa_onnx to transcribe
      logDebug('Transcription would happen here with sherpa_onnx');
      logDebug('Audio file: $audioPath');
      logDebug('Model path: $_modelPath');
      
      // Return placeholder message indicating ASR is not yet implemented
      return null;
      
    } catch (e) {
      logDebug('Error during transcription: $e');
      return null;
    } finally {
      _isRecognizing = false;
      notifyListeners();
    }
  }

  /// Start real-time streaming recognition
  /// 
  /// Returns a stream of transcription results
  /// Note: This is a placeholder for streaming ASR
  Stream<String>? startStreamingRecognition() {
    if (!_isInitialized) {
      logDebug('Speech recognition service not initialized');
      return null;
    }

    // Placeholder for streaming recognition
    logDebug('Streaming recognition not yet implemented');
    return null;
  }

  /// Stop streaming recognition
  void stopStreamingRecognition() {
    _isRecognizing = false;
    notifyListeners();
  }

  /// Get model information
  Map<String, dynamic>? getModelInfo() {
    if (!_isInitialized || _modelPath == null) {
      return null;
    }

    return {
      'path': _modelPath,
      'type': 'Whisper ONNX',
      'status': 'ready',
    };
  }

  /// Dispose resources
  void disposeService() {
    _isInitialized = false;
    _modelPath = null;
    _isRecognizing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disposeService();
    super.dispose();
  }
}

/// Result of a speech recognition operation
class SpeechRecognitionResult {
  /// The transcribed text
  final String text;
  
  /// Confidence score (0.0 - 1.0)
  final double confidence;
  
  /// Language detected
  final String? language;
  
  /// Processing time in milliseconds
  final int processingTimeMs;

  const SpeechRecognitionResult({
    required this.text,
    this.confidence = 1.0,
    this.language,
    this.processingTimeMs = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'confidence': confidence,
      'language': language,
      'processingTimeMs': processingTimeMs,
    };
  }
}
