import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/streaming_json_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StreamingJsonParser Tests', () {
    late File testFile;
    late File badFile;

    setUp(() async {
      // Create a valid small JSON file
      testFile = File('test_valid_json.json');
      await testFile.writeAsString('{"name": "test", "value": 42}');

      // Create an invalid JSON file
      badFile = File('test_bad_json.json');
      await badFile.writeAsString('invalid json data');
    });

    tearDown(() async {
      if (testFile.existsSync()) {
        await testFile.delete();
      }
      if (badFile.existsSync()) {
        await badFile.delete();
      }
    });

    test('parseJsonFile parses a valid JSON file correctly', () async {
      final result = await StreamingJsonParser.parseJsonFile(testFile);
      expect(result, isA<Map<String, dynamic>>());
      expect(result['name'], 'test');
      expect(result['value'], 42);
    });

    test('canSafelyParse returns true for valid JSON starting with { or [',
        () async {
      final canParse = await StreamingJsonParser.canSafelyParse(testFile);
      expect(canParse, isTrue);

      final arrayFile = File('test_array_json.json');
      await arrayFile.writeAsString('[{"id": 1}]');
      final canParseArray = await StreamingJsonParser.canSafelyParse(arrayFile);
      expect(canParseArray, isTrue);
      await arrayFile.delete();
    });

    test('canSafelyParse returns false for invalid file contents', () async {
      final canParse = await StreamingJsonParser.canSafelyParse(badFile);
      expect(canParse, isFalse);
    });

    test('estimateMemoryUsage returns fileSize * 3', () async {
      final fileSize = await testFile.length();
      final estimated = await StreamingJsonParser.estimateMemoryUsage(testFile);

      expect(estimated, (fileSize * 3).toInt());
    });
  });
}
