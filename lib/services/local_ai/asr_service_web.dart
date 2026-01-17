import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import 'asr_types.dart';

/// Web 端占位实现：
///
/// - 仅用于保证 Web 编译不引入 dart:io / record / sherpa_onnx
/// - 真实 ASR 仅在支持 FFI/文件系统的平台提供
class ASRService extends ChangeNotifier {
  static final ASRService _instance = ASRService._internal();
  factory ASRService() => _instance;
  ASRService._internal();

  ASRModelConfig? _currentConfig;
  ASRModelConfig? get currentConfig => _currentConfig;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  final StreamController<ASRResult> _resultController =
      StreamController<ASRResult>.broadcast();
  Stream<ASRResult> get resultStream => _resultController.stream;

  Future<void> initialize([ASRModelConfig? config]) async {
    _currentConfig = config ?? ASRModels.whisperTiny;
    _isInitialized = false;
    logWarning('Web 平台不支持本地 ASR', source: 'ASRService');
    notifyListeners();
    throw UnsupportedError('Web 平台不支持本地 ASR');
  }

  Future<ASRResult> recognizeFile(String filePath) async {
    throw UnsupportedError('Web 平台不支持本地 ASR');
  }

  Future<ASRResult> recognizeAudioData(
    List<int> audioData, {
    int sampleRate = 16000,
  }) async {
    throw UnsupportedError('Web 平台不支持本地 ASR');
  }

  Future<void> startRealtimeRecognition() async {
    throw UnsupportedError('Web 平台不支持本地 ASR');
  }

  Future<ASRResult?> stopRealtimeRecognition() async {
    return null;
  }

  Future<void> cancelRealtimeRecognition() async {
    _isRecording = false;
    notifyListeners();
  }

  List<String> getSupportedLanguages() {
    return const [];
  }

  @override
  void dispose() {
    _resultController.close();
    super.dispose();
  }
}
