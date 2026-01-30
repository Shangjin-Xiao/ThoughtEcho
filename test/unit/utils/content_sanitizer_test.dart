import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/content_sanitizer.dart';

void main() {
  group('ContentSanitizer', () {
    const expectedCspContent =
        "default-src 'none'; script-src 'none'; object-src 'none'; style-src 'unsafe-inline'; img-src data: https:; font-src data: https:; connect-src 'none'; media-src 'none'; frame-src 'none'; child-src 'none';";
    const expectedCspTag =
        '<meta http-equiv="Content-Security-Policy" content="$expectedCspContent">';

    test('injectCsp returns unchanged HTML if CSP already exists', () {
      const html = '''
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="Content-Security-Policy" content="script-src 'self'">
    <title>Test</title>
</head>
<body>Hello</body>
</html>
''';
      expect(ContentSanitizer.injectCsp(html), html);
    });

    test('injectCsp injects CSP into existing <head>', () {
      const html = '''
<!DOCTYPE html>
<html>
<head>
    <title>Test</title>
</head>
<body>Hello</body>
</html>
''';
      final result = ContentSanitizer.injectCsp(html);
      expect(result, contains(expectedCspTag));
      expect(result,
          contains('<head>\n    $expectedCspTag\n    <title>Test</title>'));
    });

    test('injectCsp injects CSP into <head> with attributes', () {
      const html = '''
<!DOCTYPE html>
<html>
<head profile="http://example.com">
    <title>Test</title>
</head>
<body>Hello</body>
</html>
''';
      final result = ContentSanitizer.injectCsp(html);
      expect(result, contains(expectedCspTag));
      expect(
          result,
          contains(
              '<head profile="http://example.com">\n    $expectedCspTag\n    <title>Test</title>'));
    });

    test(
        'injectCsp creates <head> and injects CSP if <html> exists but no <head>',
        () {
      const html = '''
<!DOCTYPE html>
<html>
<body>Hello</body>
</html>
''';
      final result = ContentSanitizer.injectCsp(html);
      expect(result, contains(expectedCspTag));
      expect(result,
          contains('<html>\n<head>\n    $expectedCspTag\n</head>\n<body>'));
    });

    test('injectCsp creates <head> when <html> has attributes', () {
      const html = '''
<!DOCTYPE html>
<html lang="en">
<body>Hello</body>
</html>
''';
      final result = ContentSanitizer.injectCsp(html);
      expect(result, contains(expectedCspTag));
      expect(
          result,
          contains(
              '<html lang="en">\n<head>\n    $expectedCspTag\n</head>\n<body>'));
    });

    test('injectCsp prepends CSP if no html structure exists', () {
      const html = '<div>Hello</div>';
      final result = ContentSanitizer.injectCsp(html);
      expect(result, startsWith('$expectedCspTag\n<div>Hello</div>'));
    });

    test('injectCsp handles uppercase tags', () {
      const html = '''
<!DOCTYPE html>
<HTML>
<HEAD>
    <TITLE>Test</TITLE>
</HEAD>
<BODY>Hello</BODY>
</HTML>
''';
      final result = ContentSanitizer.injectCsp(html);
      expect(result, contains(expectedCspTag));
      // With mapped replacement, it preserves case of the matched tag
      expect(result, contains('<HEAD>\n    $expectedCspTag'));
    });

    test('injectCsp handles empty string', () {
      expect(ContentSanitizer.injectCsp(''), '');
    });
  });
}
