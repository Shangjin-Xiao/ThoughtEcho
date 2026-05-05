import 'motion_photo_utils_base.dart';

MotionPhotoUtils createMotionPhotoUtils() =>
    const _UnsupportedMotionPhotoUtils();

class _UnsupportedMotionPhotoUtils extends MotionPhotoUtils {
  const _UnsupportedMotionPhotoUtils();

  @override
  Future<MotionPhotoInfo?> detect(String filePath) async => null;

  @override
  Future<String> extractVideoToTemporaryFile(
    String filePath, {
    MotionPhotoInfo? info,
  }) {
    throw UnsupportedError('Motion photo playback is not supported here.');
  }

  @override
  Future<void> deleteTemporaryVideo(String filePath) async {}
}
