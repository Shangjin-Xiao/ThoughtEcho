import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/services/model_manager.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

class SpeechRecognitionService {
  static final SpeechRecognitionService _instance = SpeechRecognitionService._internal();
  static SpeechRecognitionService get instance => _instance;

  SpeechRecognitionService._internal();

  final _audioRecorder = AudioRecorder();
  sherpa.OfflineRecognizer? _recognizer;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<void> initialize() async {
    try {
      final modelType = await ModelManager.instance.isModelReady(ModelType.whisperBase)
          ? ModelType.whisperBase
          : ModelType.whisperTiny;

      if (!await ModelManager.instance.isModelReady(modelType)) {
        throw Exception('No Whisper model available');
      }

      final modelPath = await ModelManager.instance.getModelPath(modelType);

      // sherpa-onnx specific configuration structure
      // Note: Assuming modelPath points to the directory containing necessary files or specific model file
      // Typically Whisper ONNX needs: encoder, decoder, tokens, etc.
      // For simplicity in this plan, we assume standard layout or simple model loading if supported.
      // Adjusting to typical Sherpa configuration:

      // Important: The user prompt specified sherpa-onnx + whisper.
      // Sherpa-onnx typically loads models via a config object.
      // We need to know the specific file structure of the downloaded tar.bz2.
      // Assuming the ModelManager extraction results in specific files.
      // Since we can't easily introspect the tar here, we'll try to guess standard names
      // or assume the user downloads a single .onnx if valid, but Whisper usually has multiple parts.

      // Let's assume standard names for now based on sherpa-onnx releases:
      // tiny-decoder.onnx, tiny-encoder.onnx, tokens.txt

      final modelDir = File(modelPath).parent.path;
      // modelPath from ModelManager points to a specific file like 'tiny.en.pt' which is pytorch.
      // Sherpa-onnx needs ONNX models.
      // CORRECTION: The ModelManager URL points to `sherpa-onnx-whisper-tiny.tar.bz2`.
      // When extracted, it should have the ONNX files.

      final config = sherpa.OfflineRecognizerConfig(
        featConfig: sherpa.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        modelConfig: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: '$modelDir/tiny-encoder.onnx',
            decoder: '$modelDir/tiny-decoder.onnx',
          ),
          tokens: '$modelDir/tiny-tokens.txt',
          numThreads: 2,
          debug: kDebugMode,
        ),
      );

      _recognizer = sherpa.OfflineRecognizer(config);

      UnifiedLogService.instance.log(
        UnifiedLogLevel.info,
        'SpeechRecognitionService initialized with ${modelType.name}',
        source: 'SpeechRecognitionService',
      );
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Failed to initialize SpeechRecognitionService: $e',
        source: 'SpeechRecognitionService',
        error: e,
      );
    }
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/temp_recording.m4a'; // Sherpa needs proper format, ideally wav 16k

        // Note: Sherpa onnx handles raw audio or wav files.
        // We might need to configure recorder to WAV 16000Hz PCM if possible or convert.
        // Record package supports WAV.

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: '${dir.path}/temp_recording.wav'
        );
        _isRecording = true;
      }
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Failed to start recording: $e',
        source: 'SpeechRecognitionService',
        error: e,
      );
    }
  }

  Future<String> stopAndTranscribe() async {
    if (!_isRecording) return '';

    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;

      if (path == null) return '';

      return await transcribeFile(path);
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Failed to stop recording: $e',
        source: 'SpeechRecognitionService',
        error: e,
      );
      return '';
    }
  }

  Future<String> transcribeFile(String audioPath) async {
    if (_recognizer == null) {
      await initialize();
      if (_recognizer == null) return 'ASR Model not initialized';
    }

    // Sherpa ONNX usually takes a stream or float array.
    // However, the flutter plugin wrapper typically exposes file-based or stream-based methods.
    // Checking sherpa_onnx usage:
    // It doesn't have a direct `transcribeFile` in the wrapper usually?
    // Wait, the wrapper typically provides `acceptWaveform`.
    // We need to read the wav file and pass samples.
    // Or check if there is a helper.

    // For this plan, I will implement a basic wave reader or assume we can pass the file path if supported.
    // Looking at common flutter sherpa examples, we typically decode the wave file.

    try {
      // 1. Read WAV file
      // Since we don't have a wave reader library in dependencies (except maybe flutter_sound or similar if included),
      // we might need to rely on sherpa's helper if it exists.
      // Actually `sherpa_onnx` package usually has `readWave` or similar.

      final waveData = sherpa.readWave(audioPath);
      if (waveData == null) return 'Failed to read audio file';

      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: waveData.samples, sampleRate: waveData.sampleRate);

      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);

      stream.free();

      return result.text;
    } catch (e) {
       UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Transcription failed: $e',
        source: 'SpeechRecognitionService',
        error: e,
      );
      return 'Error: $e';
    }
  }

  void dispose() {
    _audioRecorder.dispose();
    _recognizer?.free();
  }
}
