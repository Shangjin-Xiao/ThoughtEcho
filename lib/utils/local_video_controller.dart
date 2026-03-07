import 'package:video_player/video_player.dart';

import 'local_video_controller_stub.dart'
    if (dart.library.io) 'local_video_controller_io.dart'
    as impl;

VideoPlayerController createLocalVideoPlayerController(String filePath) {
  return impl.createLocalVideoPlayerController(filePath);
}
