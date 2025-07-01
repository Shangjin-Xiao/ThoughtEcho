import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import '../services/media_file_service.dart';

/// 增强的全屏编辑器工具栏组件
/// 基于flutter_quill官方按钮的完整实现
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
      height: 56, // 增加高度以容纳更多按钮
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

            // 第二组：基础格式（加粗、斜体、下划线、删除线）
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

            // 第三组：颜色（文字色、背景色）
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

            // 第四组：标题
            quill.QuillToolbarSelectHeaderStyleDropdownButton(
              controller: widget.controller,
              options:
                  const quill.QuillToolbarSelectHeaderStyleDropdownButtonOptions(),
            ),
            _buildDivider(),

            // 第五组：对齐方式
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.leftAlignment,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.centerAlignment,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.rightAlignment,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.justifyAlignment,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            _buildDivider(),

            // 第六组：列表
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
            quill.QuillToolbarToggleCheckListButton(
              controller: widget.controller,
              options: const quill.QuillToolbarToggleCheckListButtonOptions(),
            ),
            _buildDivider(),

            // 第七组：缩进
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
            quill.QuillToolbarToggleStyleButton(
              controller: widget.controller,
              attribute: quill.Attribute.inlineCode,
              options: const quill.QuillToolbarToggleStyleButtonOptions(),
            ),
            _buildDivider(),

            // 第九组：链接
            quill.QuillToolbarLinkStyleButton(
              controller: widget.controller,
              options: const quill.QuillToolbarLinkStyleButtonOptions(),
            ),
            _buildDivider(),

            // 第十组：媒体插入
            _buildMediaButton(
              icon: Icons.image,
              tooltip: '插入图片',
              onPressed: () => _insertImage(),
            ),
            _buildMediaButton(
              icon: Icons.videocam,
              tooltip: '插入视频',
              onPressed: () => _insertVideo(),
            ),
            _buildMediaButton(
              icon: Icons.audiotrack,
              tooltip: '插入音频',
              onPressed: () => _insertAudio(),
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
            _buildDivider(),

            // 第十二组：帮助
            _buildMediaButton(
              icon: Icons.help_outline,
              tooltip: '文件大小说明',
              onPressed: () => _showFileSizeInfo(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 1,
      height: 24,
      color: theme.colorScheme.outlineVariant.withOpacity(0.5),
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
        // 检查文件大小
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
    } catch (e) {
      debugPrint('文件选择错误: $e');
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
      final isMobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: isMobile ? 70 : 85,
        maxWidth: isMobile ? 1024 : 1920,
        maxHeight: isMobile ? 1024 : 1920,
      );

      if (image != null) {
        await _insertMediaFile(image.path, 'image');
      }
    } catch (e) {
      debugPrint('拍照错误: $e');
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
      final isMobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      final XFile? video = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: Duration(seconds: isMobile ? 30 : 60),
      );

      if (video != null) {
        await _insertMediaFile(video.path, 'video');
      }
    } catch (e) {
      debugPrint('录制视频错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('录制视频失败: $e')));
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

  void _insertMediaFromUrlString(String url, String type) async {
    try {
      await _insertMediaEmbed(url, type);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插入${_getMediaTypeName(type)}失败: $e')),
        );
      }
    }
  }

  Future<void> _insertMediaFile(String filePath, String type) async {
    try {
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
    } catch (e) {
      debugPrint('媒体文件插入错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插入${_getMediaTypeName(type)}失败: $e')),
        );
      }
    }
  }

  Future<void> _insertMediaEmbed(String path, String type) async {
    try {
      final int index = widget.controller.selection.baseOffset;
      late quill.BlockEmbed embed;

      switch (type) {
        case 'image':
          embed = quill.BlockEmbed.image(path);
          break;
        case 'video':
          embed = quill.BlockEmbed.video(path);
          break;
        case 'audio':
          embed = quill.BlockEmbed.custom(
            quill.CustomBlockEmbed('audio', path),
          );
          break;
        default:
          embed = quill.BlockEmbed.image(path);
      }

      widget.controller.document.insert(index, embed);
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

  int _getMaxFileSize(String type) {
    switch (type) {
      case 'image':
        return 50 * 1024 * 1024; // 50MB
      case 'video':
        return 200 * 1024 * 1024; // 200MB
      case 'audio':
        return 100 * 1024 * 1024; // 100MB
      default:
        return 50 * 1024 * 1024;
    }
  }

  String _getFileSizeErrorMessage(String type, int maxSize) {
    final maxSizeMB = (maxSize / (1024 * 1024)).round();
    final typeName = _getMediaTypeName(type);
    return '$typeName文件过大，请选择小于${maxSizeMB}MB的文件';
  }

  void _showFileSizeInfo() {
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
                Text('📸 图片: 最大 50MB'),
                Text('🎬 视频: 最大 200MB'),
                Text('🎵 音频: 最大 100MB'),
                SizedBox(height: 12),
                Text(
                  '这些限制足以满足日常使用，使用流式处理技术确保大文件也能稳定处理。',
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
}

/// 兼容性别名，保持向后兼容
class FullScreenToolbar extends QuillEnhancedToolbar {
  const FullScreenToolbar({super.key, required super.controller});
}
