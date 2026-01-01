import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../utils/app_logger.dart';

/// Service for local speech recognition using on-device capabilities
/// 
/// Uses the speech_to_text package which leverages:
/// - iOS: Apple's Speech framework (on-device recognition)
/// - Android: Google's Speech Recognition API (on-device when available)
/// - Web: Web Speech API
/// 
/// This provides real-time, on-device speech recognition without requiring
/// external model downloads.
class LocalSpeechRecognitionService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isRecognizing = false;
  String? _error;
  String? _modelPath;
  String _lastRecognizedWords = '';
  double _confidence = 0.0;

  /// Whether the service is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Whether initialization is in progress  
  bool get isInitializing => _isInitializing;

  /// Whether recognition is in progress
  bool get isRecognizing => _isRecognizing;

  /// Error message if initialization failed
  String? get error => _error;

  /// Path to the current loaded model (not used, kept for compatibility)
  String? get modelPath => _modelPath;
  
  /// Last recognized words
  String get lastRecognizedWords => _lastRecognizedWords;
  
  /// Confidence level of last recognition (0.0 to 1.0)
  double get confidence => _confidence;

  /// Initialize the speech recognition service
  /// 
  /// This initializes the on-device speech recognition engine.
  /// No model download required.
  Future<void> initialize([String? modelPath]) async {
    if (_isInitializing) {
      logDebug('Speech recognition service is already initializing');
      return;
    }

    _isInitializing = true;
    _error = null;
    notifyListeners();

    try {
      final available = await _speech.initialize(
        onError: (error) {
          logDebug('Speech recognition error: ${error.errorMsg}');
          _error = error.errorMsg;
          notifyListeners();
        },
        onStatus: (status) {
          logDebug('Speech recognition status: $status');
          _isRecognizing = status == 'listening';
          notifyListeners();
        },
      );

      if (!available) {
        throw Exception('Speech recognition not available on this device');
      }

      _isInitialized = true;
      logDebug('Speech recognition service initialized successfully');
      
    } catch (e) {
      _error = e.toString();
      logDebug('Failed to initialize speech recognition service: $e');
      _isInitialized = false;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Start listening for speech
  /// 
  /// [onResult] - Callback for recognition results
  /// [locale] - Language locale (e.g., 'zh_CN', 'en_US')
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    String locale = 'zh_CN',
  }) async {
    if (!_isInitialized) {
      logDebug('Speech recognition service not initialized');
      await initialize();
    }

    if (_isRecognizing) {
      logDebug('Already listening');
      return;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          _lastRecognizedWords = result.recognizedWords;
          _confidence = result.confidence;
          onResult(result.recognizedWords, result.finalResult);
          notifyListeners();
        },
        localeId: locale,
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: false,
        partialResults: true,
      );
    } catch (e) {
      logDebug('Error starting speech recognition: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Stop listening for speech
  Future<void> stopListening() async {
    if (_isRecognizing) {
      await _speech.stop();
      _isRecognizing = false;
      notifyListeners();
    }
  }

  /// Cancel listening (without final result)
  Future<void> cancelListening() async {
    if (_isRecognizing) {
      await _speech.cancel();
      _isRecognizing = false;
      notifyListeners();
    }
  }

  /// Get available locales for speech recognition
  Future<List<stt.LocaleName>> getAvailableLocales() async {
    if (!_isInitialized) {
      return [];
    }
    return await _speech.locales();
  }

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
