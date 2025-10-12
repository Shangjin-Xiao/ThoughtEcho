import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;

    // 根据屏幕尺寸调整约束
    final maxReleaseNotesHeight = screenHeight > 700 ? 350.0 : 250.0;
    final contentPadding = mediaQuery.size.width < 400 ? 12.0 : 16.0;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              padding: EdgeInsets.all(contentPadding),
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
              SizedBox(height: contentPadding),
              Text(
                '更新内容',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  minHeight: 100,
                  maxHeight: maxReleaseNotesHeight,
                ),
                padding: EdgeInsets.all(contentPadding),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withAlpha(50),
                  ),
                ),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: versionInfo.releaseNotes,
                    selectable: true,
                    styleSheet: _createUpdateMarkdownStyle(theme),
                    onTapLink: (text, href, title) {
                      if (href != null) {
                        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                      }
                    },
                    shrinkWrap: false,
                  ),
                ),
              ),
            ],

            // 发布时间
            SizedBox(height: contentPadding),
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
    final mediaQuery = MediaQuery.of(context);
    final contentPadding = mediaQuery.size.width < 400 ? 12.0 : 16.0;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
            padding: EdgeInsets.all(contentPadding),
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
                SizedBox(height: contentPadding),
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

  /// 创建适合更新弹窗的Markdown样式表
  MarkdownStyleSheet _createUpdateMarkdownStyle(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final baseColor = colorScheme.onSurface;

    return MarkdownStyleSheet(
      // 段落样式
      p: theme.textTheme.bodyMedium?.copyWith(
        color: baseColor,
        height: 1.5,
        fontSize: 14,
      ),

      // 标题样式
      h1: theme.textTheme.headlineSmall?.copyWith(
        color: baseColor,
        fontWeight: FontWeight.bold,
        fontSize: 18,
        height: 1.2,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        color: baseColor,
        fontWeight: FontWeight.bold,
        fontSize: 16,
        height: 1.3,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        color: baseColor,
        fontWeight: FontWeight.w600,
        fontSize: 15,
        height: 1.3,
      ),

      // 文本装饰
      em: TextStyle(color: baseColor, fontStyle: FontStyle.italic),
      strong: TextStyle(color: baseColor, fontWeight: FontWeight.bold),
      del: TextStyle(
        color: baseColor.withValues(alpha: 0.7),
        decoration: TextDecoration.lineThrough,
      ),

      // 链接样式
      a: TextStyle(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: colorScheme.primary.withValues(alpha: 0.6),
      ),

      // 引用块样式
      blockquote: theme.textTheme.bodySmall?.copyWith(
        color: baseColor.withValues(alpha: 0.8),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.4),
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),

      // 行内代码样式
      code: TextStyle(
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        fontFamily: 'JetBrains Mono, Consolas, Monaco, Courier New, monospace',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),

      // 代码块样式
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      codeblockPadding: const EdgeInsets.all(12),

      // 列表样式
      listBullet: TextStyle(
        color: colorScheme.primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      listIndent: 20,

      // 其他样式
      textScaler: const TextScaler.linear(1.0),
    );
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
