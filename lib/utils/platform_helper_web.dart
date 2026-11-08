import 'dart:typed_data';

class PlatformHelper {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;

  static bool get is64BitProcess => false;
  static int get pointerBits => 32;

  static Future<String> getCpuArchitecture() async {
    return 'web';
  }

  static Future<Uint8List?> readFileBytesIfExists(String filePath) async {
    return null;
  }

  static Future<List<String>> resolveCandidateMmkvFiles({
    List<String>? customPaths,
  }) async {
    return customPaths ?? const [];
  }

  static Future<bool> hasPopulatedThoughtEchoDatabase({
    List<String>? customDbPaths,
    String? customDataDirectoryPath,
  }) async {
    return false;
  }
}
