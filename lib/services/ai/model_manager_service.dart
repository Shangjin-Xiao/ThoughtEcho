import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import '../utils/app_logger.dart';

class ModelManagerService {
  static const String _hfBaseUrl = "https://huggingface.co/Xenova/paraphrase-multilingual-MiniLM-L12-v2/resolve/main";
  static const String _embeddingModelName = "onnx/model_quantized.onnx";
  static const String _vocabName = "vocab.txt";

  // Sherpa Onnx models (Whisper tiny) - using a known reliable source
  static const String _sherpaBaseUrl = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models";
  static const String _sherpaModelTar = "sherpa-onnx-whisper-tiny.tar.bz2";

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${directory.path}/ai_models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir.path;
  }

  Future<String> getEmbeddingModelPath() async {
    final path = await _localPath;
    return '$path/model_quantized.onnx';
  }

  Future<String> getVocabPath() async {
    final path = await _localPath;
    return '$path/vocab.txt';
  }

  Future<String> getSherpaEncoderPath() async {
    final path = await _localPath;
    return '$path/sherpa-onnx-whisper-tiny/tiny-encoder.int8.onnx';
  }

  Future<String> getSherpaDecoderPath() async {
    final path = await _localPath;
    return '$path/sherpa-onnx-whisper-tiny/tiny-decoder.int8.onnx';
  }

  Future<String> getSherpaTokensPath() async {
    final path = await _localPath;
    return '$path/sherpa-onnx-whisper-tiny/tiny-tokens.txt';
  }

  Future<bool> areEmbeddingModelsDownloaded() async {
    final path = await _localPath;
    final modelFile = File('$path/model_quantized.onnx');
    final vocabFile = File('$path/vocab.txt');
    return await modelFile.exists() && await vocabFile.exists();
  }

  Future<bool> areAsrModelsDownloaded() async {
    final path = await _localPath;
    // Check key files for whisper tiny
    final encoder = File('$path/sherpa-onnx-whisper-tiny/tiny-encoder.int8.onnx');
    return await encoder.exists();
  }

  Future<void> downloadEmbeddingModels({Function(double)? onProgress}) async {
    final path = await _localPath;

    // Download Model
    await _downloadFile(
      '$_hfBaseUrl/$_embeddingModelName',
      '$path/model_quantized.onnx',
      onProgress: (p) => onProgress?.call(p * 0.8), // 80% weight
    );

    // Download Vocab
    await _downloadFile(
      '$_hfBaseUrl/$_vocabName',
      '$path/vocab.txt',
      onProgress: (p) => onProgress?.call(0.8 + p * 0.2), // 20% weight
    );
  }

  // Note: Unzipping/Untarring logic is needed for Sherpa models usually distributed as tar.bz2
  // For simplicity in this environment, we might download individual files if possible,
  // or implement a basic tar extractor. For now, I'll assume individual file downloads for embedding
  // and placeholder for ASR since unpacking tar.bz2 might require native libs or complex dart logic.
  // Actually, let's use a direct link to a zip or individual files if available.
  // Xenova's repo has individual files. Sherpa usually has tar.bz2.
  // I will implement a simplified downloader that just mocks the "complex" unzip for now
  // or tries to download raw files if I can find a raw file source.
  // I'll stick to downloading the embedding model first as it's critical for the Vector Search.

  Future<void> _downloadFile(String url, String savePath, {Function(double)? onProgress}) async {
    final file = File(savePath);
    if (await file.exists()) return;

    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    final contentLength = response.contentLength;

    if (contentLength == null) {
        // Fallback if no content length
        final bytes = await http.readBytes(Uri.parse(url));
        await file.writeAsBytes(bytes);
        onProgress?.call(1.0);
        return;
    }

    final sink = file.openWrite();
    int received = 0;
    await response.stream.listen(
      (List<int> chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received / contentLength);
      },
    ).asFuture();
    await sink.close();
  }
}
