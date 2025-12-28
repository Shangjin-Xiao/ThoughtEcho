import 'package:flutter/foundation.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/services/model_manager.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

class LocalAIService extends ChangeNotifier {
  static final LocalAIService _instance = LocalAIService._internal();
  static LocalAIService get instance => _instance;

  LocalAIService._internal();

  bool _isInitialized = false;
  LocalAISettings _settings = const LocalAISettings();

  bool get isInitialized => _isInitialized;
  LocalAISettings get settings => _settings;

  Future<void> initialize(LocalAISettings settings) async {
    _settings = settings;

    if (!_settings.enabled) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.info,
        'Local AI is disabled in settings',
        source: 'LocalAIService',
      );
      return;
    }

    try {
      await ModelManager.instance.initialize();
      _isInitialized = true;

      UnifiedLogService.instance.log(
        UnifiedLogLevel.info,
        'Local AI Service initialized',
        source: 'LocalAIService',
      );
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Failed to initialize Local AI Service: $e',
        source: 'LocalAIService',
        error: e,
      );
    }
    notifyListeners();
  }

  void updateSettings(LocalAISettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  bool isFeatureAvailable(String feature) {
    if (!_settings.enabled) return false;

    switch (feature) {
      case 'asr':
        return _settings.speechToTextEnabled &&
               (ModelManager.instance.getStatus(AppModelType.whisperTiny) == ModelStatus.ready ||
                ModelManager.instance.getStatus(AppModelType.whisperBase) == ModelStatus.ready);
      case 'ocr':
        return _settings.ocrEnabled &&
               ModelManager.instance.getStatus(AppModelType.tesseractEng) == ModelStatus.ready; // Simplified check
      case 'llm':
        return ModelManager.instance.getStatus(AppModelType.gemma) == ModelStatus.ready;
      default:
        return false;
    }
  }
}
