import 'dart:io';

class PlatformHelper {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;

  static Future<String> getCpuArchitecture() async {
    try {
      if (Platform.isAndroid) {
        final archInfo = await Process.run('getprop', ['ro.product.cpu.abi']);
        if (archInfo.exitCode == 0 && archInfo.stdout != null) {
          return (archInfo.stdout as String).trim().toLowerCase();
        }
      }

      String arch = Platform.operatingSystemVersion.toLowerCase();
      if (arch.contains('64')) return 'arm64';

      return Platform.version.toLowerCase();
    } catch (e) {
      return '';
    }
  }
}
