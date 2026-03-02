import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/local_ai_model.dart';

void main() {
  group('LocalAIModelInfo map serialization', () {
    test('toMap returns same structure as toJson', () {
      const model = LocalAIModelInfo(
        id: 'whisper-tiny',
        name: 'Whisper Tiny',
        type: LocalAIModelType.asr,
        description: 'test model',
        sizeBytes: 1024,
        downloadUrl: 'https://example.com/model.tar.bz2',
        fileName: 'model.tar.bz2',
        status: LocalAIModelStatus.downloaded,
        downloadProgress: 1.0,
        errorMessage: null,
        version: '1.0',
        isRequired: true,
      );

      expect(model.toMap(), equals(model.toJson()));
    });

    test('fromMap creates model with same values as fromJson', () {
      final map = {
        'id': 'whisper-tiny',
        'name': 'Whisper Tiny',
        'type': 'asr',
        'description': 'test model',
        'sizeBytes': 1024,
        'downloadUrl': 'https://example.com/model.tar.bz2',
        'fileName': 'model.tar.bz2',
        'status': 'downloaded',
        'downloadProgress': 1.0,
        'errorMessage': null,
        'version': '1.0',
        'isRequired': true,
      };

      final fromMap = LocalAIModelInfo.fromMap(map);
      final fromJson = LocalAIModelInfo.fromJson(map);

      expect(fromMap, equals(fromJson));
      expect(fromMap.toJson(), equals(fromJson.toJson()));
    });
  });
}
