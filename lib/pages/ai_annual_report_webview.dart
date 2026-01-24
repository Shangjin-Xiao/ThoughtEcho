import 'package:flutter/foundation.dart'; // Add kIsWeb import
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/large_file_manager.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

class AIAnnualReportWebView extends StatefulWidget {
  final String htmlContent;
  final int year;

  const AIAnnualReportWebView({
    super.key,
    required this.htmlContent,
    required this.year,
  });

  @override
  State<AIAnnualReportWebView> createState() => _AIAnnualReportWebViewState();
}

class _AIAnnualReportWebViewState extends State<AIAnnualReportWebView>
    with TickerProviderStateMixin {
  AppLocalizations get l10n => AppLocalizations.of(context);
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.yearAIAnnualReport(widget.year.toString())),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
            tooltip: l10n.openInBrowser,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareReport,
            tooltip: l10n.shareReport,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _saveReport,
            tooltip: l10n.saveReport,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.processingReport,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(colorScheme),
                      const SizedBox(height: 20),
                      _buildPreviewCard(colorScheme),
                      const SizedBox(height: 20),
                      _buildActionButtons(colorScheme),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderCard(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.onPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.psychology,
                    color: colorScheme.onPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.yearAIAnnualReport(widget.year.toString()),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.personalizedSummaryByAI,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.onPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.aiGeneratedReview,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onPrimary.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ColorScheme colorScheme) {
    return Card(
      elevation: 8,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  l10n.reportPreview,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _extractTextFromHtml(widget.htmlContent),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.fullReportViewInBrowser,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser),
            label: Text(l10n.openFullReportInBrowser),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareReport,
                icon: const Icon(Icons.share),
                label: Text(l10n.shareBtn),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saveReport,
                icon: const Icon(Icons.save_alt),
                label: Text(l10n.saveBtn),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _extractTextFromHtml(String content) {
    // 检查是否是JSON格式
    if (content.trim().startsWith('{') || content.trim().startsWith('[')) {
      // 尝试解析JSON以提供更友好的显示
      try {
        // 简单清理JSON格式的显示
        String cleanJson = content
            .replaceAll('"author":', l10n.author)
            .replaceAll('"work":', l10n.work)
            .replaceAll('"confidence":', l10n.confidence)
            .replaceAll('"explanation":', l10n.explanation)
            .replaceAll(RegExp(r'[{}",]'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        return l10n.detectedAIJSONFormat(cleanJson);
      } catch (e) {
        return l10n.detectedAbnormalFormat(
          content.length > 300 ? '${content.substring(0, 300)}...' : content,
        );
      }
    }

    // 检查是否包含HTML标签
    if (!content.contains('<html') && !content.contains('<!DOCTYPE')) {
      return l10n.aiGeneratedTextContent(
        content.length > 500 ? '${content.substring(0, 500)}...' : content,
      );
    }

    // 提取HTML中的文本内容
    String text = content
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.length > 800) {
      text = '${text.substring(0, 800)}...';
    }

    return text.isEmpty ? l10n.generatingReportContent : text;
  }

  void _openInBrowser() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 检查内容格式并处理
      String contentToWrite = widget.htmlContent;

      // 如果不是HTML格式，包装成HTML
      if (!widget.htmlContent.trim().toLowerCase().startsWith('<!doctype') &&
          !widget.htmlContent.trim().toLowerCase().startsWith('<html')) {
        contentToWrite = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${l10n.annualReportHtmlTitle(widget.year.toString())}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #eee;
        }
        .content {
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        .json-content {
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 5px;
            padding: 15px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            overflow-x: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>${l10n.annualReportHtmlTitle(widget.year.toString())}</h1>
            <p>${l10n.generationTimeLabel(DateTime.now().toString().substring(0, 19))}</p>
        </div>
        <div class="content ${widget.htmlContent.trim().startsWith('{') ? 'json-content' : ''}">${widget.htmlContent}</div>
    </div>
</body>
</html>
''';
      }

      // 方法1：尝试使用Data URI在浏览器中直接打开
      try {
        // 对于较小的HTML内容，使用Data URI
        if (contentToWrite.length < 8000) {
          // 限制Data URI长度避免问题
          final encodedHtml = Uri.encodeComponent(contentToWrite);
          final dataUri = Uri.parse(
            'data:text/html;charset=utf-8,$encodedHtml',
          );

          if (await canLaunchUrl(dataUri)) {
            await launchUrl(dataUri, mode: LaunchMode.externalApplication);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(l10n.reportOpenedInBrowser),
                    ],
                  ),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  duration: AppConstants.snackBarDurationNormal,
                ),
              );
            }
            return; // 成功打开，直接返回
          }
        }
      } catch (dataUriError) {
        // Data URI失败，继续尝试其他方法
      }

      // 方法2：尝试文件URL方式（优先用于桌面端和支持的移动端）
      try {
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final htmlFile = File(
          '${tempDir.path}/annual_report_${widget.year}_$timestamp.html',
        );

        await LargeFileManager.writeStringToFile(htmlFile, contentToWrite);

        // 尝试直接打开文件URL
        final uri = Uri.file(htmlFile.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(l10n.annualReportOpenedInBrowser),
                  ],
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                duration: AppConstants.snackBarDurationNormal,
              ),
            );
          }
          return; // 成功打开，直接返回
        }
      } catch (urlError) {
        // URL方式失败，继续尝试其他方法
      }

      // 方法3：尝试使用HTTP服务器方式 (通用且更可靠，支持 Windows/iOS/Android)
      if (!kIsWeb) {
        try {
          await _openInBrowserViaTempServer(contentToWrite);
          return;
        } catch (serverError) {
          debugPrint('HTTP服务器方式失败: $serverError');
          // 服务器方式失败，继续尝试其他方法
        }
      }

      // 方法4：最后的备用方案 - 复制内容到剪贴板并提供指导
      await Clipboard.setData(ClipboardData(text: contentToWrite));

      if (mounted) {
        _showCopyInstructions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.cannotGetFilePath}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 移动端专用：通过临时HTTP服务器在浏览器中打开HTML内容
  Future<void> _openInBrowserViaTempServer(String htmlContent) async {
    // 1. 尝试使用本地HTTP服务器方式 (iOS/Android通用且更可靠)
    HttpServer? server;
    try {
      // 绑定到本地回环地址的随机端口
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      // 处理请求
      server.listen((HttpRequest request) {
        // 设置正确的ContentType和编码，防止乱码
        request.response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        request.response.headers.add('Access-Control-Allow-Origin', '*');

        // 写入HTML内容
        request.response.write(htmlContent);
        request.response.close();
      });

      // 构建localhost URL
      final uri = Uri.parse(
          'http://127.0.0.1:${server.port}/annual_report_${widget.year}.html');

      // 使用外部浏览器打开
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(l10n.reportOpenedInBrowser),
                ],
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: AppConstants.snackBarDurationNormal,
            ),
          );
        }

        // 延迟关闭服务器，给予用户足够的时间加载页面
        // 注意：页面加载完成后，服务器关闭不会影响查看，但刷新会失效
        Future.delayed(const Duration(minutes: 5), () {
          try {
            server?.close(force: true);
            debugPrint('临时报告服务器已自动关闭');
          } catch (_) {}
        });

        return; // 成功打开，直接返回
      }
    } catch (e) {
      debugPrint('HTTP服务器方式打开失败: $e');
      try {
        server?.close(force: true);
      } catch (_) {}
      // 继续执行后续的Fallback逻辑
    }

    // 2. Fallback: 原有的文件方式 (对于某些Android设备可能有效，或者作为失败后的各种尝试)
    try {
      // 创建临时文件
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final htmlFile = File(
        '${tempDir.path}/annual_report_${widget.year}_$timestamp.html',
      );

      await LargeFileManager.writeStringToFile(htmlFile, htmlContent);

      // 尝试使用不同的LaunchMode来打开文件
      final uri = Uri.file(htmlFile.path);

      // 首先尝试platformDefault模式
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(l10n.reportOpenedInBrowser),
                  ],
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                duration: AppConstants.snackBarDurationNormal,
              ),
            );
          }
          return;
        }
      } catch (e) {
        // platformDefault失败，尝试其他方式
      }

      // 如果直接打开失败，显示用户指导
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.annualReportCannotOpenBrowser)),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: l10n.shareBtn,
              textColor: Colors.white,
              onPressed: () => _shareReportFile(htmlFile.path),
            ),
          ),
        );
      }
    } catch (e) {
      throw Exception('打开浏览器失败: $e');
    }
  }

  /// 分享报告文件
  Future<void> _shareReportFile(String filePath) async {
    try {
      // 使用系统分享功能，让用户选择浏览器打开
      if (Platform.isAndroid) {
        // Android: 尝试使用Intent直接打开HTML文件
        final uri = Uri.parse('file://$filePath');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          // 如果无法直接打开，提示用户手动操作
          _showManualOpenInstructions(filePath);
        }
      } else if (Platform.isIOS) {
        // iOS: 提示用户手动操作
        _showManualOpenInstructions(filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.shareReport}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 显示手动打开指导
  void _showManualOpenInstructions(String filePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.annualReportOpenInBrowser,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.reportFileSavedInstructions),
            const SizedBox(height: 16),
            Text(l10n.step1OpenFileManager),
            Text(l10n.step2NavigateToPath),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                filePath,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            Text(l10n.step3TapHtmlFile),
            Text(l10n.step4SelectBrowser),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.gotIt),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // 复制文件路径到剪贴板
              Clipboard.setData(ClipboardData(text: filePath));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.pathCopied),
                  duration: AppConstants.snackBarDurationImportant,
                ),
              );
            },
            child: Text(l10n.copyPath),
          ),
        ],
      ),
    );
  }

  void _showCopyInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.annualReportHowToView,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.htmlReportCopiedSteps),
            const SizedBox(height: 16),
            Text(l10n.annualReportMobileInstructions,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(l10n.browserInstructionsStep1),
            Text(l10n.browserInstructionsStep2),
            Text(l10n.browserInstructionsStep3),
            Text(l10n.browserInstructionsStep4),
            Text(l10n.browserInstructionsStep5),
            const SizedBox(height: 12),
            Text(l10n.annualReportDesktopInstructions,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(l10n.desktopInstructionsStep1),
            Text(l10n.desktopInstructionsStep2),
            Text(l10n.desktopInstructionsStep3),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.gotIt),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Clipboard.setData(const ClipboardData(text: 'data:text/html,'));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.addressBarPrefixCopied),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: Text(l10n.copyPrefix),
          ),
        ],
      ),
    );
  }

  void _shareReport() async {
    HapticFeedback.mediumImpact();

    try {
      setState(() {
        _isLoading = true;
      });

      // 创建临时HTML文件用于分享
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final htmlFile = File(
        '${tempDir.path}/annual_report_${widget.year}_$timestamp.html',
      );

      // 准备HTML内容
      String contentToShare = widget.htmlContent;
      if (!widget.htmlContent.trim().toLowerCase().startsWith('<!doctype') &&
          !widget.htmlContent.trim().toLowerCase().startsWith('<html')) {
        contentToShare = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${l10n.annualReportHtmlTitle(widget.year.toString())}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #eee;
        }
        .content {
            white-space: pre-wrap;
            word-wrap: break-word;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>${l10n.annualReportHtmlTitle(widget.year.toString())}</h1>
            <p>${l10n.generationTimeLabel(DateTime.now().toString().substring(0, 19))}</p>
        </div>
        <div class="content">${widget.htmlContent}</div>
    </div>
</body>
</html>
''';
      }

      await LargeFileManager.writeStringToFile(htmlFile, contentToShare);

      // 使用系统分享功能
      await SharePlus.instance.share(
        ShareParams(
          text: l10n.yearAIAnnualReport(widget.year.toString()),
          subject: l10n.yearAIAnnualReport(widget.year.toString()),
          files: [XFile(htmlFile.path)],
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(l10n.reportShared),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.shareReport}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _saveReport() async {
    HapticFeedback.mediumImpact();

    try {
      setState(() {
        _isLoading = true;
      });

      try {
        // 尝试获取文档目录
        final appDir = await getApplicationDocumentsDirectory();
        final reportsDir = Directory('${appDir.path}/annual_reports');

        // 确保目录存在
        if (!await reportsDir.exists()) {
          await reportsDir.create(recursive: true);
        }

        // 创建文件名
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'annual_report_${widget.year}_$timestamp.html';
        final reportFile = File('${reportsDir.path}/$fileName');

        // 保存文件
        await LargeFileManager.writeStringToFile(
            reportFile, widget.htmlContent);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.annualReportSavedToLocal)),
                ],
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (pathError) {
        // 如果路径操作失败，回退到剪贴板
        await Clipboard.setData(ClipboardData(text: widget.htmlContent));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.content_copy, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.annualReportCopiedToClipboard)),
                ],
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.saveReport}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
