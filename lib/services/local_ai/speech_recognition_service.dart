/// 语音识别服务
///
/// 使用 sherpa_onnx 进行设备端语音转文字，支持多种 ASR 模型架构：
/// - 离线模型 (OfflineRecognizer): Whisper, Paraformer, SenseVoice, Qwen3-ASR, FunASR-Nano
/// - 流式模型 (OnlineRecognizer):  Zipformer2 CTC, Streaming Paraformer, Streaming Zipformer Transducer
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/local_ai_model.dart';
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

  /// sherpa_onnx 识别器（OfflineRecognizer 或 OnlineRecognizer）
  dynamic _recognizer;

  /// sherpa_onnx 音频流（OfflineStream 或 OnlineStream，用于实时预览）
  dynamic _asrStream;

  /// 录音器（record 插件）
  final AudioRecorder _recorder = AudioRecorder();

  /// 当前录音文件路径（WAV）
  String? _recordingFilePath;

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

  /// 实时预览解码间隔（优化：增加到1500ms减少CPU负担和UI卡顿）
  static const Duration _partialDecodeInterval = Duration(milliseconds: 1500);

  /// 每次触发预览解码前至少新增的样本数（优化：增加到24000，约1.5秒）
  static const int _minNewSamplesForPartialDecode = 24000; // ~1.5s @16k

  /// 高核设备上的线程上限，避免占用过高导致 UI 抖动（优化：降低到4避免过多线程竞争）
  static const int _maxRecommendedThreads = 4;

  /// 录音计时器
  Timer? _recordingTimer;

  /// 当前选中的 ASR 模型 ID，默认 whisper-tiny 保证向后兼容
  String _selectedModelId = 'whisper-tiny';

  /// ASR 设置持久化文件名
  static const String _asrSettingsFileName = 'asr_settings.json';

  // ======================== Getters ========================

  /// 获取当前状态
  RecordingStatus get status => _status;

  /// 获取当前转写文本
  String get currentTranscription => _currentTranscription;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 是否正在录制
  bool get isRecording => _status.isRecording;

  /// 当前选中的 ASR 模型 ID
  String get selectedModelId => _selectedModelId;

  /// 当前模型架构类型
  AsrModelArchitecture? get currentArchitecture =>
      LocalAIModels.getAsrArchitecture(_selectedModelId);

  /// 检查 ASR 模型是否可用（当前选中模型或任意已下载的 ASR 模型）
  bool get isModelAvailable {
    // 优先检查当前选中的模型
    if (_modelManager.isModelDownloaded(_selectedModelId)) {
      return true;
    }
    // 兜底：检查任意已下载的 ASR 模型
    return LocalAIModels.byType(LocalAIModelType.asr)
        .any((m) => _modelManager.isModelDownloaded(m.id));
  }

  /// 当前模型是否为流式模型
  bool get _isStreamingModel => LocalAIModels.isStreamingAsr(_selectedModelId);

  // ======================== 初始化 ========================

  /// 初始化服务
  Future<void> initialize({bool eagerLoadModel = true}) async {
    if (_initialized) return;

    try {
      // 加载持久化的 ASR 模型选择
      await _loadSelectedModelId();

      // 确保模型管理器已初始化
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 启动阶段不要强制加载/解压模型，否则容易卡死或触发 OOM。
      // 模型准备会在真正开始识别时（或用户手动点击"加载/准备"）完成。
      if (eagerLoadModel && isModelAvailable) {
        await prepareModel();
      }

      _initialized = true;
      logInfo('语音识别服务初始化完成，模型: $_selectedModelId',
          source: 'SpeechRecognitionService');
    } catch (e) {
      logError('语音识别服务初始化失败: $e', source: 'SpeechRecognitionService');
      // 不抛出错误，允许服务继续运行（只是没有模型）
      _initialized = true;
    }
  }

  // ======================== 模型管理 ========================

  /// 准备 ASR 模型：解压（若需要）并初始化识别器。
  ///
  /// [modelId] 指定要加载的模型 ID。若为 null，使用当前选中的模型。
  /// 该过程可能耗时较长，应由 UI 在用户显式触发后调用。
  Future<void> prepareModel({String? modelId, String language = 'zh'}) async {
    // 确保模型管理器已初始化
    if (!_modelManager.isInitialized) {
      await _modelManager.initialize();
    }

    // 如果指定了模型 ID，先切换到该模型
    if (modelId != null && modelId != _selectedModelId) {
      await switchModel(modelId);
    }

    // 如果选择的模型不可用则尝试回退到任意已下载的 ASR 模型
    if (!_modelManager.isModelDownloaded(_selectedModelId)) {
      final availableAsrModels = LocalAIModels.byType(LocalAIModelType.asr)
          .where((m) => _modelManager.isModelDownloaded(m.id))
          .toList();
      if (availableAsrModels.isNotEmpty) {
        _selectedModelId = availableAsrModels.first.id;
        await _saveSelectedModelId();
        logInfo('回退到可用 ASR 模型: $_selectedModelId',
            source: 'SpeechRecognitionService');
      } else {
        throw Exception('asr_model_required');
      }
    }

    // 识别器已存在则无需重复初始化
    if (_recognizer != null) return;

    await _initializeRecognizer(language: language);
    if (_recognizer == null) {
      throw Exception('asr_model_init_failed');
    }
  }

  /// 切换到指定的 ASR 模型
  ///
  /// 会释放当前识别器并重新初始化。调用前应确保目标模型已下载。
  Future<void> switchModel(String modelId) async {
    if (modelId == _selectedModelId && _recognizer != null) {
      logDebug('模型 $_selectedModelId 已在使用中',
          source: 'SpeechRecognitionService');
      return;
    }

    // 释放当前识别器和流
    _freeRecognizer();
    _freeStream();

    _selectedModelId = modelId;
    await _saveSelectedModelId();

    // 重新初始化识别器（仅在服务已初始化且有可用模型时）
    if (_initialized && isModelAvailable) {
      await _initializeRecognizer();
    }

    notifyListeners();
    logInfo('切换 ASR 模型为: $modelId', source: 'SpeechRecognitionService');
  }

  // ======================== 识别器初始化 ========================

  /// 初始化 sherpa_onnx 识别器（根据当前选中的模型架构）
  Future<void> _initializeRecognizer({String language = 'zh'}) async {
    try {
      await _ensureSherpaInitialized();

      // 获取并确保模型已解压
      final modelPath = _getSelectedModelPath();
      if (modelPath == null) {
        logError('无法找到可用的 ASR 模型: $_selectedModelId',
            source: 'SpeechRecognitionService');
        return;
      }

      await _ensureModelExtracted();

      final extractedPath = await _getExtractedModelPath();
      if (extractedPath == null) {
        logError('无法找到解压后的 ASR 模型路径', source: 'SpeechRecognitionService');
        return;
      }

      // 根据架构类型构建识别器配置
      final config =
          await _buildRecognizerConfig(extractedPath, language: language);
      if (config == null) {
        logError('无法为 $_selectedModelId 创建识别器配置',
            source: 'SpeechRecognitionService');
        return;
      }

      // 创建对应的识别器
      if (config is sherpa.OfflineRecognizerConfig) {
        _recognizer = sherpa.OfflineRecognizer(config);
        logInfo('sherpa_onnx 离线识别器初始化成功 ($_selectedModelId)',
            source: 'SpeechRecognitionService');
      } else if (config is sherpa.OnlineRecognizerConfig) {
        _recognizer = sherpa.OnlineRecognizer(config);
        logInfo('sherpa_onnx 在线识别器初始化成功 ($_selectedModelId)',
            source: 'SpeechRecognitionService');
      } else {
        logError('未知的识别器配置类型: ${config.runtimeType}',
            source: 'SpeechRecognitionService');
      }
    } catch (e) {
      logError('初始化 sherpa_onnx 识别器失败: $e', source: 'SpeechRecognitionService');
      _recognizer = null;
    }
  }

  /// 根据模型架构构建对应的 sherpa_onnx 识别器配置
  Future<Object?> _buildRecognizerConfig(
    String extractedPath, {
    String language = 'zh',
  }) async {
    final architecture = LocalAIModels.getAsrArchitecture(_selectedModelId);
    if (architecture == null) {
      logError('未知的模型架构: $_selectedModelId',
          source: 'SpeechRecognitionService');
      return null;
    }

    // 查找 tokens 文件（所有模型都需要）
    final tokensPath = await _findFileInDir(extractedPath, 'tokens.txt');
    if (tokensPath == null) {
      logError('未找到 tokens.txt 文件', source: 'SpeechRecognitionService');
      return null;
    }

    switch (architecture) {
      // ==================== 离线模型 ====================

      case AsrModelArchitecture.whisper:
        final modelFiles =
            await ModelExtractor.validateWhisperModel(extractedPath);
        if (modelFiles == null) {
          logError('Whisper 模型文件不完整: $extractedPath',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OfflineRecognizerConfig(
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

      case AsrModelArchitecture.paraformer:
        final modelPath = await _findFileInDir(
          extractedPath,
          'model.int8.onnx',
          fallbackNames: ['model.onnx'],
        );
        if (modelPath == null) {
          logError('Paraformer 模型文件不完整（未找到 model.int8.onnx）',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            paraformer: sherpa.OfflineParaformerModelConfig(model: modelPath),
            tokens: tokensPath,
            numThreads: _recommendedThreadCount(),
            debug: false,
            modelType: 'paraformer',
          ),
        );

      case AsrModelArchitecture.senseVoice:
        final modelPath = await _findFileInDir(
          extractedPath,
          'model.int8.onnx',
          fallbackNames: ['model.onnx'],
        );
        if (modelPath == null) {
          logError('SenseVoice 模型文件不完整（未找到 model.int8.onnx）',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            senseVoice: sherpa.OfflineSenseVoiceModelConfig(
              model: modelPath,
              language: language,
              useInverseTextNormalization: true,
            ),
            tokens: tokensPath,
            numThreads: _recommendedThreadCount(),
            debug: false,
            modelType: 'sense_voice',
          ),
        );

      case AsrModelArchitecture.qwen3Asr:
        final encoderPath = await _findFileInDir(
          extractedPath,
          'encoder.int8.onnx',
          fallbackNames: ['encoder.onnx'],
        );
        final decoderPath = await _findFileInDir(
          extractedPath,
          'decoder.int8.onnx',
          fallbackNames: ['decoder.onnx'],
        );
        final convFrontendPath =
            await _findFileInDir(extractedPath, 'conv_frontend.onnx');
        final tokenizerDir = await _findDirInDir(extractedPath, 'tokenizer');
        if (encoderPath == null || decoderPath == null) {
          logError('Qwen3-ASR 模型文件不完整（缺少 encoder/decoder）',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            qwen3Asr: sherpa.OfflineQwen3AsrModelConfig(
              encoder: encoderPath,
              decoder: decoderPath,
              convFrontend: convFrontendPath ?? '',
              tokenizer: tokenizerDir ?? '',
            ),
            tokens: tokensPath,
            numThreads: _recommendedThreadCount(),
            debug: false,
            modelType: 'qwen3_asr',
          ),
        );

      case AsrModelArchitecture.funAsrNano:
        final embeddingPath = await _findFileInDir(
          extractedPath,
          'embedding.int8.onnx',
          fallbackNames: ['embedding.onnx'],
        );
        final encoderAdaptorPath = await _findFileInDir(
          extractedPath,
          'encoder_adaptor.int8.onnx',
          fallbackNames: ['encoder_adaptor.onnx'],
        );
        final llmPath = await _findFileInDir(
          extractedPath,
          'llm.int8.onnx',
          fallbackNames: ['llm.onnx'],
        );
        final tokenizerDir = await _findDirInDir(extractedPath, 'Qwen3-0.6B');
        if (embeddingPath == null ||
            encoderAdaptorPath == null ||
            llmPath == null) {
          logError('FunASR-Nano 模型文件不完整（缺少 embedding/encoder_adaptor/llm）',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            funasrNano: sherpa.OfflineFunAsrNanoModelConfig(
              encoderAdaptor: encoderAdaptorPath,
              llm: llmPath,
              embedding: embeddingPath,
              tokenizer: tokenizerDir ?? '',
            ),
            tokens: tokensPath,
            numThreads: _recommendedThreadCount(),
            debug: false,
            modelType: 'funasr_nano',
          ),
        );

      // ==================== 流式模型 ====================

      case AsrModelArchitecture.zipformer2Ctc:
        final modelPath = await _findFileInDir(
          extractedPath,
          'model.int8.onnx',
          fallbackNames: ['model.onnx'],
        );
        if (modelPath == null) {
          logError('Zipformer2 CTC 模型文件不完整（未找到 model.int8.onnx）',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            zipformer2Ctc:
                sherpa.OnlineZipformer2CtcModelConfig(model: modelPath),
            tokens: tokensPath,
            numThreads: _recommendedThreadCount(),
            debug: false,
          ),
        );

      case AsrModelArchitecture.streamingParaformer:
        final encoderPath = await _findFileInDir(
          extractedPath,
          'encoder.int8.onnx',
          fallbackNames: ['encoder.onnx'],
        );
        final decoderPath = await _findFileInDir(
          extractedPath,
          'decoder.int8.onnx',
          fallbackNames: ['decoder.onnx'],
        );
        if (encoderPath == null || decoderPath == null) {
          logError('Streaming Paraformer 模型文件不完整（缺少 encoder/decoder）',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            paraformer: sherpa.OnlineParaformerModelConfig(
              encoder: encoderPath,
              decoder: decoderPath,
            ),
            tokens: tokensPath,
            numThreads: _recommendedThreadCount(),
            debug: false,
          ),
        );

      case AsrModelArchitecture.streamingZipformer:
        final encoderPath = await _findFileInDir(
          extractedPath,
          'encoder.int8.onnx',
          fallbackNames: ['encoder.onnx'],
        );
        final decoderPath = await _findFileInDir(
          extractedPath,
          'decoder.onnx',
          fallbackNames: ['decoder.int8.onnx'],
        );
        final joinerPath = await _findFileInDir(
          extractedPath,
          'joiner.int8.onnx',
          fallbackNames: ['joiner.onnx'],
        );
        if (encoderPath == null || decoderPath == null || joinerPath == null) {
          logError('Streaming Zipformer 模型文件不完整（缺少 encoder/decoder/joiner）',
              source: 'SpeechRecognitionService');
          return null;
        }
        return sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder: encoderPath,
              decoder: decoderPath,
              joiner: joinerPath,
            ),
            tokens: tokensPath,
            numThreads: _recommendedThreadCount(),
            debug: false,
          ),
        );
    }
  }

  // ======================== 模型文件发现 ========================

  /// 在解压目录中递归查找指定文件名的文件。
  ///
  /// 优先精确匹配 [fileName]，失败时尝试 [fallbackNames]。
  /// 搜索是递归的（某些模型文件可能在子目录中）。
  Future<String?> _findFileInDir(
    String dirPath,
    String fileName, {
    List<String> fallbackNames = const [],
  }) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return null;

    final allCandidates = [fileName, ...fallbackNames];
    final lowerCandidates = allCandidates.map((n) => n.toLowerCase()).toSet();

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final name = path.basename(entity.path).toLowerCase();
        if (lowerCandidates.contains(name)) {
          return entity.path;
        }
      }
    }
    return null;
  }

  /// 在解压目录中递归查找指定名称的目录。
  Future<String?> _findDirInDir(String dirPath, String dirName) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return null;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is Directory) {
        final name = path.basename(entity.path);
        if (name == dirName || name.contains(dirName)) {
          return entity.path;
        }
      }
    }
    return null;
  }

  // ======================== 模型路径解析 ========================

  /// 根据当前选中的模型 ID 获取模型路径（优先取解压后的路径）
  String? _getSelectedModelPath() {
    if (_modelManager.isModelDownloaded(_selectedModelId)) {
      return _modelManager.getModelPath(_selectedModelId);
    }
    // 向后兼容：回退到 whisper 模型
    if (_modelManager.isModelDownloaded('whisper-tiny')) {
      _selectedModelId = 'whisper-tiny';
      return _modelManager.getModelPath('whisper-tiny');
    }
    if (_modelManager.isModelDownloaded('whisper-base')) {
      _selectedModelId = 'whisper-base';
      return _modelManager.getModelPath('whisper-base');
    }
    return null;
  }

  /// 确保当前选中的模型已解压
  Future<void> _ensureModelExtracted() async {
    if (_modelManager.isModelDownloaded(_selectedModelId)) {
      await _modelManager.extractModelIfNeeded(_selectedModelId);
      return;
    }
    // 向后兼容：回退到 whisper 模型
    if (_modelManager.isModelDownloaded('whisper-tiny')) {
      await _modelManager.extractModelIfNeeded('whisper-tiny');
    } else if (_modelManager.isModelDownloaded('whisper-base')) {
      await _modelManager.extractModelIfNeeded('whisper-base');
    }
  }

  /// 获取当前选中模型的解压后路径
  Future<String?> _getExtractedModelPath() async {
    if (_modelManager.isModelDownloaded(_selectedModelId)) {
      final extractedPath =
          _modelManager.getExtractedModelPath(_selectedModelId);
      if (extractedPath != null) return extractedPath;
      return _modelManager.getModelPath(_selectedModelId);
    }
    // 向后兼容：回退到 whisper 模型
    if (_modelManager.isModelDownloaded('whisper-tiny')) {
      final extractedPath = _modelManager.getExtractedModelPath('whisper-tiny');
      if (extractedPath != null) return extractedPath;
      return _modelManager.getModelPath('whisper-tiny');
    }
    if (_modelManager.isModelDownloaded('whisper-base')) {
      final extractedPath = _modelManager.getExtractedModelPath('whisper-base');
      if (extractedPath != null) return extractedPath;
      return _modelManager.getModelPath('whisper-base');
    }
    return null;
  }

  // ======================== 设置持久化 ========================

  /// 将当前选中的模型 ID 保存到本地文件
  Future<void> _saveSelectedModelId() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(path.join(dir.path, _asrSettingsFileName));
      await file.writeAsString(
        json.encode({'selectedModelId': _selectedModelId}),
      );
      logDebug('ASR 模型设置已保存: $_selectedModelId',
          source: 'SpeechRecognitionService');
    } catch (e) {
      logError('保存 ASR 模型设置失败: $e', source: 'SpeechRecognitionService');
    }
  }

  /// 从本地文件加载之前选中的模型 ID
  Future<void> _loadSelectedModelId() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(path.join(dir.path, _asrSettingsFileName));
      if (await file.exists()) {
        final data =
            json.decode(await file.readAsString()) as Map<String, dynamic>;
        final savedId = data['selectedModelId'] as String?;
        if (savedId != null && savedId.isNotEmpty) {
          _selectedModelId = savedId;
          logInfo('加载 ASR 模型设置: $_selectedModelId',
              source: 'SpeechRecognitionService');
        }
      }
    } catch (e) {
      logError('加载 ASR 模型设置失败: $e', source: 'SpeechRecognitionService');
    }
  }

  // ======================== 录音 ========================

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

      // 交互目标：按住期间实时显示"转写预览"（类似微信/键盘）。
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
      _freeStream();

      _currentTranscription = '';

      if (_useStreamRecording && _recognizer != null) {
        // 根据模型类型创建对应的音频流
        if (_isStreamingModel) {
          _asrStream = (_recognizer as sherpa.OnlineRecognizer).createStream();
        } else {
          _asrStream = (_recognizer as sherpa.OfflineRecognizer).createStream();
        }

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

      logInfo('开始录音（模型: $_selectedModelId）',
          source: 'SpeechRecognitionService');
    } catch (e) {
      // 清理录音资源，避免计时器/流悬空
      _cleanupRecording();
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

    String? cleanupRecordingPath;
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
          transcribedText = await _finishStreamTranscription();
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

      cleanupRecordingPath = _recordingFilePath;
      _recordingFilePath = null;

      // 释放 asr stream
      _freeStream();

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
    } finally {
      _recordingTimer?.cancel();
      _partialDecodeTimer?.cancel();
      _partialDecodeTimer = null;
      try {
        await _audioStreamSub?.cancel();
      } catch (_) {}
      _audioStreamSub = null;
      _freeStream();

      cleanupRecordingPath ??= _recordingFilePath;
      final pathToDelete = cleanupRecordingPath;
      if (pathToDelete != null && pathToDelete.isNotEmpty) {
        try {
          final file = File(pathToDelete);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      _recordingFilePath = null;
    }
  }

  /// 完成流式转写：根据模型类型执行最终解码
  Future<String> _finishStreamTranscription() async {
    if (_isStreamingModel) {
      final recognizer = _recognizer as sherpa.OnlineRecognizer;
      final stream = _asrStream as sherpa.OnlineStream;

      // 标记音频输入结束
      stream.inputFinished();

      // 循环解码直到完成
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }

      final result = recognizer.getResult(stream);

      // 检查并重置端点
      if (recognizer.isEndpoint(stream)) {
        recognizer.reset(stream);
      }

      return result.text;
    } else {
      final recognizer = _recognizer as sherpa.OfflineRecognizer;
      final stream = _asrStream as sherpa.OfflineStream;

      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      return result.text;
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

      _freeStream();

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
      _useStreamRecording = false;
      notifyListeners();

      logInfo('取消录音', source: 'SpeechRecognitionService');
    } catch (e) {
      logError('取消录音失败: $e', source: 'SpeechRecognitionService');
    }
  }

  // ======================== 文件转写 ========================

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

  /// 使用 sherpa_onnx 转写音频样本
  Future<String> _transcribeAudio(List<double> samples) async {
    if (_recognizer == null) {
      return '';
    }

    try {
      if (_isStreamingModel) {
        final recognizer = _recognizer as sherpa.OnlineRecognizer;
        final stream = recognizer.createStream();
        stream.acceptWaveform(
          samples: Float32List.fromList(samples),
          sampleRate: 16000,
        );
        stream.inputFinished();

        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }

        final result = recognizer.getResult(stream);
        stream.free();
        return result.text;
      } else {
        final recognizer = _recognizer as sherpa.OfflineRecognizer;
        final stream = recognizer.createStream();
        stream.acceptWaveform(
          samples: Float32List.fromList(samples),
          sampleRate: 16000,
        );
        recognizer.decode(stream);

        final result = recognizer.getResult(stream);
        stream.free();

        return result.text;
      }
    } catch (e) {
      logError('sherpa_onnx 转写失败: $e', source: 'SpeechRecognitionService');
      return '';
    }
  }

  // ======================== 实时预览解码 ========================

  /// 尝试做一次"实时预览"解码（节流 + 防重入）。
  void _tryPartialDecode() {
    if (!_status.isRecording) return;
    if (_recognizer == null || _asrStream == null) return;
    if (_partialDecodeInProgress) return;
    if (_samplesSinceLastDecode < _minNewSamplesForPartialDecode) return;

    _partialDecodeInProgress = true;
    _samplesSinceLastDecode = 0;

    try {
      String text;

      if (_isStreamingModel) {
        final recognizer = _recognizer as sherpa.OnlineRecognizer;
        final stream = _asrStream as sherpa.OnlineStream;

        // 流式模型需要先检查是否 ready
        if (!recognizer.isReady(stream)) {
          text = _currentTranscription;
        } else {
          recognizer.decode(stream);
          final result = recognizer.getResult(stream);
          text = result.text;
        }
      } else {
        final recognizer = _recognizer as sherpa.OfflineRecognizer;
        final stream = _asrStream as sherpa.OfflineStream;

        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        text = result.text;
      }

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

  // ======================== 音频解码 ========================

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
      throw Exception(
          'wav_unsupported_samplerate:expected_16000_got_$sampleRate');
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

  // ======================== 资源管理 ========================

  /// 释放当前 _asrStream（兼容 OfflineStream 和 OnlineStream）
  void _freeStream() {
    try {
      _asrStream?.free();
    } catch (_) {}
    _asrStream = null;
  }

  /// 释放当前 _recognizer（兼容 OfflineRecognizer 和 OnlineRecognizer）
  void _freeRecognizer() {
    try {
      _recognizer?.free();
    } catch (_) {}
    _recognizer = null;
  }

  /// 清理录音中的各种资源
  void _cleanupRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _partialDecodeTimer?.cancel();
    _partialDecodeTimer = null;
    try {
      _audioStreamSub?.cancel();
    } catch (_) {}
    _audioStreamSub = null;
    _freeStream();
    _useStreamRecording = false;
    _samplesSinceLastDecode = 0;
    _partialDecodeInProgress = false;
  }

  /// 重置状态
  void reset() {
    _cleanupRecording();
    _status = RecordingStatus.idle;
    _currentTranscription = '';
    notifyListeners();
  }

  // ======================== 辅助方法 ========================

  /// 根据设备 CPU 动态设置线程数，兼顾速度和稳定性
  /// 优化：更保守的线程分配策略，避免UI线程竞争
  int _recommendedThreadCount() {
    final cores = Platform.numberOfProcessors;
    // 低核设备（≤4核）使用2线程，高核设备最多4线程
    if (cores <= 4) {
      return 2;
    } else if (cores <= 8) {
      return 3;
    } else {
      return 4;
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
      logError('sherpa_onnx bindings 初始化失败: $e',
          source: 'SpeechRecognitionService');
    }
  }

  /// 开始录音计时器（优化：减少更新频率到500ms降低UI负担）
  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_status.isRecording) {
        timer.cancel();
        return;
      }

      // 更新录制时长
      // 注：音量级别基于时间模拟平滑波形，真实音量需要从音频流中计算
      final timeFactor = _status.durationSeconds * 3.14;
      final simulatedVolume = 0.3 + 0.2 * (0.5 + 0.5 * math.sin(timeFactor));
      _status = _status.copyWith(
        durationSeconds: _status.durationSeconds + 0.5,
        volumeLevel: simulatedVolume.clamp(0.0, 1.0),
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _partialDecodeTimer?.cancel();
    try {
      _audioStreamSub?.cancel();
    } catch (_) {}
    _audioStreamSub = null;
    _freeStream();
    _recorder.dispose();
    _freeRecognizer();
    super.dispose();
  }
}
