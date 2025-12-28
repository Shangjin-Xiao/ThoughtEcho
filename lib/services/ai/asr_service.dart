import 'dart:async';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'model_manager_service.dart';
import 'dart:io';

class AsrService {
  final ModelManagerService _modelManager;
  final _audioRecorder = AudioRecorder();

  bool _isListening = false;
  OnlineRecognizer? _recognizer;
  OnlineStream? _stream;
  StreamSubscription? _audioSubscription;

  // Stream controller to emit partial results
  final StreamController<String> _textController = StreamController<String>.broadcast();
  Stream<String> get textStream => _textController.stream;

  AsrService(this._modelManager);

  Future<void> init() async {
    // Ensure models are available
    if (!await _modelManager.areAsrModelsDownloaded()) {
        print("ASR models missing");
        return;
    }

    // Create Recognizer
    final encoderPath = await _modelManager.getSherpaEncoderPath();
    final decoderPath = await _modelManager.getSherpaDecoderPath();
    final tokensPath = await _modelManager.getSherpaTokensPath();

    // Config for Whisper
    final config = OnlineRecognizerConfig(
      featConfig: FeatureConfig(sampleRate: 16000, featureDim: 80),
      modelConfig: OnlineModelConfig(
        transducer: OnlineTransducerModelConfig(
             encoder: "", decoder: "", joiner: "",
        ), // Empty because we use whisper
        paraformer: OnlineParaformerModelConfig(encoder: "", decoder: ""),
        zipformer: OnlineZipformerModelConfig(encoder: ""),
        tokens: tokensPath,
        numThreads: 1,
        // debug: true,
        provider: "cpu",
        modelType: "whisper",
        whisper: OnlineWhisperModelConfig(
             encoder: encoderPath,
             decoder: decoderPath,
        ),
      ),
      // decodingMethod: "greedy_search",
    );

    _recognizer = OnlineRecognizer(config);
  }

  Future<void> startListening() async {
    if (_isListening) return;
    if (_recognizer == null) await init();
    if (_recognizer == null) throw Exception("Failed to init ASR");

    if (!await _audioRecorder.hasPermission()) {
        throw Exception("Microphone permission denied");
    }

    _stream = _recognizer!.createStream();

    // Start recording stream
    // Sherpa expects 16kHz mono PCM float/int16
    // The 'record' package stream provides raw bytes (Int16 usually)

    final recordStream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _isListening = true;

    _audioSubscription = recordStream.listen((data) {
        // data is Uint8List (bytes) representing Int16 samples
        // We need to convert to Float32 array for Sherpa usually?
        // Wait, sherpa-onnx-flutter `acceptWaveform` usually takes List<double> (samples) or Int16 pointer.
        // Let's check API.
        // Usually: acceptWaveform(sampleRate, samples) where samples is List<double> normalized -1..1

        // Convert Uint8List (Int16) to Float list
        final samples = _bytesToFloat(data);
        _stream!.acceptWaveform(samples, sampleRate: 16000);

        // Decode
        if (_recognizer!.isReady(_stream!)) {
            _recognizer!.decode(_stream!);
        }

        final result = _recognizer!.getResult(_stream!);
        if (result.text.isNotEmpty) {
            _textController.add(result.text);
        }
    });
  }

  Future<void> stopListening() async {
    if (!_isListening) return;

    await _audioSubscription?.cancel();
    await _audioRecorder.stop();
    _stream?.free();
    _isListening = false;
    // Final result check?
    // Usually stream emits continuously.
  }

  List<double> _bytesToFloat(List<int> bytes) {
    // Little-endian Int16 -> Float
    final floats = <double>[];
    for (int i = 0; i < bytes.length; i += 2) {
      int sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536; // sign extend
      floats.add(sample / 32768.0);
    }
    return floats;
  }

  void dispose() {
    _audioSubscription?.cancel();
    _audioRecorder.dispose();
    _stream?.free();
    _recognizer?.free();
    _textController.close();
  }
}
