import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/version_check_service.dart';
import '../utils/app_logger.dart';

/// 版本更新提示对话框
class UpdateDialog extends StatelessWidget {
  final VersionInfo versionInfo;
  final bool showNoUpdateMessage;

  const UpdateDialog({
    super.key,
    required this.versionInfo,
    this.showNoUpdateMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (versionInfo.hasUpdate) {
      return _buildUpdateAvailableDialog(context);
    } else if (showNoUpdateMessage) {
      return _buildNoUpdateDialog(context);
    } else {
      return const SizedBox.shrink();
    }
  }

  /// 构建有更新可用的对话框
  Widget _buildUpdateAvailableDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('发现新版本'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本信息卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withAlpha(50),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '当前版本',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        versionInfo.currentVersion,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '最新版本',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          versionInfo.latestVersion,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 更新内容
            if (versionInfo.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                '更新内容',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withAlpha(50),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    versionInfo.releaseNotes,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],

            // 发布时间
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '发布时间: ${_formatDate(versionInfo.publishedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后更新'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            _launchDownloadUrl(versionInfo.downloadUrl);
          },
          icon: const Icon(Icons.download),
          label: const Text('立即下载'),
        ),
      ],
    );
  }

  /// 构建无更新的对话框
  Widget _buildNoUpdateDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 28,
          ),
          SizedBox(width: 12),
          Text('已是最新版本'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withAlpha(50),
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.verified,
                  size: 48,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                Text(
                  '当前版本 ${versionInfo.currentVersion}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '您使用的已是最新版本',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ],
    );
  }

  /// 启动下载链接
  Future<void> _launchDownloadUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        logError('无法打开下载链接: $url');
      }
    } catch (e) {
      logError('启动下载链接失败: $e', error: e);
    }
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 显示更新对话框的静态方法
  static Future<void> show(
    BuildContext context,
    VersionInfo versionInfo, {
    bool showNoUpdateMessage = false,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => UpdateDialog(
        versionInfo: versionInfo,
        showNoUpdateMessage: showNoUpdateMessage,
      ),
    );
  }
}
