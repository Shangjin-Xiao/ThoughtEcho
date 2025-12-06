import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/generated_card.dart';
import '../utils/app_logger.dart';

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
    // 只在debug模式且SVG内容有问题时才打印详细信息
    if (kDebugMode && svgContent.length < 100) {
      logDebug(
        'SVG渲染 - 内容可能过短: ${svgContent.length}字符',
        source: 'SVGCardWidget',
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

      // 使用与导出完全一致的渲染配置
      return SvgPicture.string(
        svgContent,
        fit: fit,
        width: width,
        height: height,
        allowDrawingOutsideViewBox: false, // 与offscreen renderer保持一致
        placeholderBuilder: showLoadingIndicator
            ? (context) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text(
                          '正在加载SVG...',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
            : null,
        errorBuilder: (context, error, stackTrace) {
          AppLogger.e(
            'SVG渲染错误: $error',
            error: error,
            stackTrace: stackTrace,
            source: 'SvgCardWidget',
          );
          if (kDebugMode) {
            AppLogger.d(
              'SVG内容预览: ${svgContent.substring(0, svgContent.length > 200 ? 200 : svgContent.length)}...',
              source: 'SvgCardWidget',
            );
          }
          // 使用回退SVG模板而不是错误提示
          return _buildFallbackSVG();
        },
      );
    } catch (e) {
      AppLogger.e('SVG组件构建错误: $e', error: e, source: 'SvgCardWidget');
      return _buildErrorWidget('SVG组件错误: ${e.toString()}');
    }
  }

  Widget _buildErrorWidget(String message) {
    return errorWidget ??
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border.all(color: Colors.grey[300]!, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_not_supported_outlined,
                    size: 48,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'SVG渲染失败',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '正在尝试使用备用模板...',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        message.length > 100
                            ? '${message.substring(0, 100)}...'
                            : message,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
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
    try {
      // 尝试从原始SVG内容中提取文本内容
      String extractedContent = _extractContentFromSVG(svgContent);

      // 生成回退SVG
      final fallbackSVG = _generateFallbackSVGContent(extractedContent);

      AppLogger.i(
        '使用回退SVG模板，内容长度: ${fallbackSVG.length}',
        source: 'SvgCardWidget',
      );

      return SvgPicture.string(
        fallbackSVG,
        fit: fit,
        placeholderBuilder: showLoadingIndicator
            ? (context) => Container(
                  color: Colors.grey[100],
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text(
                          '正在加载备用模板...',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
            : null,
        errorBuilder: (context, error, stackTrace) {
          AppLogger.e(
            '回退SVG也渲染失败: $error',
            error: error,
            source: 'SvgCardWidget',
          );
          return _buildFinalErrorWidget();
        },
      );
    } catch (e) {
      AppLogger.e('构建回退SVG失败: $e', error: e, source: 'SvgCardWidget');
      return _buildFinalErrorWidget();
    }
  }

  /// 构建最终错误提示（当所有方案都失败时）
  Widget _buildFinalErrorWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red[200]!, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
              const SizedBox(height: 12),
              Text(
                '卡片渲染失败',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请尝试重新生成卡片',
                style: TextStyle(color: Colors.red[600], fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 从SVG内容中提取文本
  String _extractContentFromSVG(String svg) {
    try {
      // 尝试提取text标签中的内容
      final textMatches = RegExp(r'<text[^>]*>([^<]+)</text>').allMatches(svg);
      final texts = textMatches
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

  <!-- 笔记内容（无标签） -->
  <foreignObject x="50" y="240" width="300" height="240">
    <div xmlns="http://www.w3.org/1999/xhtml" style="font-family: Arial, sans-serif; font-size: 14px; line-height: 1.5; color: #333; padding: 20px; text-align: center; word-wrap: break-word;">
      ${displayContent.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}
    </div>
  </foreignObject>

  <!-- 底部提示 -->
  <text x="200" y="540" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    请尝试重新生成或检查AI配置
  </text>

  <!-- 心迹标识 -->
  <text x="200" y="570" text-anchor="middle" fill="rgba(255,255,255,0.8)" font-family="Arial, sans-serif" font-size="10">
    心迹 - 备用模板
  </text>
</svg>
''';
  }
}

/// 生成的卡片展示组件
class GeneratedCardWidget extends StatelessWidget {
  final GeneratedCard card;
  final VoidCallback? onTap;
  final Future<void> Function(GeneratedCard card)? onShare;
  final Future<void> Function(GeneratedCard card)? onSave;
  final Future<void> Function()? onRegenerate;
  final bool showActions;
  final bool actionsEnabled;
  final double? width;
  final double? height;

  const GeneratedCardWidget({
    super.key,
    required this.card,
    this.onTap,
    this.onShare,
    this.onSave,
    this.onRegenerate,
    this.showActions = true,
    this.actionsEnabled = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // 如果不显示操作按钮，直接返回SVGCardWidget以避免ParentData类型冲突
    if (!showActions) {
      return SVGCardWidget(
        svgContent: card.svgContent,
        onTap: onTap,
        width: width,
        height: height,
      );
    }

    // 显示操作按钮时，使用Column包装
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SVGCardWidget(
          svgContent: card.svgContent,
          onTap: onTap,
          width: width,
          height: height,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (onRegenerate != null)
              _ActionButton(
                icon: Icons.refresh,
                label: l10n.regenerateCard,
                onPressed: () => onRegenerate?.call(),
                enabled: actionsEnabled,
              ),
            if (onShare != null)
              _ActionButton(
                icon: Icons.share,
                label: l10n.shareBtn,
                onPressed: () => onShare?.call(card),
                enabled: actionsEnabled,
              ),
            if (onSave != null)
              _ActionButton(
                icon: Icons.save_alt,
                label: l10n.saveBtn,
                onPressed: () => onSave?.call(card),
                enabled: actionsEnabled,
              ),
          ],
        ),
      ],
    );
  }
}

/// 操作按钮组件
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
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
class CardPreviewDialog extends StatefulWidget {
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
  State<CardPreviewDialog> createState() => _CardPreviewDialogState();
}

class _CardPreviewDialogState extends State<CardPreviewDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
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
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 500,
                  maxHeight: 700,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 关闭按钮
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                          tooltip: '关闭',
                        ),
                      ),
                    ),
                    // 卡片内容
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 标题
                              Text(
                                '精选卡片',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              // 卡片
                              GeneratedCardWidget(
                                card: widget.card,
                                onShare: widget.onShare,
                                onSave: widget.onSave,
                                width: 300,
                                height: 400,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
