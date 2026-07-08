import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/delta_content_serializer.dart';

void main() {
  group('DeltaContentSerializer', () {
    test('preserves media embeds when encoding rich text delta', () {
      final delta = [
        {
          'insert': {'image': '/media/image.jpg'},
        },
        {
          'insert': {'video': '/media/video.mp4'},
        },
        {'insert': 'caption\n'},
      ];

      final encoded = DeltaContentSerializer.encode(delta);

      expect(jsonDecode(encoded), delta);
    });

    test('rejects lossy simplified media placeholders', () {
      final delta = [
        {
          'insert': {'type': 'image', 'simplified': true},
        },
      ];

      expect(
        () => DeltaContentSerializer.encode(delta),
        throwsA(isA<LossyDeltaContentException>()),
      );
    });
  });
}
