import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

/// 增强的全屏编辑器工具栏组件
/// 支持基础富文本格式化功能
class QuillEnhancedToolbar extends StatelessWidget {
  final quill.QuillController controller;

  const QuillEnhancedToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 56, // 明确设置高度
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: quill.QuillSimpleToolbar(
          controller: controller,
          config: quill.QuillSimpleToolbarConfig(
            // 启用媒体扩展按钮
            embedButtons: FlutterQuillEmbeds.toolbarButtons(),

            // 基础格式化功能
            showBoldButton: true,
            showItalicButton: true,
            showUnderLineButton: true,
            showStrikeThrough: true,

            // 段落格式
            showHeaderStyle: true,
            showListNumbers: true,
            showListBullets: true,
            showQuote: true,
            showCodeBlock: true,

            // 链接和其他功能
            showLink: true,
            showUndo: true,
            showRedo: true,
            showClearFormat: true,

            // 布局配置
            multiRowsDisplay: false,
            decoration: BoxDecoration(color: Colors.transparent),
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
