import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'unified_media_import_dialog.dart';

/// 统一的增强工具栏组件
///
/// 整合了两个原有工具栏的优点：
/// - 使用官方组件确保稳定性
/// - 保留自定义功能的完整性
/// - 优化大文件处理，防止OOM
/// - 统一媒体导入逻辑
class UnifiedQuillToolbar extends StatefulWidget {
  final quill.QuillController controller;
  final void Function(String filePath)? onMediaImported;

  const UnifiedQuillToolbar({super.key, required this.controller, this.onMediaImported});

  @override
  State<UnifiedQuillToolbar> createState() => _UnifiedQuillToolbarState();
}

class _UnifiedQuillToolbarState extends State<UnifiedQuillToolbar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // 第一组：历史操作
            quill.QuillToolbarHistoryButton(
              controller: widget.controller,
              isUndo: true,
              options: const quill.QuillToolbarHistoryButtonOptions(),
            ),
            quill.QuillToolbarHistoryButton(
              controller: widget.controller,
              isUndo: false,
              options: const quill.QuillToolbarHistoryButtonOptions(),
            ),
            _buildDivider(),

            // 第二组：基础格式
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.bold,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.italic,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.underline,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.strikeThrough,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            _buildDivider(),

            // 第三组：标题
            quill.QuillToolbarSelectHeaderStyleDropdownButton(
              controller: widget.controller,
              options: const quill
                  .QuillToolbarSelectHeaderStyleDropdownButtonOptions(),
            ),
            _buildDivider(),

            // 第四组：字体和大小
            quill.QuillToolbarFontSizeButton(
              controller: widget.controller,
              options: const quill.QuillToolbarFontSizeButtonOptions(),
            ),
            quill.QuillToolbarFontFamilyButton(
              controller: widget.controller,
              options: const quill.QuillToolbarFontFamilyButtonOptions(),
            ),
            _buildDivider(),

            // 第五组：颜色
            quill.QuillToolbarColorButton(
              controller: widget.controller,
              isBackground: false,
              options: const quill.QuillToolbarColorButtonOptions(),
            ),
            quill.QuillToolbarColorButton(
              controller: widget.controller,
              isBackground: true,
              options: const quill.QuillToolbarColorButtonOptions(),
            ),
            _buildDivider(),

            // 第六组：对齐
            quill.QuillToolbarSelectAlignmentButton(
              controller: widget.controller,
            ),
            _buildDivider(),

            // 第七组：列表
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.ol,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.ul,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarIndentButton(
              controller: widget.controller,
              isIncrease: false,
              options: const quill.QuillToolbarIndentButtonOptions(),
            ),
            quill.QuillToolbarIndentButton(
              controller: widget.controller,
              isIncrease: true,
              options: const quill.QuillToolbarIndentButtonOptions(),
            ),
            _buildDivider(),

            // 第八组：引用和代码
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.blockQuote,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.codeBlock,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            _buildDivider(),

            // 第九组：链接
            quill.QuillToolbarLinkStyleButton(
              controller: widget.controller,
              options: const quill.QuillToolbarLinkStyleButtonOptions(),
            ),
            _buildDivider(),

            // 第十组：媒体插入 - 使用统一的媒体导入
            _buildMediaButton(
              icon: Icons.image,
              tooltip: '插入图片',
              onPressed: () => _showUnifiedMediaDialog('image'),
            ),
            _buildMediaButton(
              icon: Icons.videocam,
              tooltip: '插入视频',
              onPressed: () => _showUnifiedMediaDialog('video'),
            ),
            _buildMediaButton(
              icon: Icons.audiotrack,
              tooltip: '插入音频',
              onPressed: () => _showUnifiedMediaDialog('audio'),
            ),
            _buildDivider(),

            // 第十一组：其他功能
            quill.QuillToolbarClearFormatButton(
              controller: widget.controller,
              options: const quill.QuillToolbarClearFormatButtonOptions(),
            ),
            quill.QuillToolbarSearchButton(
              controller: widget.controller,
              options: const quill.QuillToolbarSearchButtonOptions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }

  Widget _buildMediaButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
            child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  /// 显示统一的媒体导入对话框
  void _showUnifiedMediaDialog(String mediaType) {
    showDialog(
      context: context,
      builder: (context) => UnifiedMediaImportDialog(
        mediaType: mediaType,
        onMediaImported: (String filePath) {
          _insertMediaIntoEditor(filePath, mediaType);
          // 将导入的媒体回传给上层（如编辑页）以便会话级追踪
          widget.onMediaImported?.call(filePath);
        },
      ),
    );
  }

  /// 将媒体文件插入到编辑器中
  void _insertMediaIntoEditor(String filePath, String mediaType) {
    try {
      final index = widget.controller.selection.baseOffset;
      final length = widget.controller.selection.extentOffset - index;

      // 根据媒体类型创建不同的嵌入块
      switch (mediaType) {
        case 'image':
          widget.controller.replaceText(
            index,
            length,
            quill.BlockEmbed.image(filePath),
            null,
          );
          break;
        case 'video':
          widget.controller.replaceText(
            index,
            length,
            quill.BlockEmbed.video(filePath),
            null,
          );
          break;
        case 'audio':
          // 创建自定义音频嵌入块
          final audioEmbed = quill.CustomBlockEmbed('audio', filePath);
          widget.controller.replaceText(index, length, audioEmbed, null);
          break;
      }

      // 移动光标到插入内容之后
      widget.controller.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        quill.ChangeSource.local,
      );
    } catch (e) {
      debugPrint('插入媒体文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插入${_getMediaTypeName(mediaType)}失败: $e')),
        );
      }
    }
  }

  String _getMediaTypeName(String type) {
    switch (type) {
      case 'image':
        return '图片';
      case 'video':
        return '视频';
      case 'audio':
        return '音频';
      default:
        return '媒体';
    }
  }
}

/// 兼容性别名，保持向后兼容
class FullScreenToolbar extends UnifiedQuillToolbar {
  const FullScreenToolbar({super.key, required super.controller});
}
