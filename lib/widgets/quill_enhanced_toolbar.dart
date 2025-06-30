import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:image_picker/image_picker.dart';

/// 增强的全屏编辑器工具栏组件
/// 支持图片、视频等扩展功能
class QuillEnhancedToolbar extends StatelessWidget {
  final quill.QuillController controller;
  final bool showExpandButton;
  final VoidCallback? onExpandPressed;

  const QuillEnhancedToolbar({
    super.key,
    required this.controller,
    this.showExpandButton = false,
    this.onExpandPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主工具栏
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
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
            child: quill.QuillSimpleToolbar(
              controller: controller,
              config: quill.QuillSimpleToolbarConfig(
                // 启用扩展功能按钮
                embedButtons: FlutterQuillEmbeds.toolbarButtons(),
                // 基础格式化选项
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
                // 对齐方式
                showAlignmentButtons: true,
                showDirection: true,
                showIndent: true,
                // 链接和其他
                showLink: true,
                showUndo: true,
                showRedo: true,
                showClearFormat: true,
                showSearchButton: true,
                // 布局配置
                multiRowsDisplay: false,
                toolbarIconAlignment: WrapAlignment.start,
                toolbarSectionSpacing: 4,
                // 自定义样式
                decoration: BoxDecoration(color: Colors.transparent),
                // 按钮选项配置
                buttonOptions: quill.QuillSimpleToolbarButtonOptions(
                  base: quill.QuillToolbarBaseButtonOptions(
                    iconSize: 20,
                    iconButtonFactor: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 扩展操作栏（可选）
        if (showExpandButton)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '全屏编辑模式',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onExpandPressed,
                  icon: const Icon(Icons.fullscreen_exit),
                  iconSize: 20,
                  tooltip: '退出全屏',
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 全屏编辑器页面的增强工具栏
class FullScreenToolbar extends StatefulWidget {
  final quill.QuillController controller;

  const FullScreenToolbar({super.key, required this.controller});

  @override
  State<FullScreenToolbar> createState() => _FullScreenToolbarState();
}

class _FullScreenToolbarState extends State<FullScreenToolbar> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isExpanded ? 120 : 60,
      child: Column(
        children: [
          // 主工具栏
          Container(
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
            child: Row(
              children: [
                // 展开/收起按钮
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  icon: Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  tooltip: _isExpanded ? '收起工具栏' : '展开工具栏',
                ),
                // 工具栏内容
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: quill.QuillSimpleToolbar(
                      controller: widget.controller,
                      config: quill.QuillSimpleToolbarConfig(
                        embedButtons: FlutterQuillEmbeds.toolbarButtons(),
                        multiRowsDisplay: false,
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        buttonOptions: quill.QuillSimpleToolbarButtonOptions(
                          base: quill.QuillToolbarBaseButtonOptions(
                            iconSize: 18,
                            iconButtonFactor: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 扩展工具栏
          if (_isExpanded)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                ),
                child: GridView.count(
                  crossAxisCount: 8,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildToolButton(
                      context,
                      Icons.image,
                      '插入图片',
                      () => _insertImage(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.videocam,
                      '插入视频',
                      () => _insertVideo(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.table_chart,
                      '插入表格',
                      () => _insertTable(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.horizontal_rule,
                      '分割线',
                      () => _insertDivider(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.emoji_emotions,
                      '表情符号',
                      () => _showEmojiPicker(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.functions,
                      '数学公式',
                      () => _insertFormula(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.link,
                      '插入链接',
                      () => _insertLink(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.access_time,
                      '时间戳',
                      () => _insertTimestamp(),
                    ),
                    _buildToolButton(
                      context,
                      Icons.more_horiz,
                      '更多',
                      () => _showMoreOptions(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  void _insertImage() async {
    // 显示图片来源选择
    final source = await showDialog<ImageSource>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('选择图片来源'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('从相册选择'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('拍照'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ],
            ),
          ),
    );

    if (source != null) {
      try {
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(source: source);

        if (image != null) {
          // 直接插入图片
          final index = widget.controller.selection.baseOffset;
          widget.controller.replaceText(
            index,
            0,
            quill.BlockEmbed.image(image.path),
            null,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('插入图片失败: $e')));
        }
      }
    }
  }

  void _insertVideo() async {
    // 直接选择视频文件
    try {
      final picker = ImagePicker();
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);

      if (video != null) {
        // 插入视频 embed
        final index = widget.controller.selection.baseOffset;
        widget.controller.replaceText(
          index,
          0,
          quill.BlockEmbed.video(video.path),
          null,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('插入视频失败: $e')));
      }
    }
  }

  void _insertTable() {
    // 插入简单表格
    const tableMarkdown = '''
| 列1 | 列2 | 列3 |
|-----|-----|-----|
| 内容1 | 内容2 | 内容3 |
| 内容4 | 内容5 | 内容6 |
''';
    final index = widget.controller.selection.baseOffset;
    widget.controller.document.insert(index, tableMarkdown);
    widget.controller.updateSelection(
      TextSelection.collapsed(offset: index + tableMarkdown.length),
      quill.ChangeSource.local,
    );
  }

  void _insertDivider() {
    // 插入分割线
    const divider = '\n---\n';
    final index = widget.controller.selection.baseOffset;
    widget.controller.document.insert(index, divider);
    widget.controller.updateSelection(
      TextSelection.collapsed(offset: index + divider.length),
      quill.ChangeSource.local,
    );
  }

  void _showEmojiPicker() {
    // 显示表情选择器
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('表情选择器即将推出')));
  }

  void _insertFormula() {
    // 插入数学公式占位符
    const formula = r'$$\LaTeX$$';
    final index = widget.controller.selection.baseOffset;
    widget.controller.document.insert(index, formula);
    widget.controller.updateSelection(
      TextSelection.collapsed(offset: index + formula.length),
      quill.ChangeSource.local,
    );
  }

  void _insertTimestamp() {
    // 插入当前时间戳
    final timestamp = DateTime.now().toString().substring(0, 19);
    final text = '[$timestamp] ';
    final index = widget.controller.selection.baseOffset;
    widget.controller.document.insert(index, text);
    widget.controller.updateSelection(
      TextSelection.collapsed(offset: index + text.length),
      quill.ChangeSource.local,
    );
  }

  void _showMoreOptions() {
    // 显示更多格式选项
    showModalBottomSheet(
      context: context,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.format_clear),
                  title: const Text('清除格式'),
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请使用工具栏中的清除格式按钮')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy),
                  title: const Text('复制选中内容'),
                  onTap: () {
                    // 复制功能
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('复制功能需要选中文本')));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.select_all),
                  title: const Text('全选'),
                  onTap: () {
                    // 全选文档内容
                    widget.controller.updateSelection(
                      TextSelection(
                        baseOffset: 0,
                        extentOffset: widget.controller.document.length - 1,
                      ),
                      quill.ChangeSource.local,
                    );
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.find_in_page),
                  title: const Text('查找替换'),
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('查找替换功能即将推出')));
                  },
                ),
              ],
            ),
          ),
    );
  }

  void _insertLink() async {
    // 显示链接输入对话框
    String? url;
    String? text;

    await showDialog(
      context: context,
      builder: (context) {
        final urlController = TextEditingController();
        final textController = TextEditingController();

        return AlertDialog(
          title: const Text('插入链接'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: '显示文本',
                  hintText: '链接显示的文本',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://example.com',
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                url = urlController.text.trim();
                text = textController.text.trim();
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (url != null && url!.isNotEmpty) {
      final displayText = text?.isNotEmpty == true ? text! : url!;
      final index = widget.controller.selection.baseOffset;

      // 插入链接格式的文本
      widget.controller.replaceText(
        index,
        0,
        displayText,
        TextSelection.collapsed(offset: index),
      );

      // 应用链接格式
      widget.controller.formatText(
        index,
        displayText.length,
        quill.LinkAttribute(url!),
      );
    }
  }
}
