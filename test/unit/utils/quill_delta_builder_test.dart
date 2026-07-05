import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/quill_delta_builder.dart';

void main() {
  group('DeltaBuilder Unit Tests', () {
    test('textToDelta converts plain text to basic delta ops', () {
      final ops = DeltaBuilder.textToDelta('Hello World');
      expect(ops.length, 2);
      expect(ops[0]['insert'], 'Hello World');
      expect(ops[1]['insert'], '\n');
    });

    test('appendTextToDelta appends new text preserving original ops order',
        () {
      final originalOps = [
        {'insert': 'Hello '},
        {
          'insert': {'image': 'img1'}
        },
        {'insert': '\n'}
      ];
      final originalJson = jsonEncode({'ops': originalOps});

      final resultOps = DeltaBuilder.appendTextToDelta(
        originalDeltaJson: originalJson,
        newText: 'World',
      );

      // Verify original order is preserved: text, image, then new text starts on new line
      expect(resultOps.length, 5);
      expect(resultOps[0]['insert'], 'Hello ');
      expect(resultOps[1]['insert'], {'image': 'img1'});
      expect(resultOps[2]['insert'], '\n');
      expect(resultOps[3]['insert'], 'World');
      expect(resultOps[4]['insert'], '\n');
    });

    test(
        'replaceTextInDelta replaces text and performs position-aware merge of embeds',
        () {
      final originalOps = [
        {'insert': 'Hello '}, // Length 6
        {
          'insert': {'image': 'img1'}
        }, // Offset 6
        {'insert': 'World'}, // Length 5 (Total 11)
        {
          'insert': {'image': 'img2'}
        }, // Offset 11
        {'insert': '\n'}
      ];
      final originalJson = jsonEncode({'ops': originalOps});

      // newText length is 22.
      // img1 should map to: (6 * 22) ~/ 11 = 12.
      // img2 should map to: (11 * 22) ~/ 11 = 22.
      final newText = 'Bonjour tout le Monde!'; // Length 22
      final resultOps = DeltaBuilder.replaceTextInDelta(
        originalDeltaJson: originalJson,
        newText: newText,
      );

      expect(resultOps.length, 6);
      expect(resultOps[0]['insert'], 'Bonjour tou');
      expect(resultOps[1]['insert'], {'image': 'img1'});
      expect(resultOps[2]['insert'], 't le Mond');
      expect(resultOps[3]['insert'], {'image': 'img2'});
      expect(resultOps[4]['insert'], 'e!');
      expect(resultOps[5]['insert'], '\n');
    });

    test('replaceTextInDelta fallback when no embeds', () {
      final originalOps = [
        {'insert': 'Hello World\n'}
      ];
      final originalJson = jsonEncode({'ops': originalOps});

      final resultOps = DeltaBuilder.replaceTextInDelta(
        originalDeltaJson: originalJson,
        newText: 'Bonjour',
      );

      expect(resultOps.length, 2);
      expect(resultOps[0]['insert'], 'Bonjour');
      expect(resultOps[1]['insert'], '\n');
    });
  });
}
