import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/generated_card.dart';

/// SVG卡片渲染组件
class SVGCardWidget extends StatelessWidget {
  final String svgContent;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool showLoadingIndicator;
  final Widget? errorWidget;

  const SVGCardWidget({
    super.key,
    required this.svgContent,
    this.onTap,
    this.width = 400,
    this.height = 600,
    this.fit = BoxFit.contain,
    this.showLoadingIndicator = true,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    // 在debug模式下打印SVG内容用于调试
    if (kDebugMode) {
      print('SVG渲染 - 内容长度: ${svgContent.length}');
      print(
        'SVG渲染 - 前100字符: ${svgContent.length > 100 ? svgContent.substring(0, 100) : svgContent}',
      );

      // 检查SVG内容的关键元素
      final hasViewBox = svgContent.contains('viewBox');
      final hasXmlns = svgContent.contains('xmlns');
      final hasForeignObject = svgContent.contains('foreignObject');
      final hasEmoji = RegExp(
        r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]',
        unicode: true,
      ).hasMatch(svgContent);

      print(
        'SVG检查 - viewBox: $hasViewBox, xmlns: $hasXmlns, foreignObject: $hasForeignObject, emoji: $hasEmoji',
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildSVGWidget(),
        ),
      ),
    );
  }

  Widget _buildSVGWidget() {
    try {
      // 验证SVG内容
      if (svgContent.trim().isEmpty) {
        return _buildErrorWidget('SVG内容为空');
      }

      if (!svgContent.contains('<svg') || !svgContent.contains('</svg>')) {
        return _buildErrorWidget('无效的SVG格式');
      }

      return SvgPicture.string(
        svgContent,
        fit: fit,
        placeholderBuilder:
            showLoadingIndicator
                ? (context) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                )
                : null,
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            print('SVG渲染错误: $error');
            print('SVG内容: $svgContent');
            print('错误堆栈: $stackTrace');
          }
          // 使用回退SVG模板而不是错误提示
          return _buildFallbackSVG();
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('SVG组件构建错误: $e');
      }
      return _buildErrorWidget('SVG组件错误: ${e.toString()}');
    }
  }

  Widget _buildErrorWidget(String message) {
    return errorWidget ??
        Container(
          color: Colors.grey[200],
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  const Text(
                    'SVG渲染失败',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
  }

  /// 构建回退SVG模板
  Widget _buildFallbackSVG() {
    // 尝试从原始SVG内容中提取文本内容
    String extractedContent = _extractContentFromSVG(svgContent);

    // 生成回退SVG
    final fallbackSVG = _generateFallbackSVGContent(extractedContent);

    try {
      return SvgPicture.string(fallbackSVG, fit: fit);
    } catch (e) {
      // 如果回退SVG也失败，则显示错误提示
      return _buildErrorWidget('SVG渲染完全失败');
    }
  }

  /// 从SVG内容中提取文本
  String _extractContentFromSVG(String svg) {
    try {
      // 尝试提取text标签中的内容
      final textMatches = RegExp(r'<text[^>]*>([^<]+)</text>').allMatches(svg);
      final texts =
          textMatches
              .map((match) => match.group(1)?.trim() ?? '')
              .where((text) => text.isNotEmpty)
              .toList();

      if (texts.isNotEmpty) {
        return texts.first;
      }

      // 尝试提取foreignObject中的内容
      final foreignMatches = RegExp(
        r'<foreignObject[^>]*>.*?<div[^>]*>([^<]+)</div>',
        dotAll: true,
      ).allMatches(svg);
      if (foreignMatches.isNotEmpty) {
        final content = foreignMatches.first.group(1)?.trim() ?? '';
        if (content.isNotEmpty) {
          return content;
        }
      }

      return '内容解析失败';
    } catch (e) {
      return '无法提取内容';
    }
  }

  /// 生成回退SVG内容
  String _generateFallbackSVGContent(String content) {
    // 限制内容长度
    final displayContent =
        content.length > 50 ? '${content.substring(0, 50)}...' : content;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="fallbackBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#ff7b7b;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#667eea;stop-opacity:1" />
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="400" height="600" fill="url(#fallbackBg)" rx="20"/>

  <!-- 警告图标 -->
  <circle cx="200" cy="120" r="30" fill="rgba(255,255,255,0.2)" stroke="white" stroke-width="2"/>
  <text x="200" y="130" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="24">⚠</text>

  <!-- 标题 -->
  <text x="200" y="180" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="16" font-weight="bold">
    SVG生成失败
  </text>

  <!-- 内容区域 -->
  <rect x="30" y="220" width="340" height="280" fill="rgba(255,255,255,0.9)" rx="15"/>

  <!-- 内容文字 -->
  <text x="200" y="260" text-anchor="middle" fill="#333" font-family="Arial, sans-serif" font-size="14" font-weight="bold">
    原始内容：
  </text>

  <!-- 分割线 -->
  <line x1="50" y1="280" x2="350" y2="280" stroke="#ddd" stroke-width="1"/>

  <!-- 提取的内容 -->
  <foreignObject x="50" y="300" width="300" height="180">
    <div xmlns="http://www.w3.org/1999/xhtml" style="font-family: Arial, sans-serif; font-size: 14px; line-height: 1.5; color: #555; padding: 10px; text-align: center; word-wrap: break-word;">
      ${displayContent.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}
    </div>
  </foreignObject>

  <!-- 底部提示 -->
  <text x="200" y="540" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    请尝试重新生成或检查AI配置
  </text>

  <!-- ThoughtEcho标识 -->
  <text x="200" y="570" text-anchor="middle" fill="rgba(255,255,255,0.8)" font-family="Arial, sans-serif" font-size="10">
    ThoughtEcho - 备用模板
  </text>
</svg>
''';
  }
}

/// 生成的卡片展示组件
class GeneratedCardWidget extends StatelessWidget {
  final GeneratedCard card;
  final VoidCallback? onTap;
  final VoidCallback? onShare;
  final VoidCallback? onSave;
  final bool showActions;
  final double? width;
  final double? height;

  const GeneratedCardWidget({
    super.key,
    required this.card,
    this.onTap,
    this.onShare,
    this.onSave,
    this.showActions = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SVGCardWidget(
          svgContent: card.svgContent,
          onTap: onTap,
          width: width,
          height: height,
        ),
        if (showActions) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (onShare != null)
                _ActionButton(
                  icon: Icons.share,
                  label: '分享',
                  onPressed: onShare!,
                ),
              if (onSave != null)
                _ActionButton(
                  icon: Icons.save_alt,
                  label: '保存',
                  onPressed: onSave!,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 操作按钮组件
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// 卡片预览对话框
class CardPreviewDialog extends StatelessWidget {
  final GeneratedCard card;
  final VoidCallback? onShare;
  final VoidCallback? onSave;

  const CardPreviewDialog({
    super.key,
    required this.card,
    this.onShare,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 关闭按钮
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
            // 卡片内容
            Flexible(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GeneratedCardWidget(
                    card: card,
                    onShare: onShare,
                    onSave: onSave,
                    width: 350,
                    height: 500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片生成加载对话框
class CardGenerationLoadingDialog extends StatelessWidget {
  final String message;
  final VoidCallback? onCancel;

  const CardGenerationLoadingDialog({
    super.key,
    this.message = '正在生成卡片...',
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
      actions: [
        if (onCancel != null)
          TextButton(onPressed: onCancel, child: const Text('取消')),
      ],
    );
  }
}
