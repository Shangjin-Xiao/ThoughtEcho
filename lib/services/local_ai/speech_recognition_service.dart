/// 语音识别服务
///
/// 使用 sherpa_onnx + Whisper 进行设备端语音转文字

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../models/speech_recognition_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';

// sherpa_onnx imports - conditional import for platform support
// ignore: depend_on_referenced_packages
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

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

  /// sherpa_onnx 识别器
  sherpa.OfflineRecognizer? _recognizer;

  /// 音频缓冲
  final List<double> _audioBuffer = [];

  /// 录音计时器
  Timer? _recordingTimer;

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

      // 尝试初始化 sherpa_onnx 识别器
      if (isModelAvailable) {
        await _initializeRecognizer();
      } else {
        logInfo('ASR 模型未下载，语音识别功能暂不可用', source: 'SpeechRecognitionService');
      }

      _initialized = true;
      logInfo('语音识别服务初始化完成', source: 'SpeechRecognitionService');
    } catch (e) {
      logError('语音识别服务初始化失败: $e', source: 'SpeechRecognitionService');
      // 不抛出错误，允许服务继续运行（只是没有模型）
      _initialized = true;
    }
  }

  /// 初始化 sherpa_onnx 识别器
  Future<void> _initializeRecognizer() async {
    try {
      final modelPath = _getAvailableModelPath();
      if (modelPath == null) {
        logError('无法找到可用的 ASR 模型', source: 'SpeechRecognitionService');
        return;
      }

      // 解压模型文件（如果是压缩包）
      final extractedPath = await _extractModelIfNeeded(modelPath);

      // 配置 Whisper 模型
      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: path.join(extractedPath, 'encoder.onnx'),
            decoder: path.join(extractedPath, 'decoder.onnx'),
            language: 'zh', // 中文
            task: 'transcribe',
          ),
          tokens: path.join(extractedPath, 'tokens.txt'),
          numThreads: 4,
          debug: false,
          modelType: 'whisper',
        ),
      );

      _recognizer = sherpa.OfflineRecognizer(config);
      logInfo('sherpa_onnx 识别器初始化成功', source: 'SpeechRecognitionService');
    } catch (e) {
      logError('初始化 sherpa_onnx 识别器失败: $e', source: 'SpeechRecognitionService');
      _recognizer = null;
    }
  }

  /// 获取可用的模型路径
  String? _getAvailableModelPath() {
    // 优先使用 whisper-base
    if (_modelManager.isModelDownloaded('whisper-base')) {
      return _modelManager.getModelPath('whisper-base');
    }
    // 其次使用 whisper-tiny
    if (_modelManager.isModelDownloaded('whisper-tiny')) {
      return _modelManager.getModelPath('whisper-tiny');
    }
    return null;
  }

  /// 解压模型文件（如果需要）
  Future<String> _extractModelIfNeeded(String modelPath) async {
    // 如果模型是压缩包，需要解压
    if (modelPath.endsWith('.tar.bz2') || modelPath.endsWith('.tar.gz')) {
      final appDir = await getApplicationDocumentsDirectory();
      final extractDir = path.join(
        appDir.path,
        'local_ai_models',
        'whisper_extracted',
      );

      final dir = Directory(extractDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        // TODO: 实现解压逻辑
        logInfo('解压模型到: $extractDir', source: 'SpeechRecognitionService');
      }

      return extractDir;
    }

    // 如果已经是目录，直接返回
    return path.dirname(modelPath);
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
      _audioBuffer.clear();
      notifyListeners();

      // 开始录制计时
      _startRecordingTimer();

      logInfo('开始录音', source: 'SpeechRecognitionService');
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
      _recordingTimer?.cancel();
      _status = _status.copyWith(state: RecordingState.processing);
      notifyListeners();

      String transcribedText = '';

      if (_recognizer != null && _audioBuffer.isNotEmpty) {
        // 使用 sherpa_onnx 进行转写
        transcribedText = await _transcribeAudio(_audioBuffer);
      } else if (_recognizer == null) {
        // 没有识别器，提示用户下载模型
        transcribedText = _currentTranscription.isNotEmpty 
            ? _currentTranscription 
            : '请先下载语音识别模型';
      }

      final result = SpeechRecognitionResult(
        text: transcribedText,
        isFinal: true,
        timestamp: DateTime.now(),
      );

      _status = const RecordingStatus(state: RecordingState.completed);
      notifyListeners();

      logInfo('转写完成: ${transcribedText.length} 字符', source: 'SpeechRecognitionService');
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

  /// 使用 sherpa_onnx 转写音频
  Future<String> _transcribeAudio(List<double> samples) async {
    if (_recognizer == null) {
      return '';
    }

    try {
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(
        samples: Float32List.fromList(samples),
        sampleRate: 16000,
      );
      _recognizer!.decode(stream);
      
      final result = _recognizer!.getResult(stream);
      stream.free();
      
      return result.text;
    } catch (e) {
      logError('sherpa_onnx 转写失败: $e', source: 'SpeechRecognitionService');
      return '';
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_status.isRecording && !_status.isProcessing) {
      return;
    }

    try {
      _recordingTimer?.cancel();
      _status = RecordingStatus.idle;
      _currentTranscription = '';
      _audioBuffer.clear();
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

    if (_recognizer == null) {
      // 尝试初始化识别器
      if (isModelAvailable) {
        await _initializeRecognizer();
      }
      
      if (_recognizer == null) {
        throw Exception('ASR 模型未下载或初始化失败，请先下载 Whisper 模型');
      }
    }

    try {
      _status = const RecordingStatus(state: RecordingState.processing);
      notifyListeners();

      logInfo('从文件转写: $audioPath', source: 'SpeechRecognitionService');

      // 读取音频文件
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('音频文件不存在: $audioPath');
      }

      // 解码音频文件为 PCM 数据
      final samples = await _decodeAudioFile(audioPath);
      
      // 使用 sherpa_onnx 转写
      final text = await _transcribeAudio(samples);

      final result = SpeechRecognitionResult(
        text: text,
        isFinal: true,
        timestamp: DateTime.now(),
        audioPath: audioPath,
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

  /// 解码音频文件为 PCM 采样数据
  Future<List<double>> _decodeAudioFile(String audioPath) async {
    // TODO: 实现音频解码
    // 这里需要使用音频解码库将文件转换为 16kHz 单声道 float32 PCM 数据
    // 暂时返回空数组
    logInfo('解码音频文件（需要实现）', source: 'SpeechRecognitionService');
    return [];
  }

  /// 重置状态
  void reset() {
    _recordingTimer?.cancel();
    _status = RecordingStatus.idle;
    _currentTranscription = '';
    _audioBuffer.clear();
    notifyListeners();
  }

  /// 开始录音计时器
  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_status.isRecording) {
        timer.cancel();
        return;
      }

      // 更新录制时长和模拟音量
      _status = _status.copyWith(
        durationSeconds: _status.durationSeconds + 0.1,
        volumeLevel: 0.3 + (DateTime.now().millisecond % 500) / 1000,
      );
      notifyListeners();
    });
  }

  /// 添加音频数据（用于实时录音）
  void addAudioSamples(List<double> samples) {
    if (_status.isRecording) {
      _audioBuffer.addAll(samples);
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recognizer?.free();
    _recognizer = null;
    super.dispose();
  }
}
