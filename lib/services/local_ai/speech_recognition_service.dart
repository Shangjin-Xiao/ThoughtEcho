/// 语音识别服务
///
/// 使用 sherpa_onnx + Whisper 进行设备端语音转文字

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:record/record.dart';

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

  /// 录音器（record 插件）
  final AudioRecorder _recorder = AudioRecorder();

  /// 当前录音文件路径（WAV）
  String? _recordingFilePath;

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
      // 权限检查
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw Exception('record_permission_denied');
      }

      // 录制为 16kHz 单声道 WAV，便于直接喂给 sherpa_onnx
      final tempDir = await getTemporaryDirectory();
      _recordingFilePath = path.join(
        tempDir.path,
        'local_asr_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _recordingFilePath!,
      );

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

      // 先停止录音，拿到文件路径
      final recordedPath = await _recorder.stop();
      final audioPath = recordedPath ?? _recordingFilePath;

      String transcribedText = '';

      if (_recognizer != null) {
        // 优先使用录音文件（WAV）进行转写
        if (audioPath != null && audioPath.isNotEmpty) {
          final samples = await _decodeAudioFile(audioPath);
          transcribedText = samples.isNotEmpty ? await _transcribeAudio(samples) : '';
        } else if (_audioBuffer.isNotEmpty) {
          // 兼容旧路径：如果外部注入了 waveform（例如未来接入流式采样）
          transcribedText = await _transcribeAudio(_audioBuffer);
        }
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

      _recordingFilePath = null;

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
    // 当前实现仅支持 record 输出的 WAV(PCM16, 16kHz, mono)
    final file = File(audioPath);
    final bytes = await file.readAsBytes();
    return _decodeWavPcm16MonoToFloat32(bytes);
  }

  /// 解码 WAV(PCM16, mono) 为 Float32 waveform。
  ///
  /// - 仅支持 little-endian RIFF/WAVE
  /// - 仅支持 16-bit PCM
  /// - 支持任意 sampleRate，但 sherpa_onnx 通常要求 16000Hz（不做重采样）
  List<double> _decodeWavPcm16MonoToFloat32(Uint8List wavBytes) {
    if (wavBytes.lengthInBytes < 44) {
      throw Exception('wav_too_short');
    }

    String _fourCC(int offset) {
      return String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
    }

    if (_fourCC(0) != 'RIFF' || _fourCC(8) != 'WAVE') {
      throw Exception('wav_invalid_header');
    }

    final bd = ByteData.sublistView(wavBytes);

    int? numChannels;
    int? sampleRate;
    int? bitsPerSample;
    int? audioFormat;
    int dataOffset = -1;
    int dataSize = -1;

    // chunk scan from 12
    int offset = 12;
    while (offset + 8 <= wavBytes.lengthInBytes) {
      final id = _fourCC(offset);
      final size = bd.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;

      if (id == 'fmt ') {
        audioFormat = bd.getUint16(chunkDataStart, Endian.little);
        numChannels = bd.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = bd.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = bd.getUint16(chunkDataStart + 14, Endian.little);
      } else if (id == 'data') {
        dataOffset = chunkDataStart;
        dataSize = size;
        break;
      }

      // chunks are word-aligned
      offset = chunkDataStart + size;
      if (offset.isOdd) offset += 1;
    }

    if (dataOffset < 0 || dataSize <= 0) {
      throw Exception('wav_missing_data');
    }
    if (audioFormat != 1) {
      // 1 = PCM
      throw Exception('wav_unsupported_format:$audioFormat');
    }
    if (numChannels != 1) {
      throw Exception('wav_unsupported_channels:$numChannels');
    }
    if (bitsPerSample != 16) {
      throw Exception('wav_unsupported_bps:$bitsPerSample');
    }
    if (sampleRate != 16000) {
      // 不做重采样，避免引入额外依赖；用日志提示即可
      logInfo('WAV 采样率为 $sampleRate，建议使用 16000Hz', source: 'SpeechRecognitionService');
    }

    final bytesPerSample = (bitsPerSample! ~/ 8);
    final sampleCount = dataSize ~/ bytesPerSample;

    final samples = List<double>.filled(sampleCount, 0.0, growable: false);
    int p = dataOffset;
    for (int i = 0; i < sampleCount; i++) {
      final s = bd.getInt16(p, Endian.little);
      samples[i] = s / 32768.0;
      p += 2;
    }
    return samples;
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
    _recorder.dispose();
    _recognizer?.free();
    _recognizer = null;
    super.dispose();
  }
}
