/// Platform check utilities for LocalSend
import 'dart:io';
import 'package:flutter/foundation.dart';

bool checkPlatform(List<TargetPlatform> platforms, {bool web = false}) {
  if (web && kIsWeb) {
    return true;
  }
  return platforms.contains(defaultTargetPlatform);
}

bool checkPlatformIsDesktop() {
  return checkPlatform([TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS]);
}

bool checkPlatformHasTray() {
  return checkPlatform([TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]);
}

bool checkPlatformCanReceiveShareIntent() {
  return checkPlatform([TargetPlatform.android, TargetPlatform.iOS]);
}

bool checkPlatformWithGallery() {
  return checkPlatform([TargetPlatform.android, TargetPlatform.iOS]);
}

bool checkPlatformWithFileSystem() {
  return checkPlatform([TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.android, TargetPlatform.macOS]);
}

bool checkPlatformIsNotWaylandDesktop() {
  if (checkPlatform([TargetPlatform.linux])) {
    if (Platform.environment['XDG_SESSION_TYPE'] == 'wayland') {
      return false;
    }
  }
  return true;
}