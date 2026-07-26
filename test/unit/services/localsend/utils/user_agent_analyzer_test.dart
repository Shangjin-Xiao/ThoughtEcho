import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/utils/user_agent_analyzer.dart';

void main() {
  group('UserAgentAnalyzer', () {
    late UserAgentAnalyzer analyzer;

    setUp(() {
      analyzer = UserAgentAnalyzer();
    });

    group('getBrowser', () {
      test('identifies Firefox', () {
        expect(
            analyzer.getBrowser(
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:90.0) Gecko/20100101 Firefox/90.0'),
            'Firefox');
      });

      test('identifies Chrome', () {
        expect(
            analyzer.getBrowser(
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'),
            'Chrome');
      });

      test('identifies Safari', () {
        expect(
            analyzer.getBrowser(
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15'),
            'Safari');
      });

      test('identifies Opera', () {
        expect(
            analyzer.getBrowser(
                'Opera/9.80 (Windows NT 6.0) Presto/2.12.388 Version/12.14'),
            'Opera');
        expect(
            analyzer.getBrowser(
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36 OPR/77.0.4054.277'),
            'Opera');
      });

      test('identifies Edge', () {
        expect(
            analyzer.getBrowser(
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36 Edg/91.0.864.59'),
            'Edge');
      });

      test('identifies Internet Explorer', () {
        expect(
            analyzer.getBrowser(
                'Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)'),
            'Internet Explorer');
        expect(
            analyzer.getBrowser(
                'Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko'),
            'Internet Explorer');
      });

      test('identifies Insomnia', () {
        expect(analyzer.getBrowser('insomnia/2021.4.1'), 'Insomnia');
      });

      test('returns null for unknown browser', () {
        expect(analyzer.getBrowser('SomeUnknownBrowser/1.0'), isNull);
      });
    });

    group('getOS', () {
      test('identifies Windows', () {
        expect(
            analyzer.getOS('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Win/10'),
            'Windows');
      });

      test('identifies Android', () {
        expect(analyzer.getOS('Mozilla/5.0 (Linux; Android 10; SM-G981B)'),
            'Android');
      });

      test('identifies macOS', () {
        expect(
            analyzer.getOS('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'),
            'macOS');
      });

      test('identifies iOS', () {
        expect(
            analyzer.getOS(
                'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)'),
            'iOS');
        expect(analyzer.getOS('Mozilla/5.0 (iPad; CPU OS 14_6 like Mac OS X)'),
            'iOS');
        expect(
            analyzer.getOS(
                'Mozilla/5.0 (iPod touch; CPU iPhone OS 14_6 like Mac OS X)'),
            'iOS');
      });

      test('identifies Linux', () {
        expect(
            analyzer.getOS('Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:90.0)'),
            'Linux');
      });

      test('returns null for unknown OS', () {
        expect(analyzer.getOS('SomeUnknownOS/1.0'), isNull);
      });
    });
  });
}
