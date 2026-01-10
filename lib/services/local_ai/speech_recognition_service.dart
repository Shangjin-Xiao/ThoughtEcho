/// 语音识别服务
///
/// 使用 sherpa_onnx + Whisper 进行设备端语音转文字

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/speech_recognition_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';
import 'model_extractor.dart';

// sherpa_onnx imports - conditional import for platform support
// ignore: depend_on_referenced_packages
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 语音识别服务
class SpeechRecognitionService extends ChangeNotifier {
  static SpeechRecognitionService? _instance;

  /// sherpa_onnx 全局初始化标记
  static bool _sherpaInitialized = false;

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
  Future<void> initialize({bool eagerLoadModel = true}) async {
    if (_initialized) return;

    try {
      // 确保模型管理器已初始化
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 启动阶段不要强制加载/解压模型，否则容易卡死或触发 OOM。
      // 模型准备会在真正开始识别时（或用户手动点击“加载/准备”）完成。
      if (eagerLoadModel && isModelAvailable) {
        await prepareModel();
      }

      _initialized = true;
      logInfo('语音识别服务初始化完成', source: 'SpeechRecognitionService');
    } catch (e) {
      logError('语音识别服务初始化失败: $e', source: 'SpeechRecognitionService');
      // 不抛出错误，允许服务继续运行（只是没有模型）
      _initialized = true;
    }
  }

  /// 准备 ASR 模型：解压（若需要）并初始化识别器。
  ///
  /// 该过程可能耗时较长，应由 UI 在用户显式触发后调用。
  Future<void> prepareModel() async {
    // 确保模型管理器已初始化
    if (!_modelManager.isInitialized) {
      await _modelManager.initialize();
    }

    if (!isModelAvailable) {
      throw Exception('asr_model_required');
    }

    // 识别器已存在则无需重复初始化
    if (_recognizer != null) return;

    await _initializeRecognizer();
    if (_recognizer == null) {
      throw Exception('asr_model_init_failed');
    }
  }

  /// 初始化 sherpa_onnx 识别器
  Future<void> _initializeRecognizer() async {
    try {
      await _ensureSherpaInitialized();

      final modelPath = _getAvailableModelPath();
      if (modelPath == null) {
        logError('无法找到可用的 ASR 模型', source: 'SpeechRecognitionService');
        return;
      }

      // 确保模型已解压
      await _ensureModelExtracted(modelPath);

      // 获取解压后的模型路径
      final extractedPath = await _getExtractedModelPath();
      if (extractedPath == null) {
        logError('无法找到解压后的 ASR 模型', source: 'SpeechRecognitionService');
        return;
      }

      // 验证 Whisper 模型文件
      final modelFiles = await ModelExtractor.validateWhisperModel(extractedPath);
      if (modelFiles == null) {
        logError('Whisper 模型文件不完整: $extractedPath', source: 'SpeechRecognitionService');
        return;
      }

      logInfo('找到 Whisper 模型文件: $modelFiles', source: 'SpeechRecognitionService');

      // 配置 Whisper 模型
      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: modelFiles.encoder,
            decoder: modelFiles.decoder,
            language: 'zh', // 中文
            task: 'transcribe',
          ),
          tokens: modelFiles.tokens,
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

  /// 确保 sherpa_onnx 已完成必要的全局初始化。
  ///
  /// 某些平台/构建模式下，未显式初始化会导致创建识别器时报：
  /// `Please initialize sherpa-onnx first`。
  Future<void> _ensureSherpaInitialized() async {
    if (_sherpaInitialized) return;

    try {
      // sherpa_onnx 1.12.x 在部分平台需要先初始化绑定/加载 native assets。
      sherpa.initBindings();
      _sherpaInitialized = true;
      logInfo('sherpa_onnx bindings 初始化完成', source: 'SpeechRecognitionService');
    } catch (e) {
      // 初始化失败不应直接阻断后续逻辑；真正创建 recognizer 时仍会抛出具体错误。
      logError('sherpa_onnx bindings 初始化失败: $e', source: 'SpeechRecognitionService');
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

  /// 确保模型已解压
  Future<void> _ensureModelExtracted(String modelPath) async {
    // 获取当前使用的模型 ID
    String? modelId;
    if (_modelManager.isModelDownloaded('whisper-base')) {
      modelId = 'whisper-base';
    } else if (_modelManager.isModelDownloaded('whisper-tiny')) {
      modelId = 'whisper-tiny';
    }
    
    if (modelId != null) {
      await _modelManager.extractModelIfNeeded(modelId);
    }
  }

  /// 获取解压后的模型路径
  Future<String?> _getExtractedModelPath() async {
    // 优先使用 whisper-base
    if (_modelManager.isModelDownloaded('whisper-base')) {
      final extractedPath = _modelManager.getExtractedModelPath('whisper-base');
      if (extractedPath != null) return extractedPath;
      // 如果没有解压记录，但模型已下载，尝试获取解压后的目录
      return _modelManager.getModelPath('whisper-base');
    }
    // 其次使用 whisper-tiny
    if (_modelManager.isModelDownloaded('whisper-tiny')) {
      final extractedPath = _modelManager.getExtractedModelPath('whisper-tiny');
      if (extractedPath != null) return extractedPath;
      return _modelManager.getModelPath('whisper-tiny');
    }
    return null;
  }

  /// 开始录音
  Future<void> startRecording() async {
    if (!_initialized) {
      throw Exception('service_not_initialized');
    }

    if (_status.isRecording) {
      logDebug('已在录制中', source: 'SpeechRecognitionService');
      return;
    }

    try {
      // 确保识别器可用（用户点击开始录音时再准备模型，避免启动阶段卡死）
      if (_recognizer == null) {
        await prepareModel();
      }

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
      } else {
        // 没有识别器：不要返回“提示文本”作为识别结果，交由 UI 进行本地化提示。
        throw Exception('asr_model_required');
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
      // record 插件的录音必须显式 stop，否则会继续占用麦克风并导致下一次录音/转写异常。
      try {
        final isRec = await _recorder.isRecording();
        if (isRec) {
          await _recorder.stop();
        }
      } catch (_) {
        // ignore: stop best-effort
      }

      // 清理临时录音文件
      final audioPath = _recordingFilePath;
      _recordingFilePath = null;
      if (audioPath != null && audioPath.isNotEmpty) {
        try {
          final f = File(audioPath);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {
          // ignore
        }
      }

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
      throw Exception('service_not_initialized');
    }

    if (_recognizer == null) {
      await prepareModel();
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
