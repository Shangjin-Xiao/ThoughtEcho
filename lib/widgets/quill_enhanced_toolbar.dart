import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import '../services/media_file_service.dart';

/// 增强的全屏编辑器工具栏组件
/// 重写版本 - 确保稳定显示和完整功能
class QuillEnhancedToolbar extends StatefulWidget {
  final quill.QuillController controller;

  const QuillEnhancedToolbar({super.key, required this.controller});

  @override
  State<QuillEnhancedToolbar> createState() => _QuillEnhancedToolbarState();
}

class _QuillEnhancedToolbarState extends State<QuillEnhancedToolbar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 44, // 紧凑高度
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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // 所有按钮放在一行，支持左右滑动
            _buildToolbarButton(
              icon: Icons.format_bold,
              onPressed: () => _toggleFormat(quill.Attribute.bold),
              isActive: _isFormatActive(quill.Attribute.bold),
              tooltip: '粗体',
            ),
            _buildToolbarButton(
              icon: Icons.format_italic,
              onPressed: () => _toggleFormat(quill.Attribute.italic),
              isActive: _isFormatActive(quill.Attribute.italic),
              tooltip: '斜体',
            ),
            _buildToolbarButton(
              icon: Icons.format_underlined,
              onPressed: () => _toggleFormat(quill.Attribute.underline),
              isActive: _isFormatActive(quill.Attribute.underline),
              tooltip: '下划线',
            ),
            _buildToolbarButton(
              icon: Icons.strikethrough_s,
              onPressed: () => _toggleFormat(quill.Attribute.strikeThrough),
              isActive: _isFormatActive(quill.Attribute.strikeThrough),
              tooltip: '删除线',
            ),
            _buildToolbarButton(
              icon: Icons.format_list_numbered,
              onPressed: () => _toggleFormat(quill.Attribute.ol),
              isActive: _isFormatActive(quill.Attribute.ol),
              tooltip: '有序列表',
            ),
            _buildToolbarButton(
              icon: Icons.format_list_bulleted,
              onPressed: () => _toggleFormat(quill.Attribute.ul),
              isActive: _isFormatActive(quill.Attribute.ul),
              tooltip: '无序列表',
            ),
            _buildToolbarButton(
              icon: Icons.format_quote,
              onPressed: () => _toggleFormat(quill.Attribute.blockQuote),
              isActive: _isFormatActive(quill.Attribute.blockQuote),
              tooltip: '引用',
            ),
            _buildToolbarButton(
              icon: Icons.image,
              onPressed: _insertImage,
              tooltip: '插入图片',
            ),
            _buildToolbarButton(
              icon: Icons.videocam,
              onPressed: _insertVideo,
              tooltip: '插入视频',
            ),
            _buildToolbarButton(
              icon: Icons.camera_alt,
              onPressed: _insertCamera,
              tooltip: '拍照',
            ),
            _buildToolbarButton(
              icon: Icons.link,
              onPressed: _insertLink,
              tooltip: '插入链接',
            ),
            _buildToolbarButton(
              icon: Icons.undo,
              onPressed:
                  widget.controller.hasUndo ? widget.controller.undo : null,
              tooltip: '撤销',
            ),
            _buildToolbarButton(
              icon: Icons.redo,
              onPressed:
                  widget.controller.hasRedo ? widget.controller.redo : null,
              tooltip: '重做',
            ),
            _buildToolbarButton(
              icon: Icons.format_clear,
              onPressed: _clearFormat,
              tooltip: '清除格式',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    VoidCallback? onPressed,
    bool isActive = false,
    required String tooltip,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1), // 减小水平间距
      child: Material(
        color:
            isActive ? theme.colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(4), // 减小圆角
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 32, // 减小宽度从40到32
            height: 32, // 减小高度从40到32
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
            child: Icon(
              icon,
              size: 16, // 减小图标尺寸从18到16
              color:
                  onPressed == null
                      ? theme.colorScheme.onSurface.withOpacity(0.38)
                      : isActive
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  // 格式化相关方法
  void _toggleFormat(quill.Attribute attribute) {
    widget.controller.formatSelection(attribute);
  }

  bool _isFormatActive(quill.Attribute attribute) {
    final style = widget.controller.getSelectionStyle();
    return style.attributes.containsKey(attribute.key);
  }

  void _clearFormat() {
    // 清除所有格式
    final selection = widget.controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      // 获取选中文本内容
      final text = widget.controller.document.getPlainText(
        selection.start,
        selection.end - selection.start,
      );

      // 删除选中文本并重新插入无格式文本
      widget.controller.replaceText(
        selection.start,
        selection.end - selection.start,
        text,
        null,
      );
    }
  }

  // 媒体插入方法
  void _insertImage() {
    _showMediaDialog('image');
  }

  void _insertVideo() {
    _showMediaDialog('video');
  }

  void _insertCamera() {
    _showMediaDialog('camera');
  }

  void _insertLink() {
    _showLinkDialog();
  }

  void _showMediaDialog(String type) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('插入${_getMediaTypeName(type)}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload),
                  title: const Text('从文件选择'),
                  onTap: () {
                    Navigator.pop(context);
                    _insertMediaFromFile(type);
                  },
                ),
                if (type == 'image' || type == 'camera')
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: const Text('拍照'),
                    onTap: () {
                      Navigator.pop(context);
                      _insertMediaFromCamera();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('从网址'),
                  onTap: () {
                    Navigator.pop(context);
                    _insertMediaFromUrl(type);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
    );
  }

  void _showLinkDialog() {
    final TextEditingController urlController = TextEditingController();
    final TextEditingController textController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('插入链接'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textController,
                  decoration: const InputDecoration(
                    labelText: '链接文本',
                    hintText: '显示的文字',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: '链接地址',
                    hintText: 'https://example.com',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (urlController.text.isNotEmpty) {
                    final text =
                        textController.text.isNotEmpty
                            ? textController.text
                            : urlController.text;

                    final index = widget.controller.selection.baseOffset;
                    final length = text.length;

                    widget.controller.replaceText(index, 0, text, null);
                    widget.controller.formatText(
                      index,
                      length,
                      quill.LinkAttribute(urlController.text),
                    );
                  }
                  Navigator.pop(context);
                },
                child: const Text('插入'),
              ),
            ],
          ),
    );
  }

  String _getMediaTypeName(String type) {
    switch (type) {
      case 'image':
      case 'camera':
        return '图片';
      case 'video':
        return '视频';
      default:
        return '媒体';
    }
  }

  void _insertMediaFromFile(String type) async {
    try {
      XTypeGroup typeGroup;
      switch (type) {
        case 'image':
          typeGroup = const XTypeGroup(
            label: 'images',
            extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
          );
          break;
        case 'video':
          typeGroup = const XTypeGroup(
            label: 'videos',
            extensions: ['mp4', 'avi', 'mov', 'mkv', 'webm'],
          );
          break;
        default:
          typeGroup = const XTypeGroup(label: 'files');
      }

      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        await _insertMediaFile(file.path, type);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      }
    }
  }

  void _insertMediaFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);

      if (image != null) {
        await _insertMediaFile(image.path, 'image');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
      }
    }
  }

  /// 插入媒体文件到编辑器
  Future<void> _insertMediaFile(String filePath, String type) async {
    try {
      // 获取当前光标位置
      final int index = widget.controller.selection.baseOffset;

      String? savedPath;

      // 将文件保存到应用目录
      switch (type) {
        case 'image':
          savedPath = await MediaFileService.saveImage(filePath);
          break;
        case 'video':
          savedPath = await MediaFileService.saveVideo(filePath);
          break;
        default:
          // 对于其他文件类型，尝试作为图片保存
          savedPath = await MediaFileService.saveImage(filePath);
      }

      if (savedPath == null) {
        throw Exception('保存媒体文件失败');
      }

      // 根据文件类型创建相应的embed
      late quill.BlockEmbed embed;

      switch (type) {
        case 'image':
          embed = quill.BlockEmbed.image(savedPath);
          break;
        case 'video':
          embed = quill.BlockEmbed.video(savedPath);
          break;
        default:
          // 对于其他文件类型，作为图片处理
          embed = quill.BlockEmbed.image(savedPath);
      }

      // 插入embed到文档
      widget.controller.document.insert(index, embed);

      // 移动光标到插入内容之后
      widget.controller.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        quill.ChangeSource.local,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_getMediaTypeName(type)}插入成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插入${_getMediaTypeName(type)}失败: $e')),
        );
      }
    }
  }

  /// 从URL插入媒体
  void _insertMediaFromUrlString(String url, String type) async {
    try {
      // 对于URL，直接插入不保存到本地
      final int index = widget.controller.selection.baseOffset;

      // 根据文件类型创建相应的embed
      late quill.BlockEmbed embed;

      switch (type) {
        case 'image':
          embed = quill.BlockEmbed.image(url);
          break;
        case 'video':
          embed = quill.BlockEmbed.video(url);
          break;
        default:
          // 对于其他文件类型，作为图片处理
          embed = quill.BlockEmbed.image(url);
      }

      // 插入embed到文档
      widget.controller.document.insert(index, embed);

      // 移动光标到插入内容之后
      widget.controller.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        quill.ChangeSource.local,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_getMediaTypeName(type)}插入成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插入${_getMediaTypeName(type)}失败: $e')),
        );
      }
    }
  }

  void _insertMediaFromUrl(String type) {
    final TextEditingController urlController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('插入${_getMediaTypeName(type)}链接'),
            content: TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: '${_getMediaTypeName(type)}地址',
                hintText: 'https://example.com/media.jpg',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (urlController.text.isNotEmpty) {
                    _insertMediaFromUrlString(urlController.text, type);
                  }
                  Navigator.pop(context);
                },
                child: const Text('插入'),
              ),
            ],
          ),
    );
  }
}

/// 兼容性别名，保持向后兼容
class FullScreenToolbar extends QuillEnhancedToolbar {
  const FullScreenToolbar({super.key, required super.controller});
}
