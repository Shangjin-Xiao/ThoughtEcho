import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/utils/path_security_utils.dart';
import 'package:thoughtecho/utils/zip_stream_processor.dart';

void main() {
  group('Zip Slip Security Unit Tests (R3.1)', () {
    late Directory tempDir;
    late String extractDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('zip_slip_test_');
      extractDir = path.join(tempDir.path, 'target_extract');
      await Directory(extractDir).create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('PathSecurityUtils.sanitizeZipEntryName', () {
      test('converts Windows backslashes to POSIX slashes', () {
        expect(
          PathSecurityUtils.sanitizeZipEntryName(r'media\images\photo.jpg'),
          equals('media/images/photo.jpg'),
        );
      });

      test('removes leading slashes from zip entry names', () {
        expect(
          PathSecurityUtils.sanitizeZipEntryName('/etc/passwd'),
          equals('etc/passwd'),
        );
        expect(
          PathSecurityUtils.sanitizeZipEntryName(r'\Windows\System32\cmd.exe'),
          equals('Windows/System32/cmd.exe'),
        );
        expect(
          PathSecurityUtils.sanitizeZipEntryName('///root/secret.txt'),
          equals('root/secret.txt'),
        );
      });
    });

    group('Zip Slip Defense with POSIX Slashes (/)', () {
      test('blocks simple parent directory traversal (../evil.txt)', () {
        final maliciousPath = path.join(extractDir, '..', 'evil.txt');
        expect(
          () => PathSecurityUtils.validateExtractionPath(
              maliciousPath, extractDir),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          )),
        );
      });

      test('blocks deep parent directory traversal (../../../../etc/passwd)',
          () {
        final maliciousPath =
            path.join(extractDir, '..', '..', '..', 'etc', 'passwd');
        expect(
          () => PathSecurityUtils.validateExtractionPath(
              maliciousPath, extractDir),
          throwsA(isA<Exception>()),
        );
      });

      test('blocks nested traversal (sub/dir/../../../../evil.txt)', () {
        final maliciousPath =
            path.join(extractDir, 'sub', 'dir', '..', '..', '..', 'evil.txt');
        expect(
          () => PathSecurityUtils.validateExtractionPath(
              maliciousPath, extractDir),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Zip Slip Defense with Windows Backslashes (\\)', () {
      test(r'blocks Windows backslash traversal (..\evil.txt)', () {
        final rawEntry = r'..\evil.txt';
        final posixEntry = PathSecurityUtils.sanitizeZipEntryName(rawEntry);
        final platformSubPath = posixEntry.replaceAll('/', path.separator);
        final targetPath = path.join(extractDir, platformSubPath);

        expect(
          () =>
              PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
          throwsA(isA<Exception>()),
        );
      });

      test(
          r'blocks Windows deep backslash traversal (..\..\Windows\System32\cmd.exe)',
          () {
        final rawEntry = r'..\..\Windows\System32\cmd.exe';
        final posixEntry = PathSecurityUtils.sanitizeZipEntryName(rawEntry);
        final platformSubPath = posixEntry.replaceAll('/', path.separator);
        final targetPath = path.join(extractDir, platformSubPath);

        expect(
          () =>
              PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
          throwsA(isA<Exception>()),
        );
      });

      test(r'blocks mixed slash traversal (../..\evil.txt and ..\../evil.txt)',
          () {
        final entries = [
          r'../..\evil.txt',
          r'..\../evil.txt',
          r'sub/..\../evil.txt',
        ];
        for (final entry in entries) {
          final posixEntry = PathSecurityUtils.sanitizeZipEntryName(entry);
          final platformSubPath = posixEntry.replaceAll('/', path.separator);
          final targetPath = path.join(extractDir, platformSubPath);

          expect(
            () => PathSecurityUtils.validateExtractionPath(
                targetPath, extractDir),
            throwsA(isA<Exception>()),
            reason: 'Failed to block mixed traversal entry: $entry',
          );
        }
      });
    });

    group('Partial Directory Match Attack Prevention', () {
      test('blocks sibling directory with matching prefix', () {
        final siblingPath = '${extractDir}_evil${path.separator}file.txt';
        expect(
          () =>
              PathSecurityUtils.validateExtractionPath(siblingPath, extractDir),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          )),
        );
      });
    });

    group('Cross-Platform Safe Path Extraction', () {
      test('allows legitimate nested files with POSIX slashes', () {
        final targetPath =
            path.join(extractDir, 'media', 'images', 'photo.jpg');
        expect(
          () =>
              PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
          returnsNormally,
        );
      });

      test('allows legitimate nested files with sanitized Windows backslashes',
          () {
        final rawEntry = r'media\images\photo.jpg';
        final posixEntry = PathSecurityUtils.sanitizeZipEntryName(rawEntry);
        final platformSubPath = posixEntry.replaceAll('/', path.separator);
        final targetPath = path.join(extractDir, platformSubPath);

        expect(
          () =>
              PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
          returnsNormally,
        );
        expect(
          targetPath,
          equals(path.join(extractDir, 'media', 'images', 'photo.jpg')),
        );
      });
    });

    group('Zip Archive End-to-End Extraction Security Integration', () {
      test('ZipStreamProcessor rejects archive containing Zip Slip entry',
          () async {
        final zipFile = File(path.join(tempDir.path, 'malicious.zip'));
        final archive = Archive();

        final safeData = utf8.encode('safe content');
        archive
            .addFile(ArchiveFile('media/safe.txt', safeData.length, safeData));

        final evilData = utf8.encode('evil content');
        archive.addFile(
            ArchiveFile('../outside_evil.txt', evilData.length, evilData));

        final zipBytes = ZipEncoder().encode(archive);
        zipFile.writeAsBytesSync(zipBytes);

        // Attempt streaming extraction - must throw Zip Slip security exception
        expect(
          ZipStreamProcessor.extractZipStreaming(zipFile.path, extractDir),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          )),
        );

        // Verify outside file was NOT created
        final outsideFile = File(path.join(tempDir.path, 'outside_evil.txt'));
        expect(await outsideFile.exists(), isFalse);
      });
    });
  });
}
