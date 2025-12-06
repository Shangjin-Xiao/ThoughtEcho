import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/version_check_service.dart';
import '../gen_l10n/app_localizations.dart';

// 条件导入：只在非 Web 平台导入
import '../services/apk_download_service.dart'
    if (dart.library.html) '../services/apk_download_service_stub.dart';

/// 更新按钮类型枚举
enum UpdateButtonType {
  /// 稍后更新（本次忽略）
  later,

  /// 永久忽略
  ignore,

  /// 立即更新/下载
  update,

  /// 查看更新详情/日志
  viewDetails,
}

/// 更新按钮配置
class UpdateButtonConfig {
  final UpdateButtonType type;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const UpdateButtonConfig({
    required this.type,
    required this.label,
    this.icon,
    this.onPressed,
  });
}

/// 统一的更新底部抽屉组件
class UpdateBottomSheet extends StatelessWidget {
  final VersionInfo versionInfo;
  final bool showNoUpdateMessage;
  final List<UpdateButtonConfig> buttons;

  const UpdateBottomSheet({
    super.key,
    required this.versionInfo,
    this.showNoUpdateMessage = false,
    required this.buttons,
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

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖拽指示器
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withAlpha(128),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题区域
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Icon(Icons.system_update, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context).updateFoundNewVersion),
              ],
            ),
          ),

          // 版本信息卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(contentPadding),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.of(context).updateCurrentVersion,
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
                        AppLocalizations.of(context).updateLatestVersion,
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
          ),

          // 更新内容
          if (versionInfo.releaseNotes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                AppLocalizations.of(context).updateReleaseNotes,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  minHeight: 100,
                  maxHeight: maxReleaseNotesHeight,
                ),
                padding: EdgeInsets.all(contentPadding),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outline.withAlpha(50)),
                ),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: versionInfo.releaseNotes,
                    selectable: true,
                    styleSheet: _createUpdateMarkdownStyle(theme),
                    onTapLink: (text, href, title) {
                      if (href != null) {
                        launchUrl(
                          Uri.parse(href),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    shrinkWrap: false,
                  ),
                ),
              ),
            ),
          ],

          // 发布时间
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(
                    context,
                  ).updateReleaseTime(_formatDate(versionInfo.publishedAt)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // 按钮区域
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(children: _buildButtons(context)),
          ),
        ],
      ),
    );
  }

  /// 构建无更新的对话框
  Widget _buildNoUpdateDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final contentPadding = mediaQuery.size.width < 400 ? 12.0 : 16.0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖拽指示器
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withAlpha(128),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题区域
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context).updateAlreadyLatest),
              ],
            ),
          ),

          // 内容区域
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(contentPadding),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline.withAlpha(50)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.verified, size: 48, color: Colors.green),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).updateCurrentVersionLabel(versionInfo.currentVersion),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context).updateUsingLatestVersion,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 按钮区域
          Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 24,
                ),
              ),
              child: Text(AppLocalizations.of(context).confirm),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建按钮列表
  List<Widget> _buildButtons(BuildContext context) {
    final buttonWidgets = <Widget>[];

    for (int i = 0; i < buttons.length; i++) {
      final config = buttons[i];

      Widget button;
      switch (config.type) {
        case UpdateButtonType.ignore:
          button = OutlinedButton(
            onPressed: config.onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(config.label),
          );
          break;
        case UpdateButtonType.later:
          button = TextButton(
            onPressed: config.onPressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(config.label),
          );
          break;
        case UpdateButtonType.update:
          button = FilledButton.icon(
            onPressed: config.onPressed,
            icon: config.icon != null ? Icon(config.icon, size: 18) : null,
            label: Text(config.label),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          );
          break;
        case UpdateButtonType.viewDetails:
          button = OutlinedButton.icon(
            onPressed: config.onPressed,
            icon: config.icon != null ? Icon(config.icon, size: 18) : null,
            label: Text(config.label),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          );
          break;
      }

      buttonWidgets.add(Expanded(child: button));

      // 在按钮之间添加间距（除了最后一个）
      if (i < buttons.length - 1) {
        buttonWidgets.add(const SizedBox(width: 12));
      }
    }

    return buttonWidgets;
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
        backgroundColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.4,
        ),
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
    // 如果没有更新且不需要显示无更新消息，直接返回
    if (!versionInfo.hasUpdate && !showNoUpdateMessage) {
      return;
    }

    // 如果没有更新，显示无更新消息
    if (!versionInfo.hasUpdate && showNoUpdateMessage) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => UpdateBottomSheet(
          versionInfo: versionInfo,
          showNoUpdateMessage: true,
          buttons: const [], // 无更新时不需要按钮
        ),
      );
    }

    // 有更新时，统一使用带忽略选项的对话框
    return showWithIgnoreOption(context, versionInfo);
  }

  /// 显示带有忽略选项的更新对话框
  static Future<void> showWithIgnoreOption(
    BuildContext context,
    VersionInfo versionInfo,
  ) async {
    // 根据平台确定更新按钮的文本和图标
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final l10n = AppLocalizations.of(context);
    final updateButtonLabel = isWindows ? l10n.updateGoToStore : l10n.updateNow;
    final updateButtonIcon = isWindows ? Icons.store : Icons.download;

    // 按钮配置：永久忽略、查看详情、立即更新/前往商店
    final buttons = [
      UpdateButtonConfig(
        type: UpdateButtonType.ignore,
        label: AppLocalizations.of(context).updateIgnoreForever,
        onPressed: () async {
          await VersionCheckService.ignoreVersion(versionInfo.latestVersion);
          if (context.mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).updateVersionIgnored,
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
      UpdateButtonConfig(
        type: UpdateButtonType.viewDetails,
        label: AppLocalizations.of(context).updateViewDetails,
        icon: Icons.open_in_browser,
        onPressed: () async {
          // 不关闭对话框，直接打开GitHub页面
          await _openDownloadUrl(context, versionInfo.downloadUrl);
        },
      ),
      UpdateButtonConfig(
        type: UpdateButtonType.update,
        label: updateButtonLabel,
        icon: updateButtonIcon,
        onPressed: () async {
          Navigator.of(context).pop();
          await _downloadAndInstallApk(context, versionInfo);
        },
      ),
    ];

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          UpdateBottomSheet(versionInfo: versionInfo, buttons: buttons),
    );
  }

  /// 下载并安装APK或跳转到对应平台的商店
  static Future<void> _downloadAndInstallApk(
    BuildContext context,
    VersionInfo versionInfo,
  ) async {
    // 根据平台选择不同的更新方式
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (isWindows) {
      // Windows平台：跳转到Microsoft Store
      await _openMicrosoftStore(context);
    } else if (isAndroid) {
      // Android平台：下载APK
      if (versionInfo.apkDownloadUrl != null) {
        await ApkDownloadService.downloadAndInstallApk(
          context,
          versionInfo.apkDownloadUrl!,
          versionInfo.latestVersion,
        );
      } else {
        // 回退到浏览器下载
        await _openDownloadUrl(context, versionInfo.downloadUrl);
      }
    } else {
      // 其他平台：打开浏览器下载
      await _openDownloadUrl(context, versionInfo.downloadUrl);
    }
  }

  /// 打开Microsoft Store
  static Future<void> _openMicrosoftStore(BuildContext context) async {
    // Microsoft Store URL格式：ms-windows-store://pdp/?productId=<AppId>
    // 这里需要替换为实际的应用ProductId
    const String microsoftStoreUrl =
        'ms-windows-store://pdp/?productId=9NC7GDG6KFMC';

    try {
      final uri = Uri.parse(microsoftStoreUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // 如果Store协议不可用，回退到网页版
        const String webStoreUrl =
            'https://www.microsoft.com/store/apps/9NC7GDG6KFMC';
        final webUri = Uri.parse(webStoreUrl);
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Cannot open Microsoft Store');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).updateOpenStoreFailed(e.toString()),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 打开下载链接（实例方法）
  static Future<void> _openDownloadUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Cannot open download link');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).updateOpenLinkFailed(e.toString()),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
