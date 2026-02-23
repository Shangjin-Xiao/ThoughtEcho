/// Web/非IO 平台的模型解压占位实现
class ModelExtractor {
  static Future<String> extract(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1.0);
    throw UnsupportedError('model_extraction_not_supported_on_this_platform');
  }

  static Future<String> extractTarBz2(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) =>
      extract(archivePath, extractDir, onProgress: onProgress);

  static Future<String> extractTarGz(
    String archivePath,
    String extractDir, {
    void Function(double progress)? onProgress,
  }) =>
      extract(archivePath, extractDir, onProgress: onProgress);

  static Future<WhisperModelFiles?> validateWhisperModel(
      String modelDir) async {
    return null;
  }

  static Future<List<String>> findTrainedDataFiles(String dir) async {
    return const [];
  }
}

class WhisperModelFiles {
  final String encoder;
  final String decoder;
  final String tokens;

  const WhisperModelFiles({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });
}
