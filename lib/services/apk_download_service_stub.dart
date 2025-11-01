import 'package:flutter/material.dart';

/// APK下载服务的 Web 平台桩实现
/// 在 Web 平台上，APK 下载功能不可用
class ApkDownloadService {
  /// Web 平台不支持 APK 下载
  static Future<void> downloadAndInstallApk(
    BuildContext context,
    String apkUrl,
    String version,
  ) async {
    // Web 平台不执行任何操作
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Web 平台不支持 APK 下载'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 清理资源（Web 平台空实现）
  static void dispose() {}
}
