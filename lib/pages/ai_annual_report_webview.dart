import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
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
        title: Text('${widget.year} AI年度报告'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
            tooltip: '在浏览器中打开',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareReport,
            tooltip: '分享报告',
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _saveReport,
            tooltip: '保存报告',
          ),
        ],
      ),
      body:
          _isLoading
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      '正在处理报告...',
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
                        '${widget.year} AI年度报告',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '基于AI分析的个性化总结',
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
                      'AI已为您生成专属的年度回顾，包含数据分析、成长洞察和未来建议',
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
                  '报告内容预览',
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
                      '完整报告包含精美的图表和交互效果，建议在浏览器中查看',
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
            label: const Text('在浏览器中查看完整报告'),
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
                label: const Text('分享'),
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
                label: const Text('保存'),
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
        String cleanJson =
            content
                .replaceAll('"author":', '作者: ')
                .replaceAll('"work":', '作品: ')
                .replaceAll('"confidence":', '可信度: ')
                .replaceAll('"explanation":', '说明: ')
                .replaceAll(RegExp(r'[{}",]'), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();

        return '''
⚠️ 检测到AI返回了JSON数据格式

这表明AI模型可能误解了请求，返回了数据分析结果而非HTML报告。

返回的内容：
$cleanJson

这个问题可能的原因：
• AI混淆了年度报告生成和内容分析功能
• 提示词需要进一步优化
• 模型版本或配置问题

建议解决方案：
1. 重新生成报告（AI可能会修正错误）
2. 检查AI设置中的模型配置
3. 尝试使用原生Flutter报告功能
4. 更新AI提示词配置

如需技术支持，请保存此错误信息并联系开发者。
''';
      } catch (e) {
        return '''
⚠️ 检测到异常数据格式

AI返回了无法正常解析的JSON数据，这可能是由于：
• 网络传输问题
• AI服务异常
• 数据格式错误

原始内容：
${content.length > 300 ? '${content.substring(0, 300)}...' : content}

建议重新生成报告或使用原生报告功能。
''';
      }
    }

    // 检查是否包含HTML标签
    if (!content.contains('<html') && !content.contains('<!DOCTYPE')) {
      return '''
📄 AI生成的文本内容

${content.length > 500 ? '${content.substring(0, 500)}...' : content}

💡 提示：AI返回了纯文本格式的总结而非HTML报告。
这可能是因为模型理解了内容但没有按照HTML格式输出。

完整内容可以在浏览器中查看，系统会自动包装为HTML格式。
''';
    }

    // 提取HTML中的文本内容
    String text =
        content
            .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
            .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
            .replaceAll(RegExp(r'<[^>]*>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    if (text.length > 800) {
      text = '${text.substring(0, 800)}...';
    }

    return text.isEmpty ? '正在生成报告内容...' : text;
  }

  void _openInBrowser() async {
    setState(() {
      _isLoading = true;
    });

    try {
      try {
        // 尝试创建临时HTML文件
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final htmlFile = File(
          '${tempDir.path}/annual_report_${widget.year}_$timestamp.html',
        );

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
    <title>心迹 ${widget.year} 年度报告</title>
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
            <h1>心迹 ${widget.year} 年度报告</h1>
            <p>生成时间: ${DateTime.now().toString().substring(0, 19)}</p>
        </div>
        <div class="content ${widget.htmlContent.trim().startsWith('{') ? 'json-content' : ''}">${widget.htmlContent}</div>
    </div>
</body>
</html>
''';
        }

        await htmlFile.writeAsString(contentToWrite);

        // 在浏览器中打开
        final uri = Uri.file(htmlFile.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('报告已在浏览器中打开'),
                  ],
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }
        } else {
          throw '无法启动浏览器';
        }
      } catch (pathError) {
        // 如果文件操作失败，复制内容到剪贴板作为备用方案
        await Clipboard.setData(ClipboardData(text: widget.htmlContent));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.content_copy, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('无法创建临时文件，内容已复制到剪贴板')),
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
            content: Text('操作失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
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

  void _shareReport() async {
    HapticFeedback.mediumImpact();

    try {
      setState(() {
        _isLoading = true;
      });

      // 复制HTML内容到剪贴板
      await Clipboard.setData(ClipboardData(text: widget.htmlContent));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('报告内容已复制到剪贴板'),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分享失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
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
        await reportFile.writeAsString(widget.htmlContent);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('报告已保存到本地文件')),
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
              content: const Row(
                children: [
                  Icon(Icons.content_copy, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('无法保存文件，内容已复制到剪贴板')),
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
            content: Text('保存失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
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
