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

    test('CRC32 agrees with the standard check vector and subranges', () {
      final bytes = Uint8List.fromList(ascii.encode('x123456789y'));
      expect(MmkvBinaryReader.computeCrc32(bytes, 1, 9), 0xcbf43926);
      expect(MmkvBinaryReader.computeCrc32(Uint8List(0)), 0);
      expect(MmkvBinaryReader.computeCrc32(bytes, 3, 0), 0);
      expect(() => MmkvBinaryReader.computeCrc32(bytes, -1), throwsRangeError);
      expect(
          () => MmkvBinaryReader.computeCrc32(bytes, 0, 12), throwsRangeError);
    });

    for (final length in [0, 1, 2, 3]) {
      test('handles a $length-byte incomplete file without reading a header',
          () {
        final result = MmkvBinaryReader.parseBytes(Uint8List(length));
        expect(result.fileExists, isTrue);
        expect(result.actualSize, 0);
        expect(result.entries, isEmpty);
        expect(result.crcMatched, isNull);
        if (length > 0) expect(result.warnings, isNotEmpty);
      });
    }

    test('ignores records outside the declared payload size', () {
      final first = MmkvBinaryEncoder()..writeString('theme_style', 'paper');
      final all = MmkvBinaryEncoder()
        ..writeString('theme_style', 'paper')
        ..writeString('theme_mode', 'dark');
      final bytes = all.toFileBytes();
      final size =
          ByteData.sublistView(first.toFileBytes()).getUint32(0, Endian.little);
      ByteData.sublistView(bytes).setUint32(0, size, Endian.little);

      final result = MmkvBinaryReader.parseBytes(bytes);
      expect(result.entries, {'theme_style': 'paper'});
      expect(result.totalRecordsRead, 1);
    });

    test('discards decoded entries when both CRC checks fail', () {
      final encoder = MmkvBinaryEncoder()..writeString('theme_style', 'paper');
      final result = MmkvBinaryReader.parseBytes(
        encoder.toFileBytes(),
        crcBytes: encoder.toCrcBytes(
          overrideCrcDigest: 0xdeadbeef,
          lastCrcDigest: 0xdeadbeef,
        ),
      );
      expect(result.crcMatched, isFalse);
      expect(result.usedLastConfirmed, isFalse);
      expect(result.entries, isEmpty);
      expect(result.warnings, isNotEmpty);
    });

    test('recovers last confirmed data when header exceeds physical file', () {
      final encoder = MmkvBinaryEncoder()..writeString('theme_style', 'paper');
      final bytes = encoder.toFileBytes();
      ByteData.sublistView(bytes).setUint32(0, 0xffffffff, Endian.little);
      final result = MmkvBinaryReader.parseBytes(
        bytes,
        crcBytes: encoder.toCrcBytes(),
      );
      expect(result.usedLastConfirmed, isTrue);
      expect(result.crcMatched, isTrue);
      expect(result.entries, {'theme_style': 'paper'});
    });

    test('a value written after a tombstone restores the key', () {
      final encoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'material')
        ..writeTombstone('theme_style')
        ..writeString('theme_style', 'plain');
      final result = MmkvBinaryReader.parseBytes(encoder.toFileBytes());
      expect(result.entries, {'theme_style': 'plain'});
      expect(result.tombstonedKeys, isEmpty);
      expect(result.tombstoneRecordsRead, 1);
    });

    test('schema distinguishes prefixed false bool from empty string', () {
      final encoder = MmkvBinaryEncoder()
        ..writeBool('flutter.use_dynamic_color', false)
        ..writeString('flutter.theme_style', '');
      final result = MmkvBinaryReader.parseBytes(encoder.toFileBytes());
      expect(result.entries['flutter.use_dynamic_color'], isFalse);
      expect(result.entries['flutter.theme_style'], '');
    });

    test('malformed typed value does not prevent recovery of later records',
        () {
      // Independent wire fixture: a short double followed by a valid string.
      final payload = <int>[
        0xff,
        0xff,
        0xff,
        0x07,
        10,
        ...ascii.encode('font_scale'),
        1,
        0x7f,
        11,
        ...ascii.encode('theme_style'),
        6,
        5,
        ...ascii.encode('paper'),
      ];
      final bytes = Uint8List(4 + payload.length);
      ByteData.sublistView(bytes).setUint32(0, payload.length, Endian.little);
      bytes.setRange(4, bytes.length, payload);
      final result = MmkvBinaryReader.parseBytes(bytes);
      expect(result.entries['font_scale'], orderedEquals([0x7f]));
      expect(result.entries['theme_style'], 'paper');
      expect(result.warnings, isNotEmpty);
    });

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

    test(
      'decodes static raw byte fixture without MmkvBinaryEncoder',
      () {
        // Handcrafted raw wire-format bytes conforming to Tencent MMKV specification:
        // ItemSizeHolder: varint32 (0x00FFFFFF: 0xff, 0xff, 0xff, 0x07)
        // Record 1: key="lang" (len 4), string="zh" (container len 3: innerLen 2 + 'zh')
        // Record 2: key="is_active" (len 9), bool=true (container len 1: byte 1)
        // Record 3: key="deleted_key" (len 11), tombstone (valueLen 0)
        // Record 4: key="counter" (len 7), int64=-1 (container len 10: 10-byte varint)
        final payload = <int>[
          // ItemSizeHolder varint32
          0xff, 0xff, 0xff, 0x07,
          // Record 1
          0x04, 0x6c, 0x61, 0x6e, 0x67, 0x03, 0x02, 0x7a, 0x68,
          // Record 2
          0x09, 0x69, 0x73, 0x5f, 0x61, 0x63, 0x74, 0x69, 0x76, 0x65, 0x01,
          0x01,
          // Record 3 (Tombstone)
          0x0b, 0x64, 0x65, 0x6c, 0x65, 0x74, 0x65, 0x64, 0x5f, 0x6b, 0x65,
          0x79, 0x00,
          // Record 4 (int64 = -1)
          0x07, 0x63, 0x6f, 0x75, 0x6e, 0x74, 0x65, 0x72, 0x0a,
          0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
        ];
        final actualSize = payload.length;

        // Allocate 4096-byte file with 4-byte little-endian size header
        final rawFile = Uint8List(4096);
        final fileData = ByteData.sublistView(rawFile);
        fileData.setUint32(0, actualSize, Endian.little);
        rawFile.setRange(4, 4 + actualSize, payload);

        // CRC32 over the payload (bytes 4 .. 4+actualSize)
        final payloadCrc = MmkvBinaryReader.computeCrc32(
          Uint8List.fromList(payload),
        );

        // Allocate 4096-byte CRC meta file conforming to MMKVMetaInfo layout
        final rawCrc = Uint8List(4096);
        final crcData = ByteData.sublistView(rawCrc);
        crcData.setUint32(0, payloadCrc, Endian.little); // crcDigest
        crcData.setUint32(4, 1, Endian.little); // version
        crcData.setUint32(8, 1, Endian.little); // sequence
        // 12..27 is m_vector[16]
        crcData.setUint32(28, actualSize, Endian.little); // actualSize
        crcData.setUint32(32, actualSize, Endian.little); // lastActualSize
        crcData.setUint32(36, payloadCrc, Endian.little); // lastCrcDigest

        final result = MmkvBinaryReader.parseBytes(
          rawFile,
          crcBytes: rawCrc,
          filePath: '/independent/fixture/mmkv.default',
        );

        expect(result.fileExists, isTrue);
        expect(result.crcMatched, isTrue);
        expect(result.actualSize, equals(actualSize));
        expect(result.itemSizeHolder, equals(0x00FFFFFF));
        expect(result.tombstoneRecordsRead, equals(1));
        expect(result.tombstonedKeys, contains('deleted_key'));
        expect(result.entries.containsKey('deleted_key'), isFalse);
        expect(result.entries['lang'], equals('zh'));
        expect(result.entries['is_active'], isTrue);
        expect(result.entries['counter'], equals(-1));
      },
    );
  });
}
