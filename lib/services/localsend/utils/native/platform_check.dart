/// Platform detection utilities for LocalSend

import 'dart:io';

class PlatformCheck {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isFuchsia => Platform.isFuchsia;
  
  static bool get isMobile => isAndroid || isIOS;
  static bool get isDesktop => isLinux || isMacOS || isWindows;
  
  static String get platformName {
    if (isAndroid) return 'Android';
    if (isIOS) return 'iOS';
    if (isLinux) return 'Linux';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isFuchsia) return 'Fuchsia';
    return 'Unknown';
  }
}
