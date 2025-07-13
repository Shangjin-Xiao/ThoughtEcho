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
      print('SVG渲染 - 前100字符: ${svgContent.length > 100 ? svgContent.substring(0, 100) : svgContent}');
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
        placeholderBuilder: showLoadingIndicator
            ? (context) => Container(
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              )
            : null,
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            print('SVG渲染错误: $error');
            print('SVG内容: $svgContent');
            print('错误堆栈: $stackTrace');
          }
          return _buildErrorWidget('SVG渲染失败: ${error.toString()}');
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
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.grey,
                  ),
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
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 28,
                ),
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
          TextButton(
            onPressed: onCancel,
            child: const Text('取消'),
          ),
      ],
    );
  }
}
