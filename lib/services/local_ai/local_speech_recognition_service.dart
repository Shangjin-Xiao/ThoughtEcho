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

  @override
  void dispose() {
    _speech.cancel();
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
