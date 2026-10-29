import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';

const _maxSyncBytes = 32 * 1024 * 1024;
const _payload = {'categories': <dynamic>[], 'quotes': <dynamic>[]};

Uint8List _syncZip(List<int> data,
        {String name = 'backup_data.json',
        CompressionType compression = CompressionType.deflate}) =>
    ZipEncoder().encodeBytes(
      Archive()
        ..addFile(
            ArchiveFile(name, data.length, data)..compression = compression),
      level: 9,
    );

// Forge both size declarations without changing the compressed data. The output
// budget must hold even when ZIP metadata lies about the expansion size.
void _setDeclaredSize(Uint8List zip, int size) {
  final directory = ZipDirectory()..read(InputMemoryStream(zip));
  final header = directory.fileHeaders.single;
  final view = ByteData.sublistView(zip);
  view.setUint32(header.localHeaderOffset + 22, size, Endian.little);
  view.setUint32(directory.centralDirectoryOffset + 24, size, Endian.little);
}

Matcher get _throwsSizeLimit => throwsA(isA<StateError>().having(
      (error) => error.message,
      'message',
      contains('32 MiB'),
    ));

void main() {
  for (final name in ['backup_data.json', 'data.json', r'folder\data.json']) {
    test('decodes compatible sync entry $name', () {
      expect(
        WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
          _syncZip(utf8.encode(jsonEncode(_payload)), name: name),
        ),
        _payload,
      );
    });
  }

  for (final compression in [CompressionType.none, CompressionType.bzip2]) {
    test('decodes sync JSON with $compression compression', () {
      expect(
        WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
          _syncZip(utf8.encode(jsonEncode(_payload)), compression: compression),
        ),
        _payload,
      );
    });
  }

  test('rejects oversized declared JSON before decoding its valid contents',
      () {
    final zip = _syncZip(utf8.encode(jsonEncode(_payload)));
    _setDeclaredSize(zip, _maxSyncBytes + 1);

    expect(
      () => WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(zip),
      _throwsSizeLimit,
    );
  });

  for (final compression in [CompressionType.deflate, CompressionType.bzip2]) {
    test('rejects actual expansion with forged $compression size in an isolate',
        () async {
      final data = Uint8List(_maxSyncBytes + 1)
        ..fillRange(0, _maxSyncBytes + 1, 32);
      data.setAll(0, utf8.encode(jsonEncode(_payload)));
      final zip = _syncZip(data, compression: compression);
      _setDeclaredSize(zip, 1);
      expect(zip.length, lessThan(100 * 1024));

      // The size error must also retain its type across the production isolate
      // boundary, so it cannot enter corrupted-file archive/rebuild recovery.
      await expectLater(
        compute(
            WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting, zip),
        _throwsSizeLimit,
      );
    });
  }

  test('accepts expanded JSON exactly at the byte budget', () {
    final data = Uint8List(_maxSyncBytes)..fillRange(0, _maxSyncBytes, 32);
    data.setAll(0, utf8.encode(jsonEncode(_payload)));

    expect(
      WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
          _syncZip(data)),
      _payload,
    );
  });

  test('ignores unrelated symlink contents while selecting sync JSON', () {
    final archive = Archive()
      ..addFile(ArchiveFile('unused', 1, [255])..mode = 0xa1ff)
      ..addFile(ArchiveFile.string('backup_data.json', jsonEncode(_payload)));
    final zip = ZipEncoder().encodeBytes(archive);
    final directory = ZipDirectory()..read(InputMemoryStream(zip));
    // Mark the first entry as a Unix symlink, which ZipDecoder eagerly reads.
    final view = ByteData.sublistView(zip);
    view.setUint16(directory.centralDirectoryOffset + 4, 0x0314, Endian.little);
    view.setUint32(
        directory.centralDirectoryOffset + 38, 0xa1ff0000, Endian.little);

    expect(
      WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(zip),
      _payload,
    );
  });

  test('rejects oversized archive bytes before reading ZIP metadata', () {
    expect(
      () => WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
        Uint8List(_maxSyncBytes + 1),
      ),
      _throwsSizeLimit,
    );
  });

  test('still rejects malformed JSON and sync data without required lists', () {
    for (final data in ['{', '{"categories": []}']) {
      expect(
        () => WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
          _syncZip(utf8.encode(data)),
        ),
        throwsException,
      );
    }
  });
}
