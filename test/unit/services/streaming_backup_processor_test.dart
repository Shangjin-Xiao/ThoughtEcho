import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/services/streaming_backup_processor.dart';

import '../../test_harness.dart';

void main() {
  late Directory documents;
  late Directory temporary;

  setUp(() async {
    await TestHarness.initialize();
    documents = await getApplicationDocumentsDirectory();
    temporary = await getTemporaryDirectory();
  });

  tearDown(TestHarness.tearDown);

  Future<String> createBackup(Map<String, String> entries) async {
    final archive = Archive();
    for (final entry in entries.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final file = File(p.join(temporary.path, 'backup.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file.path;
  }

  // The import contract caps expanded backup JSON at 32 MiB. Whitespace keeps
  // fixtures valid JSON without constructing a large decoded object graph.
  const jsonLimit = 32 * 1024 * 1024;

  Future<String> createSizedJsonBackup({
    required int size,
    int? declaredSize,
    String name = 'backup_data.json',
    CompressionType compression = CompressionType.deflate,
    bool symbolicLink = false,
  }) async {
    final content = Uint8List(size)..fillRange(0, size, 0x20);
    content[0] = 0x7b;
    content[1] = 0x7d;
    final archive = Archive()
      ..addFile(ArchiveFile(name, size, content)..compression = compression)
      ..addFile(ArchiveFile.string('media/images/photo.png', 'image'));
    final bytes = ZipEncoder().encodeBytes(archive);
    final view = ByteData.sublistView(bytes);
    final centralOffset = view.getUint32(bytes.length - 6, Endian.little);
    if (declaredSize != null) {
      // Alter both local and central sizes while preserving the compressed data.
      view.setUint32(22, declaredSize, Endian.little);
      view.setUint32(centralOffset + 24, declaredSize, Endian.little);
    }
    if (symbolicLink) {
      view.setUint16(centralOffset + 4, 0x0314, Endian.little);
      view.setUint32(centralOffset + 38, 0xa1ff << 16, Endian.little);
    }
    final file = File(p.join(temporary.path, 'sized.zip'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  final exceedsJsonLimit = isA<FormatException>().having(
    (error) => error.message,
    'message',
    contains('32 MiB'),
  );

  for (final name in ['backup_data.json', 'legacy/data.json']) {
    test('restore rejects oversized declared JSON in $name', () async {
      final backup = await createSizedJsonBackup(
        size: 2,
        declaredSize: jsonLimit + 1,
        name: name,
      );

      await expectLater(
        StreamingBackupProcessor.processZipBackupStreaming(backup),
        throwsA(exceedsJsonLimit),
      );
      expect(
        await StreamingBackupProcessor.validateBackupFile(backup),
        isFalse,
      );
      expect(await documents.list(recursive: true).toList(), isEmpty);
    });
  }

  for (final compression in CompressionType.values) {
    test('restore limits actual JSON output for $compression', () async {
      final backup = await createSizedJsonBackup(
        size: jsonLimit + 1,
        declaredSize: 2,
        compression: compression,
      );

      await expectLater(
        StreamingBackupProcessor.processZipBackupStreaming(backup),
        throwsA(exceedsJsonLimit),
      );
      expect(await documents.list(recursive: true).toList(), isEmpty);
    });
  }

  test('restore accepts JSON exactly at the expanded byte limit', () async {
    final backup = await createSizedJsonBackup(size: jsonLimit);

    final data = await StreamingBackupProcessor.processZipBackupStreaming(
      backup,
      extractMediaFiles: false,
    );

    expect(data, isEmpty);
  });

  test('validation and restore reject symbolic link JSON entries', () async {
    final backup = await createSizedJsonBackup(size: 2, symbolicLink: true);

    expect(await StreamingBackupProcessor.validateBackupFile(backup), isFalse);
    await expectLater(
      StreamingBackupProcessor.processZipBackupStreaming(backup),
      throwsException,
    );
    expect(await documents.list(recursive: true).toList(), isEmpty);
  });

  test(
    'restore preserves application files and only writes managed media',
    () async {
      final protectedFiles = [
        'agent_memory.db',
        'thoughtecho.db',
        'settings.json',
        'media/other/private.db',
        'media_evil/images/private.db',
      ];
      for (final name in protectedFiles) {
        final file = File(p.join(documents.path, name));
        await file.parent.create(recursive: true);
        await file.writeAsString('local data');
      }

      final backup = await createBackup({
        'backup_data.json': '{"notes":{"quotes":[]}}',
        'media/images/before.png': 'approved image',
        for (final name in protectedFiles) name: 'untrusted data',
        'media/images/../../agent_memory.db': 'untrusted data',
        r'media\videos\..\..\thoughtecho.db': 'untrusted data',
        '../outside.txt': 'untrusted data',
        'new_private.db': 'untrusted data',
        'media/images/.. /.. /agent_memory.db': 'untrusted data',
        'media/images/photo.png:stream': 'untrusted data',
        'media/images/after.png': 'approved image',
      });

      final data = await StreamingBackupProcessor.processZipBackupStreaming(
        backup,
      );

      expect(data['notes'], {'quotes': []});
      for (final name in protectedFiles) {
        expect(
          await File(p.join(documents.path, name)).readAsString(),
          'local data',
          reason: name,
        );
      }
      expect(
        await File(p.join(documents.path, 'new_private.db')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(documents.parent.path, 'outside.txt')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(documents.path, 'media/images/.. ')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(documents.path, 'media/images/photo.png:stream'))
            .exists(),
        isFalse,
      );
      for (final name in ['before.png', 'after.png']) {
        expect(
          await File(p.join(documents.path, 'media', 'images', name))
              .readAsString(),
          'approved image',
        );
      }
    },
  );

  test('restore supports legacy JSON and normalized media paths', () async {
    final backup = await createBackup({
      'data.json': '{"quotes":[]}',
      'media/images/./photo.png': 'image',
      r'media\videos\clip.mp4': 'video',
      'media/audios/nested/recording.m4a': 'audio',
    });

    final data = await StreamingBackupProcessor.processZipBackupStreaming(
      backup,
    );

    expect(data['quotes'], isEmpty);
    for (final entry in {
      'media/images/photo.png': 'image',
      'media/videos/clip.mp4': 'video',
      'media/audios/nested/recording.m4a': 'audio',
    }.entries) {
      expect(
        await File(p.join(documents.path, entry.key)).readAsString(),
        entry.value,
      );
    }
  });

  test('restore does not follow existing directory or file links', () async {
    final database = File(p.join(documents.path, 'agent_memory.db'));
    await database.writeAsString('local memory');
    final images = Directory(p.join(documents.path, 'media', 'images'));
    await images.create(recursive: true);
    await Link(p.join(images.path, 'linked')).create(documents.path);
    await Link(p.join(images.path, 'photo.png')).create(database.path);
    final backup = await createBackup({
      'backup_data.json': '{}',
      'media/images/linked/agent_memory.db': 'untrusted data',
      'media/images/photo.png': 'untrusted data',
    });

    await StreamingBackupProcessor.processZipBackupStreaming(backup);

    expect(await database.readAsString(), 'local memory');
    expect(
      await Link(p.join(images.path, 'photo.png')).target(),
      database.path,
    );
  });

  test('restore skips symbolic link entries in the archive', () async {
    // ZIP containing backup_data.json and a Unix symbolic link at
    // media/images/link.png targeting ../../agent_memory.db.
    final backup = File(p.join(temporary.path, 'link.zip'));
    await backup.writeAsBytes(base64Decode(
      'UEsDBBQAAAAIAOEpW11Dv6ajBAAAAAIAAAAQAAAAYmFja3VwX2RhdGEuanNvbquuBQBQSwMEFAAAAAAA'
      'AAAhXMg7lDQVAAAAFQAAABUAAABtZWRpYS9pbWFnZXMvbGluay5wbmcuLi8uLi9hZ2VudF9tZW1vcnku'
      'ZGJQSwECFAMUAAAACADhKVtdQ7+mowQAAAACAAAAEAAAAAAAAAAAAAAAgAEAAAAAYmFja3VwX2RhdGEu'
      'anNvblBLAQIUAxQAAAAAAAAAIVzIO5Q0FQAAABUAAAAVAAAAAAAAAAAAAAD/oTIAAABtZWRpYS9pbWFn'
      'ZXMvbGluay5wbmdQSwUGAAAAAAIAAgCBAAAAegAAAAAA',
    ));

    await StreamingBackupProcessor.processZipBackupStreaming(backup.path);

    expect(await documents.list(recursive: true).toList(), isEmpty);
  });

  test('parsing without media extraction leaves Documents untouched', () async {
    final backup = await createBackup({
      'backup_data.json': '{"quotes":[]}',
      'agent_memory.db': 'untrusted data',
      'media/images/photo.png': 'image',
    });

    final data = await StreamingBackupProcessor.processZipBackupStreaming(
      backup,
      extractMediaFiles: false,
    );

    expect(data['quotes'], isEmpty);
    expect(await documents.list().toList(), isEmpty);
  });
}
