import 'package:flutter/material.dart';
import '../services/version_check_service.dart';
import '../widgets/update_dialog.dart';

/// 更新对话框辅助类
class UpdateDialogHelper {
  /// 显示更新提示对话框
  static Future<void> showUpdateDialog(
    BuildContext context,
    VersionInfo versionInfo,
  ) async {
    // 检查是否已永久忽略此版本
    final shouldIgnore = await VersionCheckService.shouldIgnoreVersion(
      versionInfo.latestVersion,
    );
    if (shouldIgnore) {
      return;
    }

    if (!context.mounted) return;

    await UpdateBottomSheet.showWithIgnoreOption(context, versionInfo);
  }
}
