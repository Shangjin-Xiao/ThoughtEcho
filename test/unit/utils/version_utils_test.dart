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

  group('compareSemver', () {
    test('核心版本差异直接决定大小', () {
      expect(compareSemver('4.0.0', '3.10.0'), 1);
      expect(compareSemver('3.10.0', '4.0.0'), -1);
      expect(compareSemver('4.0.0-beta.1', '1.0.0+12'), 1);
      expect(compareSemver('v4.0.0', '1.0.0+12'), 1);
    });

    test('正式版高于相同核心的预发布版', () {
      expect(compareSemver('4.0.0', '4.0.0-beta.1'), 1);
      expect(compareSemver('4.0.0-beta.1', '4.0.0'), -1);
      expect(compareSemver('4.0.0', '4.0.0-rc.1'), 1);
    });

    test('预发布版本按段落精确排序', () {
      expect(compareSemver('4.0.0-beta.2', '4.0.0-beta.1'), 1);
      expect(compareSemver('4.0.0-beta.1', '4.0.0-beta.2'), -1);
      expect(compareSemver('4.0.0-rc.1', '4.0.0-beta.9'), 1);
      expect(compareSemver('4.0.0-alpha.1', '4.0.0-beta.1'), -1);
      expect(compareSemver('4.0.0-beta.1', '4.0.0-beta.1'), 0);
    });

    test('核心与预发布相同时构建元数据区分演进', () {
      expect(compareSemver('1.0.0+12', '1.0.0+11'), 1);
      expect(compareSemver('1.0.0+11', '1.0.0+12'), -1);
      expect(compareSemver('1.0.0+12', '1.0.0+12'), 0);
      expect(compareSemver('4.0.0+2', '4.0.0+1'), 1);
      expect(compareSemver('4.0.0+12', '4.0.0'), 1);
    });

    test('兼容历史纯数字构建号', () {
      expect(compareSemver('12', '11'), 1);
      expect(compareSemver('11', '12'), -1);
      expect(compareSemver('12', '12'), 0);
      expect(compareSemver('4.0.0', '12'), 1);
      expect(compareSemver('4.0.0-beta.1', '12'), 1);
      expect(compareSemver('12', '4.0.0'), -1);
    });

    test('VersionUtils 命名空间调用等价', () {
      expect(VersionUtils.compareSemver('4.0.0-beta.1', '12'), 1);
      expect(VersionUtils.compareVersions('4.0.0+12', '4.0.0'), 0);
      expect(
        VersionUtils.compareVersions('4.0.0+12', '4.0.0', compareSemver: true),
        1,
      );
    });
  });

  group('normalizeVersion', () {
    test('处理 null 与空字符串', () {
      expect(normalizeVersion(null), '0.0.0');
      expect(normalizeVersion(''), '0.0.0');
      expect(normalizeVersion('   '), '0.0.0');
    });

    test('剥离 v 前缀', () {
      expect(normalizeVersion('v4.0.0'), '4.0.0');
      expect(normalizeVersion('V4.0.0-beta.1'), '4.0.0-beta.1');
    });

    test('规范化存量纯数字历史构建号', () {
      expect(normalizeVersion('0'), '0.0.0');
      expect(normalizeVersion('11'), '1.0.0+11');
      expect(normalizeVersion('12'), '1.0.0+12');
    });

    test('保留标准 semver 格式', () {
      expect(normalizeVersion('4.0.0-beta.1'), '4.0.0-beta.1');
      expect(normalizeVersion('4.0.0+12'), '4.0.0+12');
      expect(normalizeVersion('3.10.0+11'), '3.10.0+11');
    });
  });

  group('formatVersion', () {
    test('组合标准 version 与纯数字 buildNumber', () {
      expect(
        formatVersion(version: '4.1.0', buildNumber: '1'),
        '4.1.0+1',
      );
      expect(
        formatVersion(version: '1.0.0', buildNumber: '12'),
        '1.0.0+12',
      );
      expect(
        formatVersion(version: '4.0.0', buildNumber: '12'),
        '4.0.0+12',
      );
    });

    test('buildNumber 已为完整 semver 时优先采用 buildNumber', () {
      expect(
        formatVersion(version: '4.0.0', buildNumber: '4.0.0-beta.1'),
        '4.0.0-beta.1',
      );
      expect(
        formatVersion(version: '1.0.0', buildNumber: '4.0.0-beta.1'),
        '4.0.0-beta.1',
      );
      expect(
        formatVersion(version: '', buildNumber: '4.0.0-beta.1'),
        '4.0.0-beta.1',
      );
      expect(
        formatVersion(version: '1.0.0', buildNumber: 'v4.0.0'),
        '4.0.0',
      );
      expect(
        formatVersion(version: '', buildNumber: '4.0.0+12'),
        '4.0.0+12',
      );
    });

    test('仅有 buildNumber 且为纯数字时安全降级', () {
      expect(
        formatVersion(version: '', buildNumber: '12'),
        '1.0.0+12',
      );
    });

    test('buildNumber 为预发布标识时拼接短横线', () {
      expect(
        formatVersion(version: '4.0.0', buildNumber: 'beta.1'),
        '4.0.0-beta.1',
      );
      expect(
        formatVersion(version: '4.0.0', buildNumber: 'rc.2'),
        '4.0.0-rc.2',
      );
    });

    test('全空时回退为 0.0.0', () {
      expect(formatVersion(version: null, buildNumber: null), '0.0.0');
      expect(formatVersion(version: '', buildNumber: ''), '0.0.0');
    });
  });
}
