import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

/// 增强的全屏编辑器工具栏组件
/// 支持图片、视频等扩展功能
class QuillEnhancedToolbar extends StatelessWidget {
  final quill.QuillController controller;

  const QuillEnhancedToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.1),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: quill.QuillSimpleToolbar(
          controller: controller,
          config: quill.QuillSimpleToolbarConfig(
            // 启用扩展功能按钮 - 包含图片、视频等
            embedButtons: FlutterQuillEmbeds.toolbarButtons(),
            // 基础格式化功能
            showBoldButton: true,
            showItalicButton: true,
            showUnderLineButton: true,
            showStrikeThrough: true,
            showColorButton: true,
            showBackgroundColorButton: true,
            // 段落格式
            showHeaderStyle: true,
            showListNumbers: true,
            showListBullets: true,
            showQuote: true,
            showCodeBlock: true,
            showInlineCode: true,
            // 对齐和其他
            showAlignmentButtons: true,
            showIndent: true,
            showLink: true,
            showUndo: true,
            showRedo: true,
            showClearFormat: true,
            // 布局配置
            multiRowsDisplay: false,
            decoration: const BoxDecoration(color: Colors.transparent),
            buttonOptions: quill.QuillSimpleToolbarButtonOptions(
              base: quill.QuillToolbarBaseButtonOptions(
                iconSize: 18,
                iconButtonFactor: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 兼容性别名，保持向后兼容
class FullScreenToolbar extends QuillEnhancedToolbar {
  const FullScreenToolbar({super.key, required super.controller});
}
