import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/stub_implementations.dart';

void main() {
  group('Gal Stub Implementation', () {
    test('hasAccess always returns false', () async {
      expect(await Gal.hasAccess(), isFalse);
    });

    test('requestAccess always returns false', () async {
      expect(await Gal.requestAccess(), isFalse);
    });

    test('putImageBytes throws UnsupportedError', () async {
      final bytes = Uint8List(0);
      expect(
        () => Gal.putImageBytes(bytes, name: 'test.png'),
        throwsA(isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          'Gallery access not supported on this platform',
        )),
      );
    });
  });
}
