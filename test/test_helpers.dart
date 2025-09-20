import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dart:io';

/// Mock Path Provider Platform
class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/tmp/test_app_docs';
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return '/tmp/test_app_support';
  }

  @override
  Future<String?> getDownloadsPath() async {
    return '/tmp/test_downloads';
  }

  @override
  Future<String?> getTemporaryPath() async {
    return '/tmp/test_temp';
  }
}

/// 测试辅助类，提供通用的测试设置
class TestHelpers {
  static MockPathProviderPlatform? _mockPathProvider;

  /// 设置测试环境
  static Future<void> setupTestEnvironment() async {
    // 设置SharedPreferences mock
    SharedPreferences.setMockInitialValues({});

    // Mock path_provider
    TestWidgetsFlutterBinding.ensureInitialized();

    // 设置mock path provider
    _mockPathProvider = MockPathProviderPlatform();
    PathProviderPlatform.instance = _mockPathProvider!;
  }

  /// 清理测试环境
  static Future<void> teardownTestEnvironment() async {
    _mockPathProvider = null;
  }

  /// 创建临时目录用于测试
  static Future<Directory> createTempDir(String prefix) async {
    return Directory.systemTemp.createTemp(prefix);
  }

  /// 删除临时目录
  static Future<void> deleteTempDir(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 获取mock的应用文档目录
  static Directory getMockAppDocumentsDir() {
    return Directory('/tmp/test_app_docs');
  }
}
