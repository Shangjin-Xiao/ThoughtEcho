import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import '../utils/app_logger.dart';

class ModelManagerService {
  static const String _hfBaseUrl = "https://huggingface.co/Xenova/paraphrase-multilingual-MiniLM-L12-v2/resolve/main";
  static const String _embeddingModelName = "onnx/model_quantized.onnx";
  static const String _vocabName = "vocab.txt";

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
    final encoder = File('$path/sherpa-onnx-whisper-tiny/tiny-encoder.int8.onnx');
    return await encoder.exists();
  }

  Future<void> downloadEmbeddingModels({Function(double)? onProgress}) async {
    final path = await _localPath;

    await _downloadFile(
      '$_hfBaseUrl/$_embeddingModelName',
      '$path/model_quantized.onnx',
      onProgress: (p) => onProgress?.call(p * 0.8),
    );

    await _downloadFile(
      '$_hfBaseUrl/$_vocabName',
      '$path/vocab.txt',
      onProgress: (p) => onProgress?.call(0.8 + p * 0.2),
    );
  }

  Future<void> downloadSherpaModels({Function(double)? onProgress}) async {
    final path = await _localPath;
    final tarPath = '$path/$_sherpaModelTar';

    // 1. Download
    await _downloadFile(
      '$_sherpaBaseUrl/$_sherpaModelTar',
      tarPath,
      onProgress: (p) => onProgress?.call(p * 0.7),
    );

    // 2. Extract
    onProgress?.call(0.75); // Start extraction
    try {
        final tarFile = File(tarPath);
        final bytes = await tarFile.readAsBytes();

        // BZip2 Decode
        final archive = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));

        // Extract
        for (final file in archive) {
            final filename = file.name;
            if (file.isFile) {
                final outFile = File('$path/$filename');
                // Ensure parent exists
                await outFile.parent.create(recursive: true);
                final data = file.content as List<int>;
                await outFile.writeAsBytes(data);
            }
        }

        // Clean up tar file
        await tarFile.delete();

    } catch (e) {
        logError("Failed to extract Sherpa models: $e", source: "ModelManager");
        rethrow;
    }

    onProgress?.call(1.0);
  }

  Future<void> _downloadFile(String url, String savePath, {Function(double)? onProgress}) async {
    final file = File(savePath);
    if (await file.exists()) {
        onProgress?.call(1.0);
        return;
    }

    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    final contentLength = response.contentLength;

    if (contentLength == null) {
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
