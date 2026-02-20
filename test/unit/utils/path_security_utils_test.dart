import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/utils/path_security_utils.dart';

void main() {
  group('PathSecurityUtils', () {
    // Define a base extraction directory for tests using the current working directory
    // to ensure we have a valid absolute base.
    final extractDir = path.join(path.current, 'safe_extract_dir');

    test('allows valid file inside extraction directory', () {
      final targetPath = path.join(extractDir, 'file.txt');
      expect(
        () => PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
        returnsNormally,
      );
    });

    test('allows valid file in subdirectory', () {
      final targetPath = path.join(extractDir, 'subdir', 'file.txt');
      expect(
        () => PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
        returnsNormally,
      );
    });

    test('throws on Zip Slip attempt (parent directory)', () {
      final targetPath = path.join(extractDir, '..', 'evil.txt');
      // targetPath resolves to sibling of extractDir, e.g., .../evil.txt
      expect(
        () => PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
        throwsA(
          isA<PathSecurityException>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          ),
        ),
      );
    });

    test('throws on Zip Slip attempt (multiple levels up)', () {
      final targetPath = path.join(extractDir, '..', '..', 'etc', 'passwd');
      expect(
        () => PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
        throwsA(isA<PathSecurityException>()),
      );
    });

    test('throws on absolute path pointing outside', () {
      // Create a path that is definitely absolute and outside
      final targetPath = path.separator == '/'
          ? '/etc/passwd'
          : r'C:\Windows\System32\drivers\etc\hosts';

      // If extractDir is not a prefix of targetPath, it should fail.
      expect(
        () => PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
        throwsA(isA<PathSecurityException>()),
      );
    });

    test('throws on sibling directory with same prefix (partial match)', () {
      // extractDir: /.../safe_extract_dir
      // targetPath: /.../safe_extract_dir_suffix/file.txt
      // This ensures that "safe_extract_dir_suffix" is not accepted just because it starts with "safe_extract_dir"
      final targetPath = '${extractDir}_suffix${path.separator}file.txt';

      expect(
        () => PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
        throwsA(
          isA<PathSecurityException>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          ),
        ),
      );
    });

    test('normalizes complex paths correctly', () {
      // /safe/dir/./subdir/../file.txt -> /safe/dir/file.txt
      final targetPath = path.join(extractDir, '.', 'subdir', '..', 'file.txt');
      expect(
        () => PathSecurityUtils.validateExtractionPath(targetPath, extractDir),
        returnsNormally,
      );
    });
  });
}
