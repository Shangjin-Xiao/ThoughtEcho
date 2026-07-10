import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/ai_smart_result_utils.dart';

void main() {
  group('AiSmartResultUtils', () {
    test('uses the AddNoteDialog long-content threshold for full editor', () {
      expect(
        AiSmartResultUtils.shouldOpenFullEditor(List.filled(100, 'a').join()),
        isFalse,
      );
      expect(
        AiSmartResultUtils.shouldOpenFullEditor(List.filled(101, 'a').join()),
        isTrue,
      );
    });

    test('resolves new note metadata without default author or source', () {
      final metadata = AiSmartResultUtils.resolveNewNoteMetadata(
        aiAuthor: '',
        aiSource: null,
        aiTagIds: const ['ai'],
        defaultTagIds: const ['default'],
        aiIncludeLocation: false,
        aiIncludeWeather: true,
        userAutoAttachLocation: false,
        userAutoAttachWeather: false,
      );

      expect(metadata.author, isNull);
      expect(metadata.source, isNull);
      expect(metadata.tagIds, const ['default', 'ai']);
      expect(metadata.includeLocation, isFalse);
      expect(metadata.includeWeather, isTrue);
    });

    test('explicit AI location and weather choices override user defaults', () {
      final metadata = AiSmartResultUtils.resolveNewNoteMetadata(
        aiAuthor: '鲁迅',
        aiSource: '呐喊',
        aiTagIds: const ['ai', 'default'],
        defaultTagIds: const ['default', 'journal'],
        aiIncludeLocation: false,
        aiIncludeWeather: false,
        userAutoAttachLocation: true,
        userAutoAttachWeather: true,
      );

      expect(metadata.author, '鲁迅');
      expect(metadata.source, '呐喊');
      expect(metadata.tagIds, const ['default', 'journal', 'ai']);
      expect(metadata.includeLocation, isFalse);
      expect(metadata.includeWeather, isFalse);
    });

    test('omitted AI location and weather choices use user defaults', () {
      final metadata = AiSmartResultUtils.resolveNewNoteMetadata(
        aiAuthor: null,
        aiSource: null,
        aiTagIds: const [],
        defaultTagIds: const [],
        aiIncludeLocation: null,
        aiIncludeWeather: null,
        userAutoAttachLocation: true,
        userAutoAttachWeather: false,
      );

      expect(metadata.includeLocation, isTrue);
      expect(metadata.includeWeather, isFalse);
    });
  });
}
