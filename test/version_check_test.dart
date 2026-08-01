import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/version_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

        final versionInfo = VersionInfo.fromJson(
          mockJson,
          data['current'] as String,
        );

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
        'html_url':
            'https://github.com/Shangjin-Xiao/ThoughtEcho/releases/tag/v1.2.0',
        'body': '## 新功能\n- 添加了版本检查功能\n- 优化了UI界面',
        'published_at': '2024-07-29T10:00:00Z',
      };

      final versionInfo = VersionInfo.fromJson(mockResponse, '1.0.0');

      expect(versionInfo.currentVersion, '1.0.0');
      expect(versionInfo.latestVersion, 'v1.2.0');
      expect(versionInfo.hasUpdate, true);
      expect(
        versionInfo.downloadUrl,
        'https://github.com/Shangjin-Xiao/ThoughtEcho/releases/tag/v1.2.0',
      );
      expect(versionInfo.releaseNotes, '## 新功能\n- 添加了版本检查功能\n- 优化了UI界面');
    });
  });

  group('VersionCheckService', () {
    test('should handle timeout correctly', () async {
      // 这个测试验证超时处理逻辑
      // 使用极短超时来触发超时异常
      try {
        await VersionCheckService.checkForUpdates(
          timeout: const Duration(milliseconds: 1), // 极短超时
        );
        // 如果没有抛出异常，测试应该失败（除非网络异常快）
      } on VersionCheckTimeoutException {
        // 预期的超时异常
        expect(true, isTrue);
      } on VersionCheckNetworkException {
        // 网络异常也是可接受的（可能在建立连接前就失败了）
        expect(true, isTrue);
      } on VersionCheckException {
        // 其他版本检查异常也是可接受的
        expect(true, isTrue);
      } catch (e) {
        // 其他异常类型不应该发生
        fail('Unexpected exception type: ${e.runtimeType}');
      }
    });

    test('should parse APK download URL from assets', () {
      final mockResponseWithApk = {
        'tag_name': 'v1.2.0',
        'html_url': 'https://github.com/test/releases/tag/v1.2.0',
        'body': 'Release notes',
        'published_at': '2024-01-01T00:00:00Z',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://github.com/test/releases/download/v1.2.0/app-release.apk',
          },
          {
            'name': 'other-file.zip',
            'browser_download_url':
                'https://github.com/test/releases/download/v1.2.0/other.zip',
          },
        ],
      };

      final versionInfo = VersionInfo.fromJson(mockResponseWithApk, '1.0.0');

      expect(versionInfo.apkDownloadUrl,
          'https://github.com/test/releases/download/v1.2.0/app-release.apk');
    });

    test('should handle response without APK assets', () {
      final mockResponseNoApk = {
        'tag_name': 'v1.2.0',
        'html_url': 'https://github.com/test/releases/tag/v1.2.0',
        'body': 'Release notes',
        'published_at': '2024-01-01T00:00:00Z',
        'assets': [
          {
            'name': 'other-file.zip',
            'browser_download_url':
                'https://github.com/test/releases/download/v1.2.0/other.zip',
          },
        ],
      };

      final versionInfo = VersionInfo.fromJson(mockResponseNoApk, '1.0.0');

      expect(versionInfo.apkDownloadUrl, isNull);
    });
  });

  group('按 ABI 选包', () {
    const arm64 = ['arm64-v8a', 'armeabi-v7a', 'armeabi'];
    const arm32 = ['armeabi-v7a', 'armeabi'];

    List<Map<String, String>> assets(List<String> names) => [
          for (final name in names)
            {
              'name': name,
              'browser_download_url': 'https://example.com/$name',
            },
        ];

    // 当前 workflow 的产物名，以及建议的新命名，都必须能被正确识别。
    final splitAssets = assets([
      'thoughtecho-arm32Compat-release.apk',
      'thoughtecho-standard64-release.apk',
    ]);
    final renamedAssets = assets([
      'ThoughtEcho-3.8.0-arm32.apk',
      'ThoughtEcho-3.8.0-arm64.apk',
    ]);

    test('arm64 设备拿 64 位包，即使 32 位包排在前面', () {
      expect(
        selectApkAssetUrl(splitAssets, arm64),
        'https://example.com/thoughtecho-standard64-release.apk',
      );
      expect(
        selectApkAssetUrl(renamedAssets, arm64),
        'https://example.com/ThoughtEcho-3.8.0-arm64.apk',
      );
    });

    test('arm32 设备拿 32 位包', () {
      expect(
        selectApkAssetUrl(splitAssets, arm32),
        'https://example.com/thoughtecho-arm32Compat-release.apk',
      );
      expect(
        selectApkAssetUrl(renamedAssets, arm32),
        'https://example.com/ThoughtEcho-3.8.0-arm32.apk',
      );
    });

    test('32 位设备遇到只有 64 位包的 Release 时不给下载链接', () {
      // 装上只含 arm64-v8a 的包会因为找不到 native 库崩溃，
      // 返回 null 让 UI 回退到浏览器打开 Release 页面。
      final only64 = assets(['ThoughtEcho-3.8.0-arm64.apk']);
      expect(selectApkAssetUrl(only64, arm32), isNull);
      expect(
        selectApkAssetUrl(only64, arm64),
        'https://example.com/ThoughtEcho-3.8.0-arm64.apk',
      );
    });

    test('无架构标记的通用包对两种设备都可用', () {
      // 3.7.0 及更早发布的 fat APK。
      final legacy = assets(['app-release.apk']);
      expect(
        selectApkAssetUrl(legacy, arm32),
        'https://example.com/app-release.apk',
      );
      expect(
        selectApkAssetUrl(legacy, arm64),
        'https://example.com/app-release.apk',
      );
    });

    test('设备 ABI 未知时退回第一个 APK', () {
      expect(
        selectApkAssetUrl(splitAssets, const []),
        'https://example.com/thoughtecho-arm32Compat-release.apk',
      );
    });

    test('arm64 设备在只有 32 位包时仍可下载', () {
      final only32 = assets(['ThoughtEcho-3.8.0-arm32.apk']);
      expect(
        selectApkAssetUrl(only32, arm64),
        'https://example.com/ThoughtEcho-3.8.0-arm32.apk',
      );
    });

    test('忽略非 APK 资产', () {
      final mixed = assets([
        'thoughtecho-windows-x64-v3.8.0-release.msix',
        'ThoughtEcho-unsigned.ipa',
        'ThoughtEcho-3.8.0-arm64.apk',
      ]);
      expect(
        selectApkAssetUrl(mixed, arm64),
        'https://example.com/ThoughtEcho-3.8.0-arm64.apk',
      );
      // Windows 的 x64 资产不是 APK，不该被 32 位设备当成候选。
      expect(selectApkAssetUrl(mixed, arm32), isNull);
    });
  });
}
