class MotionPhotoInfo {
  const MotionPhotoInfo({required this.videoStart, required this.videoEnd});

  final int videoStart;
  final int videoEnd;

  int get videoLength => videoEnd - videoStart;
}

abstract class MotionPhotoUtils {
  const MotionPhotoUtils();

  Future<MotionPhotoInfo?> detect(String filePath);

  Future<String> extractVideoToTemporaryFile(
    String filePath, {
    MotionPhotoInfo? info,
  });

  Future<void> deleteTemporaryVideo(String filePath);
}
