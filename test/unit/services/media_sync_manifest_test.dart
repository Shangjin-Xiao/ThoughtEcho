import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/media_sync_manifest.dart';
import 'package:thoughtecho/utils/backup_media_processor.dart';

void main() {
  group('MediaSyncManifest', () {
    test('parses a versioned manifest and normalizes separators', () {
      final manifest = MediaSyncManifest.tryParse({
        'version': 1,
        'files': {'images\\photo.jpg': 42},
      });

      expect(manifest, isNotNull);
      expect(manifest!.fileSizes, {'images/photo.jpg': 42});
    });

    test('rejects unknown versions and unsafe paths', () {
      expect(
        MediaSyncManifest.tryParse({'version': 2, 'files': {}}),
        isNull,
      );
      expect(
        MediaSyncManifest.tryParse({
          'version': 1,
          'files': {'../secret.jpg': 1},
        }),
        isNull,
      );
    });

    test('transfers only missing or size-changed files', () {
      const manifest = MediaSyncManifest({
        'images/same.jpg': 10,
        'audios/changed.m4a': 5,
      });

      expect(manifest.shouldTransfer('media/images/same.jpg', 10), isFalse);
      expect(manifest.shouldTransfer('media/audios/changed.m4a', 8), isTrue);
      expect(manifest.shouldTransfer('media/videos/missing.mp4', 20), isTrue);
    });

    test('scans files relative to media root', () async {
      final root = await Directory.systemTemp.createTemp('media_manifest_');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/images/photo.jpg');
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);

      final manifest = await MediaSyncManifest.scan(root);

      expect(manifest.fileSizes, {'images/photo.jpg': 3});
    });
  });

  group('BackupMediaProcessor incremental filtering', () {
    test('keeps all media when receiver manifest is unavailable', () async {
      final root = await Directory.systemTemp.createTemp('media_filter_');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/photo.jpg');
      await file.writeAsBytes([1, 2, 3]);
      final entries = {'media/images/photo.jpg': file.path};

      final filtered = await BackupMediaProcessor.filterArchiveEntries(
        entries,
        receiverManifest: null,
      );

      expect(filtered, entries);
    });

    test('keeps only missing or size-changed media', () async {
      final root = await Directory.systemTemp.createTemp('media_filter_');
      addTearDown(() => root.delete(recursive: true));
      final same = File('${root.path}/same.jpg');
      final changed = File('${root.path}/changed.m4a');
      final missing = File('${root.path}/missing.mp4');
      await same.writeAsBytes([1, 2, 3]);
      await changed.writeAsBytes([1, 2, 3, 4]);
      await missing.writeAsBytes([1, 2]);

      final filtered = await BackupMediaProcessor.filterArchiveEntries(
        {
          'media/images/same.jpg': same.path,
          'media/audios/changed.m4a': changed.path,
          'media/videos/missing.mp4': missing.path,
        },
        receiverManifest: const MediaSyncManifest({
          'images/same.jpg': 3,
          'audios/changed.m4a': 1,
        }),
      );

      expect(filtered.keys, {
        'media/audios/changed.m4a',
        'media/videos/missing.mp4',
      });
    });
  });
}
