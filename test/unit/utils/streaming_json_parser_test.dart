import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/media_file_service.dart';
import 'package:thoughtecho/utils/streaming_json_parser.dart';

void main() {
  group('StreamingJsonParser', () {
    late dynamic tempDir;
    late dynamic smallFile;
    late dynamic invalidFile;

    setUp(() async {
      // Create a temporary directory for test files using MediaFileService helper
      tempDir = await MediaFileService.createTempDirForTesting(
          'streaming_json_parser_test');

      // Create a valid small JSON file
      final smallFilePath = '${tempDir.path}/small.json';
      final Map<String, dynamic> data = {
        'id': 1,
        'name': 'Test',
        'items': [1, 2, 3]
      };
      smallFile = await MediaFileService.writeFileForTesting(
          smallFilePath, jsonEncode(data));

      // Create an invalid JSON file (e.g., malformed)
      final invalidFilePath = '${tempDir.path}/invalid.json';
      invalidFile = await MediaFileService.writeFileForTesting(
          invalidFilePath, 'This is not a JSON { } [ ]');
    });

    tearDown(() async {
      // Clean up temporary directory
      if (tempDir != null) {
        await MediaFileService.deleteForTesting(tempDir.path, recursive: true);
      }
    });

    test('parseJsonFile should parse small file correctly', () async {
      final fileToParse =
          await MediaFileService.getFileForTesting(smallFile.path);
      final result = await StreamingJsonParser.parseJsonFile(fileToParse);

      expect(result, isNotNull);
      expect(result['id'], 1);
      expect(result['name'], 'Test');
      expect((result['items'] as List).length, 3);
    });

    test('parseJsonFile should throw exception on invalid file', () async {
      final fileToParse =
          await MediaFileService.getFileForTesting(invalidFile.path);
      expect(
        () async => await StreamingJsonParser.parseJsonFile(fileToParse),
        throwsA(isA<
            Exception>()), // JsonUnsupportedObjectError or FormatException usually wrapped or thrown
      );
    });

    test('canSafelyParse should return true for valid json file', () async {
      final fileToParse =
          await MediaFileService.getFileForTesting(smallFile.path);
      final result = await StreamingJsonParser.canSafelyParse(fileToParse);
      expect(result, isTrue);
    });

    test('canSafelyParse should return false for invalid json file format',
        () async {
      final fileToParse =
          await MediaFileService.getFileForTesting(invalidFile.path);
      final result = await StreamingJsonParser.canSafelyParse(fileToParse);
      expect(result, isFalse);
    });

    test('canSafelyParse should return false for non-existent file', () async {
      final nonExistentFile = await MediaFileService.getFileForTesting(
          '${tempDir.path}/does_not_exist.json');
      final result = await StreamingJsonParser.canSafelyParse(nonExistentFile);
      expect(result, isFalse);
    });

    test('estimateMemoryUsage should return roughly 3x file size', () async {
      final fileToParse =
          await MediaFileService.getFileForTesting(smallFile.path);
      final fileSize = await fileToParse.length();
      final estimatedUsage =
          await StreamingJsonParser.estimateMemoryUsage(fileToParse);

      expect(estimatedUsage, fileSize * 3);
    });
  });
}
