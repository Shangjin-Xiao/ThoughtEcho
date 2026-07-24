import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/utils/ip_helper.dart';

void main() {
  group('StringIpExt', () {
    test('visualId extracts the last part of an IPv4 address', () {
      expect('192.168.1.100'.visualId, '100');
      expect('10.0.0.1'.visualId, '1');
      expect('172.16.254.1'.visualId, '1');
    });

    test('visualId handles strings without dots', () {
      expect('localhost'.visualId, 'localhost');
      expect('12345'.visualId, '12345');
    });

    test('visualId handles empty string', () {
      expect(''.visualId, '');
    });
  });

  group('IpHelper', () {
    group('rankIpAddresses', () {
      test('places primary address first', () {
        final addresses = ['192.168.1.5', '10.0.0.5', '192.168.1.100'];
        final primary = '10.0.0.5';

        final result = IpHelper.rankIpAddresses(addresses, primary);

        expect(result.first, primary);
        expect(
          result,
          ['10.0.0.5', '192.168.1.5', '192.168.1.100'],
        ); // order of others is preserved by sorted (stable sort in collection package)
      });

      test('places addresses ending with .1 last', () {
        final addresses = [
          '192.168.1.1',
          '192.168.1.5',
          '10.0.0.1',
          '10.0.0.5',
        ];
        final primary = '192.168.1.100'; // not in list, doesn't matter

        final result = IpHelper.rankIpAddresses(addresses, primary);

        // '192.168.1.5' and '10.0.0.5' get score 1
        // '192.168.1.1' and '10.0.0.1' get score 0
        expect(result, ['192.168.1.5', '10.0.0.5', '192.168.1.1', '10.0.0.1']);
      });

      test('places primary address first even if it ends with .1', () {
        final addresses = [
          '192.168.1.1',
          '192.168.1.5',
          '10.0.0.1',
          '10.0.0.5',
        ];
        final primary = '192.168.1.1';

        final result = IpHelper.rankIpAddresses(addresses, primary);

        expect(result.first, primary);
        expect(result, ['192.168.1.1', '192.168.1.5', '10.0.0.5', '10.0.0.1']);
      });

      test('handles empty list', () {
        final result = IpHelper.rankIpAddresses([], '192.168.1.1');
        expect(result, isEmpty);
      });

      test('handles list with only one element', () {
        final result = IpHelper.rankIpAddresses(['192.168.1.5'], '192.168.1.5');
        expect(result, ['192.168.1.5']);
      });

      test('handles primary address not in the list', () {
        final addresses = ['192.168.1.1', '192.168.1.5'];
        final primary = '10.0.0.5';

        final result = IpHelper.rankIpAddresses(addresses, primary);

        expect(result, ['192.168.1.5', '192.168.1.1']);
      });
    });
  });
}
