import 'dart:async';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:record/record.dart';

class LocalASRService {
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
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
    try {
        sherpa.OnlineRecognizerConfig config = sherpa.OnlineRecognizerConfig(
        feat: sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        model: sherpa.OnlineModelConfig(
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
      // print("Failed to initialize ASR: $e");
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
      _stream = _recognizer!.createStream();

      _audioSubscription = stream.listen((data) {
        final samples = _bytesToFloat(data);
        _stream!.acceptWaveform(samples: Float32List.fromList(samples), sampleRate: 16000);

        if (_recognizer!.isReady(_stream!)) {
          _recognizer!.decode(_stream!);
          final result = _recognizer!.getResult(_stream!);
          if (result.text.isNotEmpty) {
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

    if (_recognizer != null && _stream != null) {
      final result = _recognizer!.getResult(_stream!);
      _resultController.add(result.text); // Final result
      _stream!.free();
      _stream = null;
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
