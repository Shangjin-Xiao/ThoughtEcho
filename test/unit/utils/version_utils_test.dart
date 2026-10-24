import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/version_utils.dart';

void main() {
  group('compareVersions', () {
    test('逐段比数字，不是比字符串', () {
      // 这条是这个工具存在的全部理由：'3.10.0'.compareTo('3.7.0') 是负数。
      expect(compareVersions('3.10.0', '3.7.0'), 1);
      expect(compareVersions('3.7.0', '3.10.0'), -1);
      expect(compareVersions('4.0.0', '3.9.9'), 1);
      expect(compareVersions('10.2.0', '2.10.0'), 1);
      expect(compareVersions('1.100.0', '1.20.0'), 1);
    });

    test('相等与段数不同时短的一方补 0', () {
      expect(compareVersions('4.0.0', '4.0.0'), 0);
      expect(compareVersions('4.0', '4.0.0'), 0);
      expect(compareVersions('4', '4.0.1'), -1);
      expect(compareVersions('4.1', '4.0.9'), 1);
      expect(compareVersions('1.2.3.4', '1.2.3.5'), -1);
      expect(compareVersions('1.2.3.4', '1.2.3'), 1);
      expect(compareVersions('1.2.3.0', '1.2.3'), 0);
    });

    test('剥离 v 前缀、构建号和预发布后缀', () {
      expect(compareVersions('v4.0.0', '4.0.0'), 0);
      expect(compareVersions('V4.0.0', '4.0.0'), 0);
      expect(compareVersions('4.0.0+12', '4.0.0'), 0);
      expect(compareVersions('4.0.0-beta.1', '4.0.0'), 0);
      expect(compareVersions('v4.1.0+3', '4.0.0-rc.2'), 1);
      expect(
        compareVersions('1.0.0-alpha.1+build.123', '1.0.0+build.456'),
        0,
      );
    });

    test('空白字符与换行处理', () {
      expect(compareVersions('  1.2.3 \t\n', '1.2.3'), 0);
      expect(compareVersions(' v2.0.0 ', 'V2.0.0\n'), 0);
    });

    test('坏值与边界条件当 0 处理，不抛异常', () {
      // 版本号来自存储和网络，坏值不该让升级流程崩掉。
      expect(compareVersions('', '0.0.0'), 0);
      expect(compareVersions('', ''), 0);
      expect(compareVersions('abc', '0.0.0'), 0);
      expect(compareVersions('4.x.0', '4.0.0'), 0);
      expect(compareVersions('4.x.1', '4.0.0'), 1);
      expect(compareVersions('1..2', '1.0.2'), 0);
      expect(compareVersions('.1.2', '0.1.2'), 0);
      expect(compareVersions('1.2.', '1.2.0'), 0);
    });
  });
}
