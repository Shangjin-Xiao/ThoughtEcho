/// 语音识别服务
///
/// 使用 sherpa_onnx + Whisper 进行设备端语音转文字
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

  /// sherpa_onnx 离线识别流（用于“实时预览”与最终结果）
  sherpa.OfflineStream? _asrStream;

  /// 录音器（record 插件）
  final AudioRecorder _recorder = AudioRecorder();

  /// 当前录音文件路径（WAV）
  String? _recordingFilePath;

  /// 音频缓冲
  final List<double> _audioBuffer = [];

  /// 是否使用流式录音（移动端用 PCM stream，可做实时预览）
  bool _useStreamRecording = false;

  /// 流式录音订阅
  StreamSubscription<Uint8List>? _audioStreamSub;

  /// 实时预览解码定时器
  Timer? _partialDecodeTimer;

  /// 最近一次解码时的样本计数（用于节流）
  int _samplesSinceLastDecode = 0;

  /// 是否正在做一次预览解码（避免重入）
  bool _partialDecodeInProgress = false;

  /// 实时预览解码间隔（越小越实时，但越吃 CPU）
  static const Duration _partialDecodeInterval = Duration(milliseconds: 900);

  /// 每次触发预览解码前至少新增的样本数（避免过于频繁）
  static const int _minNewSamplesForPartialDecode = 16000; // ~1s @16k

  /// 高核设备上的线程上限，避免占用过高导致 UI 抖动
  static const int _maxRecommendedThreads = 6;

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
  Future<void> prepareModel({String language = 'zh'}) async {
    // 确保模型管理器已初始化
    if (!_modelManager.isInitialized) {
      await _modelManager.initialize();
    }

    if (!isModelAvailable) {
      throw Exception('asr_model_required');
    }

    // 识别器已存在则无需重复初始化
    // TODO: 如果需要切换语言，可能需要重新初始化
    if (_recognizer != null) return;

    await _initializeRecognizer(language: language);
    if (_recognizer == null) {
      throw Exception('asr_model_init_failed');
    }
  }

  /// 初始化 sherpa_onnx 识别器
  Future<void> _initializeRecognizer({String language = 'zh'}) async {
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
      final modelFiles =
          await ModelExtractor.validateWhisperModel(extractedPath);
      if (modelFiles == null) {
        logError('Whisper 模型文件不完整: $extractedPath',
            source: 'SpeechRecognitionService');
        return;
      }

      logInfo('找到 Whisper 模型文件: $modelFiles',
          source: 'SpeechRecognitionService');

      // 配置 Whisper 模型
      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: modelFiles.encoder,
            decoder: modelFiles.decoder,
            language: language,
            task: 'transcribe',
          ),
          tokens: modelFiles.tokens,
          numThreads: _recommendedThreadCount(),
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

  /// 根据设备 CPU 动态设置线程数，兼顾速度和稳定性
  int _recommendedThreadCount() {
    final cores = Platform.numberOfProcessors;
    return math.max(1, math.min(cores ~/ 2, _maxRecommendedThreads));
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
      logError('sherpa_onnx bindings 初始化失败: $e',
          source: 'SpeechRecognitionService');
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

      // 交互目标：按住期间实时显示“转写预览”（类似微信/键盘）。
      // 因此移动端优先使用 PCM stream 录音：边录边喂给 sherpa_onnx。
      // 桌面端/不支持 stream 时回退到 WAV 文件录制。
      _useStreamRecording = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);

      // 重置流/缓冲
      _audioStreamSub?.cancel();
      _audioStreamSub = null;
      _partialDecodeTimer?.cancel();
      _partialDecodeTimer = null;
      _samplesSinceLastDecode = 0;
      _partialDecodeInProgress = false;
      _asrStream?.free();
      _asrStream = null;

      _audioBuffer.clear();
      _currentTranscription = '';

      if (_useStreamRecording && _recognizer != null) {
        _asrStream = _recognizer!.createStream();

        // 启动流式录音
        final stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );

        _audioStreamSub = stream.listen(
          (bytes) {
            // PCM16LE mono -> float samples
            final samples = _decodePcm16LeMonoToFloat32(bytes);
            if (samples.isEmpty) return;

            // 喂给 sherpa 的 stream
            final s = _asrStream;
            if (s != null) {
              s.acceptWaveform(
                samples: Float32List.fromList(samples),
                sampleRate: 16000,
              );
            }

            _samplesSinceLastDecode += samples.length;
          },
          onError: (e) {
            logError('录音流出错: $e', source: 'SpeechRecognitionService');
          },
          cancelOnError: false,
        );

        // 定时做一次增量 decode，更新 currentTranscription
        _partialDecodeTimer =
            Timer.periodic(_partialDecodeInterval, (_) => _tryPartialDecode());
      } else {
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
      }

      _status = const RecordingStatus(state: RecordingState.recording);
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
      _partialDecodeTimer?.cancel();
      _partialDecodeTimer = null;
      _status = _status.copyWith(state: RecordingState.processing);
      notifyListeners();

      String transcribedText = '';

      // 先停止录音
      try {
        await _audioStreamSub?.cancel();
      } catch (_) {}
      _audioStreamSub = null;

      String? audioPath;
      if (_useStreamRecording) {
        // stream 模式：stop 仅为释放麦克风
        try {
          await _recorder.stop();
        } catch (_) {
          // ignore
        }
      } else {
        // 文件模式：stop 返回最终文件路径（某些平台也可能返回 null）
        final recordedPath = await _recorder.stop();
        audioPath = recordedPath ?? _recordingFilePath;
      }

      if (_recognizer == null) {
        throw Exception('asr_model_required');
      }

      // 若使用流式录音：最终结果也从同一个 asrStream 获取
      if (_useStreamRecording && _asrStream != null) {
        try {
          _recognizer!.decode(_asrStream!);
          final result = _recognizer!.getResult(_asrStream!);
          transcribedText = result.text;
        } catch (e) {
          logError('最终转写失败(流式): $e', source: 'SpeechRecognitionService');
          transcribedText = '';
        }
      } else {
        // WAV 文件路径转写
        if (audioPath != null && audioPath.isNotEmpty) {
          final samples = await _decodeAudioFile(audioPath);
          transcribedText =
              samples.isNotEmpty ? await _transcribeAudio(samples) : '';
        }
      }

      final result = SpeechRecognitionResult(
        text: transcribedText,
        isFinal: true,
        timestamp: DateTime.now(),
      );

      _status = const RecordingStatus(state: RecordingState.completed);
      _currentTranscription = transcribedText;
      notifyListeners();

      _recordingFilePath = null;

      // 释放 asr stream
      try {
        _asrStream?.free();
      } catch (_) {}
      _asrStream = null;

      logInfo('转写完成: ${transcribedText.length} 字符',
          source: 'SpeechRecognitionService');
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
    // 即使状态不是 recording，也要清理可能残留的资源

    try {
      // 1. 优先停止 record 插件，防止麦克风锁定
      try {
        final isRec = await _recorder.isRecording();
        if (isRec) {
          await _recorder.stop();
        }
      } catch (e) {
        logError('停止录音器失败 (cancel): $e', source: 'SpeechRecognitionService');
      }

      // 2. 清理定时器和流
      _partialDecodeTimer?.cancel();
      _partialDecodeTimer = null;

      try {
        await _audioStreamSub?.cancel();
      } catch (_) {}
      _audioStreamSub = null;

      try {
        _asrStream?.free();
      } catch (_) {}
      _asrStream = null;

      // 3. 清理临时文件
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
      _useStreamRecording = false;
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

    String fourCC(int offset) {
      return String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
    }

    if (fourCC(0) != 'RIFF' || fourCC(8) != 'WAVE') {
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
      final id = fourCC(offset);
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
      logInfo('WAV 采样率为 $sampleRate，建议使用 16000Hz',
          source: 'SpeechRecognitionService');
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
    _partialDecodeTimer?.cancel();
    _partialDecodeTimer = null;
    try {
      _audioStreamSub?.cancel();
    } catch (_) {}
    _audioStreamSub = null;
    try {
      _asrStream?.free();
    } catch (_) {}
    _asrStream = null;
    _useStreamRecording = false;
    _samplesSinceLastDecode = 0;
    _partialDecodeInProgress = false;
    _status = RecordingStatus.idle;
    _currentTranscription = '';
    _audioBuffer.clear();
    notifyListeners();
  }

  /// 尝试做一次“实时预览”解码（节流 + 防重入）。
  void _tryPartialDecode() {
    if (!_status.isRecording) return;
    if (_recognizer == null || _asrStream == null) return;
    if (_partialDecodeInProgress) return;
    if (_samplesSinceLastDecode < _minNewSamplesForPartialDecode) return;

    _partialDecodeInProgress = true;
    _samplesSinceLastDecode = 0;

    try {
      _recognizer!.decode(_asrStream!);
      final result = _recognizer!.getResult(_asrStream!);
      final text = result.text;
      if (text != _currentTranscription) {
        _currentTranscription = text;
        notifyListeners();
      }
    } catch (e) {
      // 预览失败不影响最终 stop+transcribe
      logDebug('预览转写失败(忽略): $e', source: 'SpeechRecognitionService');
    } finally {
      _partialDecodeInProgress = false;
    }
  }

  /// PCM16LE mono -> Float32 samples (-1..1)
  List<double> _decodePcm16LeMonoToFloat32(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty) return const [];
    final byteLen = pcmBytes.lengthInBytes;
    if (byteLen < 2) return const [];

    final bd = ByteData.sublistView(pcmBytes);
    final sampleCount = byteLen ~/ 2;
    final samples = List<double>.filled(sampleCount, 0.0, growable: false);
    int p = 0;
    for (int i = 0; i < sampleCount; i++) {
      final s = bd.getInt16(p, Endian.little);
      samples[i] = s / 32768.0;
      p += 2;
    }
    return samples;
  }

  /// 开始录音计时器
  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!_status.isRecording) {
        timer.cancel();
        return;
      }

      // 更新录制时长
      // 注：音量级别基于时间模拟平滑波形，真实音量需要从音频流中计算
      final timeFactor = _status.durationSeconds * 3.14;
      final simulatedVolume = 0.3 + 0.2 * (0.5 + 0.5 * _sin(timeFactor));
      _status = _status.copyWith(
        durationSeconds: _status.durationSeconds + 0.3,
        volumeLevel: simulatedVolume.clamp(0.0, 1.0),
      );
      notifyListeners();
    });
  }

  /// 简易正弦函数近似（避免 import dart:math）
  static double _sin(double x) {
    // Normalize to -PI..PI
    x = x % (2 * 3.14159265);
    if (x > 3.14159265) x -= 2 * 3.14159265;
    // Taylor series approximation
    final x3 = x * x * x;
    final x5 = x3 * x * x;
    return x - x3 / 6.0 + x5 / 120.0;
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _partialDecodeTimer?.cancel();
    try {
      _audioStreamSub?.cancel();
    } catch (_) {}
    _audioStreamSub = null;
    try {
      _asrStream?.free();
    } catch (_) {}
    _asrStream = null;
    _recorder.dispose();
    _recognizer?.free();
    _recognizer = null;
    super.dispose();
  }
}
