/// 语音识别服务
///
/// 使用 sherpa_onnx + Whisper 进行设备端语音转文字

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/speech_recognition_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';

/// 语音识别服务
class SpeechRecognitionService extends ChangeNotifier {
  static SpeechRecognitionService? _instance;

  /// 单例实例
  static SpeechRecognitionService get instance {
    _instance ??= SpeechRecognitionService._();
    return _instance!;
  }

  SpeechRecognitionService._();

  /// 模型管理器
  final ModelManager _modelManager = ModelManager.instance;

  /// 当前录制状态
  RecordingStatus _status = RecordingStatus.idle;

  /// 实时转写结果
  String _currentTranscription = '';

  /// 是否已初始化
  bool _initialized = false;

  /// 获取当前状态
  RecordingStatus get status => _status;

  /// 获取当前转写文本
  String get currentTranscription => _currentTranscription;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 是否正在录制
  bool get isRecording => _status.isRecording;

  /// 检查 ASR 模型是否可用
  bool get isModelAvailable {
    return _modelManager.isModelDownloaded('whisper-tiny') ||
        _modelManager.isModelDownloaded('whisper-base');
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 确保模型管理器已初始化
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 检查是否有可用的 ASR 模型
      if (!isModelAvailable) {
        logInfo('ASR 模型未下载，语音识别功能暂不可用', source: 'SpeechRecognitionService');
      }

      _initialized = true;
      logInfo('语音识别服务初始化完成', source: 'SpeechRecognitionService');
    } catch (e) {
      logError('语音识别服务初始化失败: $e', source: 'SpeechRecognitionService');
      rethrow;
    }
  }

  /// 开始录音
  Future<void> startRecording() async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (_status.isRecording) {
      logDebug('已在录制中', source: 'SpeechRecognitionService');
      return;
    }

    try {
      _status = const RecordingStatus(state: RecordingState.recording);
      _currentTranscription = '';
      notifyListeners();

      // TODO: 集成 record 包进行实际录音
      // 目前为占位实现
      logInfo('开始录音（占位实现）', source: 'SpeechRecognitionService');

      // 模拟录音过程
      _startRecordingSimulation();
    } catch (e) {
      _status = RecordingStatus(
        state: RecordingState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('开始录音失败: $e', source: 'SpeechRecognitionService');
      rethrow;
    }
  }

  /// 停止录音并转写
  Future<SpeechRecognitionResult> stopAndTranscribe() async {
    if (!_status.isRecording) {
      return SpeechRecognitionResult.empty;
    }

    try {
      _status = _status.copyWith(state: RecordingState.processing);
      notifyListeners();

      // TODO: 集成 sherpa_onnx 进行实际语音识别
      // 目前为占位实现
      logInfo('停止录音并转写（占位实现）', source: 'SpeechRecognitionService');

      // 模拟转写延迟
      await Future.delayed(const Duration(milliseconds: 500));

      final result = SpeechRecognitionResult(
        text: _currentTranscription.isNotEmpty ? _currentTranscription : '语音识别功能需要下载 Whisper 模型后使用',
        isFinal: true,
        timestamp: DateTime.now(),
      );

      _status = const RecordingStatus(state: RecordingState.completed);
      notifyListeners();

      return result;
    } catch (e) {
      _status = RecordingStatus(
        state: RecordingState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('转写失败: $e', source: 'SpeechRecognitionService');
      rethrow;
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_status.isRecording && !_status.isProcessing) {
      return;
    }

    try {
      // TODO: 停止实际录音
      _status = RecordingStatus.idle;
      _currentTranscription = '';
      notifyListeners();

      logInfo('取消录音', source: 'SpeechRecognitionService');
    } catch (e) {
      logError('取消录音失败: $e', source: 'SpeechRecognitionService');
    }
  }

  /// 从音频文件转写
  Future<SpeechRecognitionResult> transcribeFile(String audioPath) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (!isModelAvailable) {
      throw Exception('ASR 模型未下载，请先下载 Whisper 模型');
    }

    try {
      _status = const RecordingStatus(state: RecordingState.processing);
      notifyListeners();

      // TODO: 集成 sherpa_onnx 进行文件转写
      logInfo('从文件转写（占位实现）: $audioPath', source: 'SpeechRecognitionService');

      // 模拟转写
      await Future.delayed(const Duration(seconds: 1));

      final result = SpeechRecognitionResult(
        text: '文件转写功能需要集成 sherpa_onnx 后实现',
        isFinal: true,
        timestamp: DateTime.now(),
      );

      _status = const RecordingStatus(state: RecordingState.completed);
      notifyListeners();

      return result;
    } catch (e) {
      _status = RecordingStatus(
        state: RecordingState.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      logError('文件转写失败: $e', source: 'SpeechRecognitionService');
      rethrow;
    }
  }

  /// 重置状态
  void reset() {
    _status = RecordingStatus.idle;
    _currentTranscription = '';
    notifyListeners();
  }

  /// 模拟录音过程（占位）
  void _startRecordingSimulation() {
    // 模拟音量变化
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_status.isRecording) {
        timer.cancel();
        return;
      }

      // 更新录制时长
      _status = _status.copyWith(
        durationSeconds: _status.durationSeconds + 0.1,
        volumeLevel: 0.3 + (DateTime.now().millisecond % 500) / 1000,
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    cancelRecording();
    super.dispose();
  }
}
