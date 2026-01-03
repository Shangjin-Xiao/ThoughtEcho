import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../utils/app_logger.dart';
import 'asr_types.dart';

/// 语音转文字服务（端侧 ASR）
///
/// - 使用 sherpa_onnx（离线 Whisper）进行识别
/// - 首次使用自动下载并解压模型文件到应用目录
/// - 使用 record 录制 16k/mono wav
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

  sherpa_onnx.OfflineRecognizer? _recognizer;
  bool _bindingsInited = false;

  final AudioRecorder _recorder = AudioRecorder();
  String? _lastRecordingPath;

  Future<void>? _initializingFuture;

  /// 初始化 ASR 服务（会触发模型下载/解压和识别器创建）
  Future<void> initialize([ASRModelConfig? config]) async {
    config ??= ASRModels.whisperTiny;

    if (_isInitialized && _currentConfig?.modelId == config.modelId) {
      return;
    }

    // 去重：避免并发初始化导致重复下载/创建
    if (_initializingFuture != null) {
      return _initializingFuture!;
    }

    _initializingFuture = _initializeInternal(config);
    try {
      await _initializingFuture;
    } finally {
      _initializingFuture = null;
    }
  }

  Future<void> _initializeInternal(ASRModelConfig config) async {
    try {
      logInfo('正在初始化 ASR 服务: ${config.modelId}', source: 'ASRService');

      if (kIsWeb) {
        throw UnsupportedError('Web 平台不支持本地 ASR');
      }

      if (config.type != ASRModelType.whisper) {
        throw UnsupportedError('当前仅接入 Whisper 离线 ASR');
      }

      if (!config.hasWhisperBundleInfo) {
        throw StateError('ASR 模型配置缺少下载/文件信息');
      }

      await _ensureWhisperModelReady(config);

      if (!_bindingsInited) {
        sherpa_onnx.initBindings();
        _bindingsInited = true;
      }

      _recognizer?.free();
      _recognizer = null;

      final modelDir = await _getModelDirectory(config);
      final encoderPath = p.join(modelDir.path, config.whisperEncoderFile!);
      final decoderPath = p.join(modelDir.path, config.whisperDecoderFile!);
      final tokensPath = p.join(modelDir.path, config.tokensFile!);

      final whisper = sherpa_onnx.OfflineWhisperModelConfig(
        encoder: encoderPath,
        decoder: decoderPath,
        language: config.language == 'auto' ? '' : config.language,
        task: 'transcribe',
        tailPaddings: config.tailPaddings,
      );

      final modelConfig = sherpa_onnx.OfflineModelConfig(
        whisper: whisper,
        tokens: tokensPath,
        modelType: 'whisper',
        debug: false,
        numThreads: 1,
        provider: 'cpu',
      );

      final recognizerConfig = sherpa_onnx.OfflineRecognizerConfig(
        feat: sherpa_onnx.FeatureConfig(
          sampleRate: config.sampleRate,
          featureDim: 80,
        ),
        model: modelConfig,
      );

      _recognizer = sherpa_onnx.OfflineRecognizer(recognizerConfig);

      _currentConfig = config;
      _isInitialized = true;
      notifyListeners();

      logInfo('ASR 服务初始化成功', source: 'ASRService');
    } catch (e, s) {
      logError(
        'ASR 服务初始化失败: $e',
        error: e,
        stackTrace: s,
        source: 'ASRService',
      );
      rethrow;
    }
  }

  /// 从音频文件识别（要求为单声道 16-bit PCM WAV）
  Future<ASRResult> recognizeFile(String filePath) async {
    if (!_isInitialized || _recognizer == null || _currentConfig == null) {
      throw StateError('ASR 服务未初始化');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('音频文件不存在', filePath);
    }

    final stopwatch = Stopwatch()..start();

    try {
      final waveData = sherpa_onnx.readWave(filePath);
      if (waveData.samples.isEmpty) {
        throw StateError('音频样本为空');
      }

      if (waveData.sampleRate != _currentConfig!.sampleRate) {
        throw StateError(
          '仅支持 ${_currentConfig!.sampleRate}Hz 音频，当前为 ${waveData.sampleRate}Hz',
        );
      }

      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: waveData.samples, sampleRate: waveData.sampleRate);

      // 离线识别：一次性 decode 即可
      _recognizer!.decode(stream);

      final result = _recognizer!.getResult(stream);
      stream.free();

      stopwatch.stop();

      final audioDurationMs =
          (waveData.samples.length / waveData.sampleRate * 1000).round();

      return ASRResult(
        text: result.text.trim(),
        confidence: 1.0,
        processingTimeMs: stopwatch.elapsedMilliseconds,
        audioDurationMs: audioDurationMs,
        isFinal: true,
      );
    } catch (e, s) {
      stopwatch.stop();
      logError(
        '语音识别失败: $e',
        error: e,
        stackTrace: s,
        source: 'ASRService',
      );
      rethrow;
    }
  }

  /// 从音频数据识别（当前未提供通用 PCM -> WAV 转换，保留接口）
  Future<ASRResult> recognizeAudioData(
    List<int> audioData, {
    int sampleRate = 16000,
  }) async {
    throw UnsupportedError('当前仅支持从 WAV 文件识别');
  }

  /// 开始录音（用于“按住说话/松开识别”的 UI）
  Future<void> startRealtimeRecognition() async {
    if (!_isInitialized || _currentConfig == null) {
      throw StateError('ASR 服务未初始化');
    }

    if (_isRecording) {
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('麦克风权限未授予');
    }

    final tmpDir = await getTemporaryDirectory();
    final fileName = 'asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    final filePath = p.join(tmpDir.path, fileName);

    _lastRecordingPath = filePath;

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: _currentConfig!.sampleRate,
        numChannels: 1,
      ),
      path: filePath,
    );

    _isRecording = true;
    notifyListeners();
  }

  /// 停止录音并返回最终识别结果
  Future<ASRResult?> stopRealtimeRecognition() async {
    if (!_isRecording) return null;

    _isRecording = false;
    notifyListeners();

    String? path;
    try {
      path = await _recorder.stop();
    } catch (e, s) {
      logError('停止录音失败: $e', error: e, stackTrace: s, source: 'ASRService');
      rethrow;
    }

    // record.stop 可能返回 null（例如录音被系统打断）
    path ??= _lastRecordingPath;
    if (path == null) return null;

    final result = await recognizeFile(path);

    // 尽量清理临时文件，避免堆积
    unawaited(_tryDeleteFile(path));

    return result;
  }

  /// 取消录音（例如用户上滑进入 OCR 或点击空白关闭浮层）
  Future<void> cancelRealtimeRecognition() async {
    if (!_isRecording) return;

    _isRecording = false;
    notifyListeners();

    try {
      await _recorder.cancel();
    } catch (_) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }

    final path = _lastRecordingPath;
    if (path != null) {
      unawaited(_tryDeleteFile(path));
    }
  }

  List<String> getSupportedLanguages() {
    switch (_currentConfig?.type) {
      case ASRModelType.whisper:
        return ['auto', 'en', 'zh', 'ja', 'ko', 'de', 'fr', 'es', 'pt', 'ru'];
      case ASRModelType.paraformer:
        return ['zh'];
      case ASRModelType.zipformer:
        return ['en', 'zh'];
      default:
        return [];
    }
  }

  Future<void> _tryDeleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      logDebug('删除临时录音文件失败: $e', source: 'ASRService');
    }
  }

  Future<Directory> _getAsrRootDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'local_ai', 'asr'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getModelDirectory(ASRModelConfig config) async {
    final root = await _getAsrRootDirectory();
    return Directory(p.join(root.path, 'models', config.extractedDirName!));
  }

  Future<void> _ensureWhisperModelReady(ASRModelConfig config) async {
    final modelDir = await _getModelDirectory(config);

    final encoderPath = p.join(modelDir.path, config.whisperEncoderFile!);
    final decoderPath = p.join(modelDir.path, config.whisperDecoderFile!);
    final tokensPath = p.join(modelDir.path, config.tokensFile!);

    final ready = await File(encoderPath).exists() &&
        await File(decoderPath).exists() &&
        await File(tokensPath).exists();

    if (ready) return;

    final asrRoot = await _getAsrRootDirectory();
    final modelsRoot = Directory(p.join(asrRoot.path, 'models'));
    if (!await modelsRoot.exists()) {
      await modelsRoot.create(recursive: true);
    }

    final archiveFile = File(
      p.join(modelsRoot.path, '${config.modelId}.tar.bz2'),
    );

    // 下载
    logInfo('开始下载 ASR 模型: ${config.modelId}', source: 'ASRService');
    await _downloadFile(
      url: config.archiveUrl!,
      saveTo: archiveFile,
    );

    // 解压
    logInfo('开始解压 ASR 模型: ${config.modelId}', source: 'ASRService');
    await _extractTarBz2(
      archiveFile: archiveFile,
      outputDir: modelsRoot,
    );

    // 清理压缩包
    try {
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
    } catch (_) {}

    // 复验
    final ok = await File(encoderPath).exists() &&
        await File(decoderPath).exists() &&
        await File(tokensPath).exists();

    if (!ok) {
      throw StateError('模型解压后缺少必要文件，请重试下载');
    }
  }

  Future<void> _downloadFile({
    required String url,
    required File saveTo,
  }) async {
    final dio = Dio();
    if (await saveTo.exists()) {
      await saveTo.delete();
    }

    await dio.download(
      url,
      saveTo.path,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
  }

  Future<void> _extractTarBz2({
    required File archiveFile,
    required Directory outputDir,
  }) async {
    final bytes = await archiveFile.readAsBytes();

    // 说明：这里会将 tar.bz2 解压到内存中再展开文件。
    // 对于 tiny 级别模型通常可接受；若后续引入更大模型，可再优化为流式解压。
    final tarBytes = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);

    // 写入磁盘
    extractArchiveToDisk(archive, outputDir.path);
  }

  @override
  void dispose() {
    _resultController.close();

    _recognizer?.free();
    _recognizer = null;

    unawaited(_recorder.dispose());

    // 录音资源由插件管理；这里只做状态复位
    _isInitialized = false;
    _isRecording = false;

    super.dispose();
  }
}
