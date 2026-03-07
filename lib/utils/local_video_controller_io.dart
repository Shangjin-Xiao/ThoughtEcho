import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createLocalVideoPlayerController(String filePath) {
  return VideoPlayerController.file(File(filePath));
}
