import 'motion_photo_utils_base.dart';
import 'motion_photo_utils_stub.dart'
    if (dart.library.io) 'motion_photo_utils_io.dart' as impl;

export 'motion_photo_utils_base.dart';

MotionPhotoUtils createMotionPhotoUtils() => impl.createMotionPhotoUtils();
