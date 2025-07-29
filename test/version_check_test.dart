import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/version_check_service.dart';

void main() {
  group('VersionInfo', () {
    test('should compare versions correctly', () {
      // 测试版本比较逻辑
      final testData = [
        {'current': '1.0.0', 'latest': '1.0.1', 'hasUpdate': true},
        {'current': '1.0.0', 'latest': '1.0.0', 'hasUpdate': false},
        {'current': '1.0.1', 'latest': '1.0.0', 'hasUpdate': false},
        {'current': '1.0.0', 'latest': '2.0.0', 'hasUpdate': true},
        {'current': 'v1.0.0', 'latest': 'v1.0.1', 'hasUpdate': true},
      ];

      for (final data in testData) {
        final mockJson = {
          'tag_name': data['latest'],
          'html_url': 'https://github.com/test/test/releases/latest',
          'body': 'Test release notes',
          'published_at': '2024-01-01T00:00:00Z',
        };

        final versionInfo = VersionInfo.fromJson(mockJson, data['current'] as String);
        
        expect(
          versionInfo.hasUpdate,
          data['hasUpdate'],
          reason: 'Current: ${data['current']}, Latest: ${data['latest']}',
        );
      }
    });

    test('should parse GitHub API response correctly', () {
      const mockResponse = {
        'tag_name': 'v1.2.0',
        'html_url': 'https://github.com/Shangjin-Xiao/ThoughtEcho/releases/tag/v1.2.0',
        'body': '## 新功能\n- 添加了版本检查功能\n- 优化了UI界面',
        'published_at': '2024-07-29T10:00:00Z',
      };

      final versionInfo = VersionInfo.fromJson(mockResponse, '1.0.0');

      expect(versionInfo.currentVersion, '1.0.0');
      expect(versionInfo.latestVersion, 'v1.2.0');
      expect(versionInfo.hasUpdate, true);
      expect(versionInfo.downloadUrl, 'https://github.com/Shangjin-Xiao/ThoughtEcho/releases/tag/v1.2.0');
      expect(versionInfo.releaseNotes, '## 新功能\n- 添加了版本检查功能\n- 优化了UI界面');
    });
  });

  group('VersionCheckService', () {
    test('should handle timeout correctly', () async {
      // 这个测试需要网络连接，在实际环境中可能会失败
      // 主要用于验证超时处理逻辑
      try {
        await VersionCheckService.checkForUpdates(
          timeout: const Duration(milliseconds: 1), // 极短超时
        );
      } catch (e) {
        expect(e, isA<VersionCheckTimeoutException>());
      }
    });
  });
}
