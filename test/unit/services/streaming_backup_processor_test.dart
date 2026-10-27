import 'dart:convert';
import 'dart:io';

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
