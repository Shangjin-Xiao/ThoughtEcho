import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/version_utils.dart';

void main() {
  group('compareVersions', () {
    test('逐段比数字，不是比字符串', () {
      // 这条是这个工具存在的全部理由：'3.10.0'.compareTo('3.7.0') 是负数。
      expect(compareVersions('3.10.0', '3.7.0'), 1);
      expect(compareVersions('3.7.0', '3.10.0'), -1);
      expect(compareVersions('4.0.0', '3.9.9'), 1);
    });

    test('相等与段数不同时短的一方补 0', () {
      expect(compareVersions('4.0.0', '4.0.0'), 0);
      expect(compareVersions('4.0', '4.0.0'), 0);
      expect(compareVersions('4', '4.0.1'), -1);
      expect(compareVersions('4.1', '4.0.9'), 1);
    });

    test('剥离 v 前缀、构建号和预发布后缀', () {
      expect(compareVersions('v4.0.0', '4.0.0'), 0);
      expect(compareVersions('4.0.0+12', '4.0.0'), 0);
      expect(compareVersions('4.0.0-beta.1', '4.0.0'), 0);
      expect(compareVersions('v4.1.0+3', '4.0.0-rc.2'), 1);
    });

    test('坏值当 0 处理，不抛异常', () {
      // 版本号来自存储和网络，坏值不该让升级流程崩掉。
      expect(compareVersions('', '0.0.0'), 0);
      expect(compareVersions('abc', '0.0.0'), 0);
      expect(compareVersions('4.x.0', '4.0.0'), 0);
      expect(compareVersions('4.x.1', '4.0.0'), 1);
    });
  });
}
