// Stub implementations for platforms that don't support certain features

import 'dart:typed_data';

/// Stub implementation for Gal when it's not available
class Gal {
  static Future<bool> hasAccess() async {
    return false;
  }

  static Future<bool> requestAccess() async {
    return false;
  }

  static Future<void> putImageBytes(Uint8List bytes, {String? name}) async {
    throw UnsupportedError('Gallery access not supported on this platform');
  }
}
