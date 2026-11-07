import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/mmkv_binary_reader.dart';

void main() {
  group('MmkvBinaryReader & MmkvBinaryEncoder', () {
    test(
      'decodes strings, empty strings, bools, int64 (positive & negative), doubles, string lists, overwrites, and tombstones',
      () {
        final encoder = MmkvBinaryEncoder();

        // 1. Standard & multi-byte UTF-8 strings (Chinese + Emoji)
        encoder.writeString(
          'app_settings',
          '{"hitokotoType":"a,b,c","hasCompletedOnboarding":true}',
        );
        encoder.writeString('user_nickname', '心迹探索者 🌟');
        encoder.writeString('webdav_last_sync_error', '');
        encoder.writeString(
          'smart_push_today_daily_quote_pushed',
          '2026-11-07',
        );

        // 2. Dynamic prefix key (draft_*)
        encoder.writeString('draft_note_123', '{"plainText":"草稿内容"}');

        // 3. StringList encoded as JSON array string (matching MMKVAdapter.setStringList)
        encoder.writeString('favorite_tags', json.encode(['哲学', '思考', 'AI']));

        // 4. Booleans
        encoder.writeBool('app_installed_v2', true);
        encoder.writeBool('agent_memory_enabled', false);
        encoder.writeBool('feature_guide_shown_home_v1', true);

        // 5. Int64 (positive, zero, and negative 64-bit two's complement varint)
        encoder.writeInt('custom_color', 0xFF2B5B84);
        encoder.writeInt('agent_memory_last_dreaming_at', 1730995200000);
        encoder.writeInt('log_level', -1);

        // 6. Double (IEEE 754 float64 little-endian)
        encoder.writeDouble('font_scale', 1.25);

        // 7. Overwrite same key multiple times -> latest value must win
        encoder.writeString('theme_style', 'material');
        encoder.writeString('theme_style', 'paper');

        // 8. Write key then tombstone-delete it -> must not appear in entries
        encoder.writeString('draft_deleted_999', 'temporary draft');
        encoder.writeTombstone('draft_deleted_999');

        final fileBytes = encoder.toFileBytes(minTotalSize: 4096);
        final crcBytes = encoder.toCrcBytes(sequence: 7);

        final result = MmkvBinaryReader.parseBytes(
          fileBytes,
          crcBytes: crcBytes,
          filePath: '/mock/app_flutter/mmkv/mmkv.default',
        );

        expect(result.fileExists, isTrue);
        expect(result.fileByteLength, equals(4096));
        expect(result.actualSize, greaterThan(4));
        expect(
          result.itemSizeHolder,
          equals(MmkvBinaryEncoder.defaultItemSizeHolder),
        );
        expect(result.crcMatched, isTrue);
        expect(result.usedLastConfirmed, isFalse);
        expect(result.crcMeta?.sequence, equals(7));
        expect(result.tombstoneRecordsRead, equals(1));
        expect(result.warnings, isEmpty);

        expect(
          result.entries['app_settings'],
          equals('{"hitokotoType":"a,b,c","hasCompletedOnboarding":true}'),
        );
        expect(result.entries['user_nickname'], equals('心迹探索者 🌟'));
        expect(result.entries['webdav_last_sync_error'], equals(''));
        expect(
          result.entries['smart_push_today_daily_quote_pushed'],
          equals('2026-11-07'),
        );
        expect(
          result.entries['draft_note_123'],
          equals('{"plainText":"草稿内容"}'),
        );
        expect(
          result.entries['favorite_tags'],
          equals(<String>['哲学', '思考', 'AI']),
        );
        expect(result.entries['app_installed_v2'], isTrue);
        expect(result.entries['agent_memory_enabled'], isFalse);
        expect(result.entries['feature_guide_shown_home_v1'], isTrue);
        expect(result.entries['custom_color'], equals(0xFF2B5B84));
        expect(
          result.entries['agent_memory_last_dreaming_at'],
          equals(1730995200000),
        );
        expect(result.entries['log_level'], equals(-1));
        expect(result.entries['font_scale'], closeTo(1.25, 1e-9));
        expect(result.entries['theme_style'], equals('paper'));
        expect(result.entries.containsKey('draft_deleted_999'), isFalse);
      },
    );

    test(
      'falls back to lastConfirmed actualSize & CRC when primary CRC mismatches',
      () {
        final confirmedEncoder = MmkvBinaryEncoder()
          ..writeBool('app_installed_v2', true)
          ..writeString('theme_mode', 'dark');
        final confirmedFile = confirmedEncoder.toFileBytes(minTotalSize: 4096);
        final confirmedActualSize =
            ByteData.sublistView(confirmedFile).getUint32(0, Endian.little);
        final confirmedCrc = MmkvBinaryReader.computeCrc32(
          confirmedFile,
          4,
          confirmedActualSize,
        );

        // Simulate an interrupted write that bumped header actualSize and corrupted trailing bytes
        final corruptedFile = Uint8List.fromList(confirmedFile);
        ByteData.sublistView(corruptedFile).setUint32(
          0,
          confirmedActualSize + 20,
          Endian.little,
        );
        corruptedFile[4 + confirmedActualSize + 2] = 0xFF;

        final crcBytes = confirmedEncoder.toCrcBytes(
          overrideCrcDigest: 0xDEADBEEF,
          overrideActualSize: confirmedActualSize + 20,
          lastActualSize: confirmedActualSize,
          lastCrcDigest: confirmedCrc,
        );

        final result = MmkvBinaryReader.parseBytes(
          corruptedFile,
          crcBytes: crcBytes,
        );

        expect(result.crcMatched, isTrue);
        expect(result.usedLastConfirmed, isTrue);
        expect(result.actualSize, equals(confirmedActualSize));
        expect(result.entries['app_installed_v2'], isTrue);
        expect(result.entries['theme_mode'], equals('dark'));
      },
    );

    test(
      'greedily recovers valid keys before a truncated tail record',
      () async {
        final encoder = MmkvBinaryEncoder()
          ..writeString('theme_style', 'plain')
          ..writeBool('use_dynamic_color', true);
        final validBytes = encoder.toFileBytes();

        // Append a truncated record (claims keyLen = 50, but only 3 bytes follow)
        final truncated = Uint8List(validBytes.length + 4);
        truncated.setRange(0, validBytes.length, validBytes);
        truncated[validBytes.length] = 50;
        truncated[validBytes.length + 1] = 0x61;
        truncated[validBytes.length + 2] = 0x62;
        truncated[validBytes.length + 3] = 0x63;
        ByteData.sublistView(truncated).setUint32(
          0,
          truncated.length - 4,
          Endian.little,
        );

        final tempDir = await Directory.systemTemp.createTemp('mmkv_reader_');
        try {
          final filePath = '${tempDir.path}/mmkv.default';
          await File(filePath).writeAsBytes(truncated);

          final result = await MmkvBinaryReader.parseFile(filePath);
          expect(result.fileExists, isTrue);
          expect(result.entries['theme_style'], equals('plain'));
          expect(result.entries['use_dynamic_color'], isTrue);
          expect(result.warnings, isNotEmpty);
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });
}
