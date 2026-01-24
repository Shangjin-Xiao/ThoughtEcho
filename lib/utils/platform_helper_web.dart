class PlatformHelper {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;

  static Future<String> getCpuArchitecture() async {
    return 'web';
  }
}
