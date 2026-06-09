import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/streaming_json_parser.dart';

void main() {
  group('StreamingJsonParser', () {
    late Directory tempDir;
    late File smallFile;
    late File invalidFile;

    setUp(() async {
      // Create a temporary directory for test files
      tempDir = await Directory.systemTemp.createTemp('streaming_json_parser_test');

      // Create a valid small JSON file
      smallFile = File('${tempDir.path}/small.json');
      final Map<String, dynamic> data = {
        'id': 1,
        'name': 'Test',
        'items': [1, 2, 3]
      };
      await smallFile.writeAsString(jsonEncode(data));

      // Create an invalid JSON file (e.g., malformed)
      invalidFile = File('${tempDir.path}/invalid.json');
      await invalidFile.writeAsString('This is not a JSON { } [ ]');
    });

    tearDown(() async {
      // Clean up temporary directory
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('parseJsonFile should parse small file correctly', () async {
      final result = await StreamingJsonParser.parseJsonFile(smallFile);

      expect(result, isNotNull);
      expect(result['id'], 1);
      expect(result['name'], 'Test');
      expect((result['items'] as List).length, 3);
    });

    test('parseJsonFile should throw exception on invalid file', () async {
      expect(
        () async => await StreamingJsonParser.parseJsonFile(invalidFile),
        throwsA(isA<Exception>()), // JsonUnsupportedObjectError or FormatException usually wrapped or thrown
      );
    });

    test('canSafelyParse should return true for valid json file', () async {
      final result = await StreamingJsonParser.canSafelyParse(smallFile);
      expect(result, isTrue);
    });

    test('canSafelyParse should return false for invalid json file format', () async {
      final result = await StreamingJsonParser.canSafelyParse(invalidFile);
      expect(result, isFalse);
    });

    test('canSafelyParse should return false for non-existent file', () async {
      final nonExistentFile = File('${tempDir.path}/does_not_exist.json');
      final result = await StreamingJsonParser.canSafelyParse(nonExistentFile);
      expect(result, isFalse);
    });

    test('estimateMemoryUsage should return roughly 3x file size', () async {
      final fileSize = await smallFile.length();
      final estimatedUsage = await StreamingJsonParser.estimateMemoryUsage(smallFile);

      expect(estimatedUsage, fileSize * 3);
    });
  });
}
