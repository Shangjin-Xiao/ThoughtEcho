// 简单的版本检查功能测试脚本
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/services/version_check_service.dart';

void main() async {
  AppLogger.i('开始测试版本检查功能...');

  // 测试版本比较逻辑
  AppLogger.i('\n=== 测试版本比较逻辑 ===');
  final testCases = [
    {'current': '1.0.0', 'latest': '1.0.1', 'expected': true},
    {'current': '1.0.0', 'latest': '1.0.0', 'expected': false},
    {'current': '1.0.1', 'latest': '1.0.0', 'expected': false},
    {'current': '1.0.0', 'latest': '2.0.0', 'expected': true},
    {'current': 'v1.0.0', 'latest': 'v1.0.1', 'expected': true},
  ];

  for (final testCase in testCases) {
    final mockJson = {
      'tag_name': testCase['latest'],
      'html_url': 'https://github.com/test/test/releases/latest',
      'body': 'Test release notes',
      'published_at': '2024-01-01T00:00:00Z',
    };

    final versionInfo = VersionInfo.fromJson(
      mockJson,
      testCase['current'] as String,
    );
    final result = versionInfo.hasUpdate;
    final expected = testCase['expected'] as bool;

    AppLogger.i(
      '当前: ${testCase['current']}, 最新: ${testCase['latest']}, 有更新: $result, 期望: $expected, ${result == expected ? '✓' : '✗'}',
    );
  }

  // 测试GitHub API响应解析
  AppLogger.i('\n=== 测试GitHub API响应解析 ===');
  const mockResponse = {
    'tag_name': 'v1.2.0',
    'html_url':
        'https://github.com/Shangjin-Xiao/ThoughtEcho/releases/tag/v1.2.0',
    'body': '## 新功能\n- 添加了版本检查功能\n- 优化了UI界面',
    'published_at': '2024-07-29T10:00:00Z',
  };

  final versionInfo = VersionInfo.fromJson(mockResponse, '1.0.0');
  AppLogger.i('当前版本: ${versionInfo.currentVersion}');
  AppLogger.i('最新版本: ${versionInfo.latestVersion}');
  AppLogger.i('有更新: ${versionInfo.hasUpdate}');
  AppLogger.i('下载链接: ${versionInfo.downloadUrl}');
  AppLogger.i('发布说明: ${versionInfo.releaseNotes}');
  AppLogger.i('发布时间: ${versionInfo.publishedAt}');

  // 测试实际的GitHub API调用（需要网络连接）
  AppLogger.i('\n=== 测试实际GitHub API调用 ===');
  try {
    AppLogger.i('正在检查GitHub上的最新版本...');
    final realVersionInfo = await VersionCheckService.checkForUpdates();
    AppLogger.i('检查成功！');
    AppLogger.i('当前版本: ${realVersionInfo.currentVersion}');
    AppLogger.i('最新版本: ${realVersionInfo.latestVersion}');
    AppLogger.i('有更新: ${realVersionInfo.hasUpdate}');
    if (realVersionInfo.hasUpdate) {
      AppLogger.i('下载链接: ${realVersionInfo.downloadUrl}');
    }
  } catch (e) {
    AppLogger.e('检查失败: $e');
  }

  AppLogger.i('\n版本检查功能测试完成！');
}
