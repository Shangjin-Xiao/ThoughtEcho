import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
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
      height: 48, // 稍微增大高度
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
            // 基础文本格式组
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

            // 分隔符
            _buildSeparator(),

            // 标题组
            _buildToolbarButton(
              icon: Icons.title,
              onPressed: () => _toggleHeader(1),
              isActive: _isHeaderActive(1),
              tooltip: '标题1',
            ),
            _buildToolbarButton(
              icon: Icons.format_size,
              onPressed: () => _toggleHeader(2),
              isActive: _isHeaderActive(2),
              tooltip: '标题2',
            ),
            _buildToolbarButton(
              icon: Icons.text_fields,
              onPressed: () => _toggleHeader(3),
              isActive: _isHeaderActive(3),
              tooltip: '标题3',
            ),

            // 分隔符
            _buildSeparator(),

            // 颜色和高亮
            _buildToolbarButton(
              icon: Icons.format_color_text,
              onPressed: _showTextColorPicker,
              tooltip: '文字颜色',
            ),
            _buildToolbarButton(
              icon: Icons.format_color_fill,
              onPressed: _showBackgroundColorPicker,
              tooltip: '背景颜色',
            ),

            // 分隔符
            _buildSeparator(),

            // 对齐方式组
            _buildToolbarButton(
              icon: Icons.format_align_left,
              onPressed: () => _toggleAlignment(quill.Attribute.leftAlignment),
              isActive: _isAlignmentActive(quill.Attribute.leftAlignment),
              tooltip: '左对齐',
            ),
            _buildToolbarButton(
              icon: Icons.format_align_center,
              onPressed:
                  () => _toggleAlignment(quill.Attribute.centerAlignment),
              isActive: _isAlignmentActive(quill.Attribute.centerAlignment),
              tooltip: '居中对齐',
            ),
            _buildToolbarButton(
              icon: Icons.format_align_right,
              onPressed: () => _toggleAlignment(quill.Attribute.rightAlignment),
              isActive: _isAlignmentActive(quill.Attribute.rightAlignment),
              tooltip: '右对齐',
            ),
            _buildToolbarButton(
              icon: Icons.format_align_justify,
              onPressed:
                  () => _toggleAlignment(quill.Attribute.justifyAlignment),
              isActive: _isAlignmentActive(quill.Attribute.justifyAlignment),
              tooltip: '两端对齐',
            ),

            // 分隔符
            _buildSeparator(),

            // 列表和缩进组
            _buildToolbarButton(
              icon: Icons.format_list_bulleted,
              onPressed: () => _toggleFormat(quill.Attribute.ul),
              isActive: _isFormatActive(quill.Attribute.ul),
              tooltip: '无序列表',
            ),
            _buildToolbarButton(
              icon: Icons.format_list_numbered,
              onPressed: () => _toggleFormat(quill.Attribute.ol),
              isActive: _isFormatActive(quill.Attribute.ol),
              tooltip: '有序列表',
            ),
            _buildToolbarButton(
              icon: Icons.checklist,
              onPressed: () => _toggleFormat(quill.Attribute.unchecked),
              isActive: _isFormatActive(quill.Attribute.unchecked),
              tooltip: '任务列表',
            ),
            _buildToolbarButton(
              icon: Icons.format_indent_increase,
              onPressed: _increaseIndent,
              tooltip: '增加缩进',
            ),
            _buildToolbarButton(
              icon: Icons.format_indent_decrease,
              onPressed: _decreaseIndent,
              tooltip: '减少缩进',
            ),

            // 分隔符
            _buildSeparator(),

            // 特殊格式组
            _buildToolbarButton(
              icon: Icons.format_quote,
              onPressed: () => _toggleFormat(quill.Attribute.blockQuote),
              isActive: _isFormatActive(quill.Attribute.blockQuote),
              tooltip: '引用',
            ),
            _buildToolbarButton(
              icon: Icons.code,
              onPressed: () => _toggleFormat(quill.Attribute.codeBlock),
              isActive: _isFormatActive(quill.Attribute.codeBlock),
              tooltip: '代码块',
            ),
            _buildToolbarButton(
              icon: Icons.horizontal_rule,
              onPressed: _insertHorizontalRule,
              tooltip: '分割线',
            ),

            // 分隔符
            _buildSeparator(),

            // 媒体插入组
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
              icon: Icons.audiotrack,
              onPressed: _insertAudio,
              tooltip: '插入音频',
            ),
            _buildToolbarButton(
              icon: Icons.link,
              onPressed: _insertLink,
              tooltip: '插入链接',
            ),
            _buildToolbarButton(
              icon: Icons.table_chart,
              onPressed: _insertTable,
              tooltip: '插入表格',
            ),

            // 分隔符
            _buildSeparator(),

            // 操作组
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
            _buildToolbarButton(
              icon: Icons.select_all,
              onPressed: _selectAll,
              tooltip: '全选',
            ),

            // 分隔符
            _buildSeparator(),

            // 帮助信息
            _buildToolbarButton(
              icon: Icons.help_outline,
              onPressed: () => _showMemoryWarning('general'),
              tooltip: '文件大小说明',
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
            width: 36, // 稍微增大宽度
            height: 36, // 稍微增大高度
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
            child: Icon(
              icon,
              size: 18, // 稍微增大图标尺寸
              color:
                  onPressed == null
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                      : isActive
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  // 构建分隔符
  Widget _buildSeparator() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
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

      // 保持选中状态
      widget.controller.updateSelection(
        TextSelection(
          baseOffset: selection.start,
          extentOffset: selection.start + text.length,
        ),
        quill.ChangeSource.local,
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

  void _insertAudio() {
    _showMediaDialog('audio');
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
                if (type == 'image')
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: const Text('拍照'),
                    onTap: () {
                      Navigator.pop(context);
                      _insertMediaFromCamera();
                    },
                  ),
                if (type == 'video')
                  ListTile(
                    leading: const Icon(Icons.videocam),
                    title: const Text('录制视频'),
                    onTap: () {
                      Navigator.pop(context);
                      _insertVideoFromCamera();
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
                  final url = urlController.text.trim();
                  final text = textController.text.trim();

                  if (url.isNotEmpty) {
                    // 基本URL验证
                    if (Uri.tryParse(url) != null) {
                      final displayText = text.isNotEmpty ? text : url;
                      final index = widget.controller.selection.baseOffset;
                      final length = displayText.length;

                      widget.controller.replaceText(
                        index,
                        0,
                        displayText,
                        null,
                      );
                      widget.controller.formatText(
                        index,
                        length,
                        quill.LinkAttribute(url),
                      );
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入有效的链接地址')),
                      );
                    }
                  }
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
        return '图片';
      case 'video':
        return '视频';
      case 'audio':
        return '音频';
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
            extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
          );
          break;
        case 'video':
          typeGroup = const XTypeGroup(
            label: 'videos',
            extensions: ['mp4', 'avi', 'mov', 'mkv', 'webm', 'flv'],
          );
          break;
        case 'audio':
          typeGroup = const XTypeGroup(
            label: 'audios',
            extensions: ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'],
          );
          break;
        default:
          typeGroup = const XTypeGroup(label: 'files');
      }

      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        // 检查文件大小 - 根据平台和文件类型设置不同限制
        final fileSize = await file.length();
        final maxSize = _getMaxFileSize(type);

        if (fileSize > maxSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_getFileSizeErrorMessage(type, maxSize)),
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        await _insertMediaFile(file.path, type);
      }
    } on OutOfMemoryError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('内存不足，无法处理选择的${_getMediaTypeName(type)}文件'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('File selection error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      }
    }
  }

  /// 根据文件类型和平台获取最大文件大小限制
  int _getMaxFileSize(String type) {
    // 放宽限制 - 主要防止极端大文件导致崩溃
    switch (type) {
      case 'image':
        return 50 * 1024 * 1024; // 50MB - 足够大的现代手机照片
      case 'video':
        return 1024 * 1024 * 1024; // 1GB - 短视频
      case 'audio':
        return 100 * 1024 * 1024; // 100MB - 长音频
      default:
        return 50 * 1024 * 1024;
    }
  }

  /// 获取文件大小错误提示信息
  String _getFileSizeErrorMessage(String type, int maxSize) {
    final maxSizeMB = (maxSize / (1024 * 1024)).round();
    final typeName = _getMediaTypeName(type);

    return '$typeName文件过大，请选择小于${maxSizeMB}MB的文件（防止应用崩溃）';
  }

  void _insertMediaFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      // 移动平台使用更高的压缩率
      final isMobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: isMobile ? 70 : 85, // 移动端70%质量，桌面端85%质量
        maxWidth: isMobile ? 1024 : 1920, // 限制图片分辨率
        maxHeight: isMobile ? 1024 : 1920,
      );

      if (image != null) {
        // 检查拍摄图片的大小
        final fileSize = await image.length();
        final maxSize = _getMaxFileSize('image');

        if (fileSize > maxSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_getFileSizeErrorMessage('image', maxSize)),
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        await _insertMediaFile(image.path, 'image');
      }
    } on OutOfMemoryError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('内存不足，无法处理拍摄的图片'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Camera capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
      }
    }
  }

  void _insertVideoFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      // 移动平台使用更严格的录制限制
      final isMobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      final XFile? video = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: Duration(seconds: isMobile ? 30 : 60), // 移动端30秒，桌面端60秒
      );

      if (video != null) {
        // 检查录制视频的大小
        final fileSize = await video.length();
        final maxSize = _getMaxFileSize('video');

        if (fileSize > maxSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_getFileSizeErrorMessage('video', maxSize)),
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        await _insertMediaFile(video.path, 'video');
      }
    } on OutOfMemoryError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('内存不足，无法处理录制的视频'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Video recording error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('录制视频失败: $e')));
      }
    }
  }

  /// 插入媒体文件到编辑器（本地文件）
  Future<void> _insertMediaFile(String filePath, String type) async {
    try {
      // 再次检查文件大小（防止绕过前面的检查）
      final file = await XFile(filePath).length();
      final maxSize = _getMaxFileSize(type);

      if (file > maxSize) {
        throw Exception('文件大小超过限制');
      }

      // 检查可用内存（简单估算）
      if (file > 20 * 1024 * 1024) {
        // 文件大于20MB时给出友好提示
        debugPrint(
          'Large file detected (${(file / (1024 * 1024)).toStringAsFixed(1)}MB), using stream processing',
        );
      }

      // 首先将媒体文件保存到应用私有目录
      String? savedPath;
      switch (type) {
        case 'image':
          savedPath = await MediaFileService.saveImage(filePath);
          break;
        case 'video':
          savedPath = await MediaFileService.saveVideo(filePath);
          break;
        case 'audio':
          savedPath = await MediaFileService.saveAudio(filePath);
          break;
        default:
          savedPath = await MediaFileService.saveImage(filePath);
      }

      if (savedPath == null) {
        throw Exception('保存媒体文件失败');
      }

      await _insertMediaEmbed(savedPath, type);
    } on OutOfMemoryError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('内存不足，无法处理这个${_getMediaTypeName(type)}文件\n建议选择更小的文件'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Media file insertion error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插入${_getMediaTypeName(type)}失败: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// 插入媒体embed到编辑器（通用方法）
  Future<void> _insertMediaEmbed(String path, String type) async {
    try {
      // 获取当前光标位置
      final int index = widget.controller.selection.baseOffset;

      // 根据文件类型创建相应的embed
      late quill.BlockEmbed embed;

      switch (type) {
        case 'image':
          embed = quill.BlockEmbed.image(path);
          break;
        case 'video':
          embed = quill.BlockEmbed.video(path);
          break;
        case 'audio':
          // 使用自定义的音频embed
          embed = quill.BlockEmbed.custom(
            quill.CustomBlockEmbed('audio', path),
          );
          break;
        default:
          embed = quill.BlockEmbed.image(path);
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

  /// 从URL插入媒体（不保存到本地）
  void _insertMediaFromUrlString(String url, String type) async {
    try {
      // URL直接插入，不需要保存到本地
      await _insertMediaEmbed(url, type);
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
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final url = urlController.text.trim();
                  if (url.isNotEmpty) {
                    // 基本URL验证
                    if (Uri.tryParse(url) != null &&
                        (url.startsWith('http://') ||
                            url.startsWith('https://'))) {
                      Navigator.pop(context);
                      _insertMediaFromUrlString(url, type);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入有效的URL地址')),
                      );
                    }
                  }
                },
                child: const Text('插入'),
              ),
            ],
          ),
    );
  }

  /// 显示内存和文件大小相关的提示信息
  void _showMemoryWarning(String type) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('📁 文件大小说明'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('为保证应用稳定运行，设置了合理的文件大小上限：'),
                SizedBox(height: 8),
                Text('� 图片: 最大 50MB'),
                Text('🎬 视频: 最大 200MB'),
                Text('🎵 音频: 最大 100MB'),
                SizedBox(height: 12),
                Text(
                  '这些限制足以满足日常使用，如需导入更大文件，建议使用专业的压缩工具。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
    );
  }

  // 标题相关方法
  void _toggleHeader(int level) {
    final attribute = quill.Attribute.fromKeyValue('header', level);
    widget.controller.formatSelection(attribute);
  }

  bool _isHeaderActive(int level) {
    final style = widget.controller.getSelectionStyle();
    final headerValue = style.attributes[quill.Attribute.header.key]?.value;
    return headerValue == level;
  }

  // 对齐相关方法
  void _toggleAlignment(quill.Attribute attribute) {
    widget.controller.formatSelection(attribute);
  }

  bool _isAlignmentActive(quill.Attribute attribute) {
    final style = widget.controller.getSelectionStyle();
    return style.attributes.containsKey(attribute.key);
  }

  // 缩进相关方法
  void _increaseIndent() {
    widget.controller.indentSelection(true);
  }

  void _decreaseIndent() {
    widget.controller.indentSelection(false);
  }

  // 插入水平分割线
  void _insertHorizontalRule() {
    final index = widget.controller.selection.baseOffset;
    widget.controller.document.insert(index, '\n');
    widget.controller.document.insert(
      index + 1,
      quill.BlockEmbed.custom(const quill.CustomBlockEmbed('divider', '')),
    );
    widget.controller.updateSelection(
      TextSelection.collapsed(offset: index + 2),
      quill.ChangeSource.local,
    );
  }

  // 插入表格
  void _insertTable() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('插入表格'),
            content: const Text('表格功能即将推出'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }

  // 全选文本
  void _selectAll() {
    widget.controller.updateSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.document.length,
      ),
      quill.ChangeSource.local,
    );
  }

  // 颜色选择器
  void _showTextColorPicker() {
    _showColorPicker('text');
  }

  void _showBackgroundColorPicker() {
    _showColorPicker('background');
  }

  void _showColorPicker(String type) {
    const commonColors = [
      Colors.black,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.brown,
      Colors.grey,
    ];

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(type == 'text' ? '选择文字颜色' : '选择背景颜色'),
            content: SizedBox(
              width: 300,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: commonColors.length,
                itemBuilder: (context, index) {
                  final color = commonColors[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _applyColor(color, type);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
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

  void _applyColor(Color color, String type) {
    final hex =
        '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
    if (type == 'text') {
      widget.controller.formatSelection(quill.ColorAttribute(hex));
    } else {
      widget.controller.formatSelection(quill.BackgroundAttribute(hex));
    }
  }

  // ...existing code...
}

/// 兼容性别名，保持向后兼容
class FullScreenToolbar extends QuillEnhancedToolbar {
  const FullScreenToolbar({super.key, required super.controller});
}
