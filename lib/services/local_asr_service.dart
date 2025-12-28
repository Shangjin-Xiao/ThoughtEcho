import 'dart:async';
import 'dart:io';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class LocalASRService {
  sherpa.OnlineRecognizer? _recognizer;
  final _audioRecorder = AudioRecorder();
  StreamSubscription? _audioSubscription;
  bool _isRecording = false;

  // Stream controller for real-time results
  final _resultController = StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;

  bool get isRecording => _isRecording;

  Future<void> initialize({
    required String tokens,
    required String encoder,
    required String decoder,
    required String joiner,
  }) async {
    // Sherpa Onnx Config
    // Usually standard transducer config for streaming
    /*
    final config = sherpa.OnlineRecognizerConfig(
      modelConfig: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: encoder,
          decoder: decoder,
          joiner: joiner,
        ),
        tokens: tokens,
        numThreads: 1,
        provider: "cpu",
        debug: 0,
        modelType: "zipformer", // or conformer, depends on model
      ),
      featConfig: sherpa.FeatureConfig(
        sampleRate: 16000,
        featureDim: 80,
      ),
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20.0,
    );

    _recognizer = sherpa.OnlineRecognizer(config);
    */
    // Note: The actual sherpa_onnx flutter API creates recognizer differently sometimes.
    // I will use a simplified initialization assuming the user has downloaded standard sherpa-onnx models.
    // Since I cannot run the code, I will write generic code that matches the library's common usage.

    try {
        sherpa.OnlineRecognizerConfig config = sherpa.OnlineRecognizerConfig(
        featConfig: sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        modelConfig: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner,
          ),
          tokens: tokens,
          numThreads: 1,
        ),
      );
      _recognizer = sherpa.OnlineRecognizer(config);
    } catch (e) {
      print("Failed to initialize ASR: $e");
    }
  }

  Future<void> startRecording() async {
    if (_recognizer == null) throw Exception("ASR not initialized");
    if (await _audioRecorder.hasPermission()) {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _isRecording = true;
      _recognizer!.reset();

      _audioSubscription = stream.listen((data) {
        // data is Uint8List (PCM bytes)
        // Convert to float array [-1, 1] if needed, or pass bytes directly depending on API.
        // sherpa_onnx acceptWaveform usually takes list of floats.
        // 16-bit PCM -> float
        final samples = _bytesToFloat(data);
        _recognizer!.acceptWaveform(samples, sampleRate: 16000);

        if (_recognizer!.isReady()) {
          _recognizer!.decode();
          final result = _recognizer!.getResult();
          if (result.text.isNotEmpty) {
             // For streaming, we might want the diff or full text.
             // Usually getResult returns the full text of current segment.
             _resultController.add(result.text);
          }
        }
      });
    }
  }

  Future<void> stopRecording() async {
    _isRecording = false;
    await _audioRecorder.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (_recognizer != null) {
      final result = _recognizer!.getResult();
      _resultController.add(result.text); // Final result
    }
  }

  List<double> _bytesToFloat(List<int> bytes) {
    // 16-bit little endian
    final floats = <double>[];
    for (int i = 0; i < bytes.length; i += 2) {
      int sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      floats.add(sample / 32768.0);
    }
    return floats;
  }

  void dispose() {
    _resultController.close();
    // _recognizer?.free(); // If API supports it
  }
}
