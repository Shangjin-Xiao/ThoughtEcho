import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/database_service.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/ai_service.dart'; // 导入AI服务
import '../utils/time_utils.dart'; // 导入时间工具类
import 'package:flex_color_picker/flex_color_picker.dart';
import '../utils/icon_utils.dart';
import 'dart:math' show min; // 添加math包导入

class NoteFullEditorPage extends StatefulWidget {
  final String initialContent;
  final Quote? initialQuote;
  final List<NoteCategory>? allTags;
  const NoteFullEditorPage({
    super.key,
    required this.initialContent,
    this.initialQuote,
    this.allTags,
  });

  @override
  State<NoteFullEditorPage> createState() => _NoteFullEditorPageState();
}

class _NoteFullEditorPageState extends State<NoteFullEditorPage> {
  late quill.QuillController _controller;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  late List<String> _selectedTagIds; // 选中标签ID列表
  String? _selectedColorHex;
  String? _location;
  String? _weather;
  String? _temperature;
  // 分离位置和天气控制
  bool _showLocation = false;
  bool _showWeather = false;

  @override
  void initState() {
    super.initState();
    // 尝试将initialContent作为Delta解析，否则作为纯文本插入
    if (widget.initialQuote?.deltaContent != null) {
      // 如果有富文本内容，优先使用富文本
      try {
        final document = quill.Document.fromJson(
          jsonDecode(widget.initialQuote!.deltaContent!),
        );
        _controller = quill.QuillController(
          document: document,
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (_) {
        _initializeAsPlainText();
      }
    } else {
      _initializeAsPlainText();
    }

    // 作者/作品
    _authorController = TextEditingController(
      text: widget.initialQuote?.sourceAuthor ?? '',
    );
    _workController = TextEditingController(
      text: widget.initialQuote?.sourceWork ?? '',
    );
    _selectedTagIds = widget.initialQuote?.tagIds ?? [];
    // 颜色
    _selectedColorHex = widget.initialQuote?.colorHex;
    // 位置/天气 - 分别设置状态
    _location = widget.initialQuote?.location;
    _weather = widget.initialQuote?.weather;
    _temperature = widget.initialQuote?.temperature;

    // 分别检查并设置位置和天气状态
    _showLocation = _location != null;
    _showWeather = _weather != null;
  }

  // 初始化为纯文本的辅助方法
  void _initializeAsPlainText() {
    _controller = quill.QuillController(
      document: quill.Document()..insert(0, widget.initialContent),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  // 天气图标映射方法
  IconData _getWeatherIcon(String weatherKey) {
    return WeatherService.getWeatherIconDataByKey(weatherKey);
  }

  Future<void> _fetchLocationWeather() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    // 检查并请求权限
    if (!locationService.hasLocationPermission) {
      bool permissionGranted =
          await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法获取位置权限')));
        }
        return;
      }
    }

    final position = await locationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        _location = locationService.getFormattedLocation();
      });

      // 获取天气
      await weatherService.getWeatherData(
        position.latitude,
        position.longitude,
      );
      setState(() {
        _weather = weatherService.currentWeather;
        _temperature = weatherService.temperature;
      });
    }
  }

  Future<void> _saveContent() async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    final plainTextContent =
        _controller.document.toPlainText().trim(); // 获取纯文本内容
    final deltaJson = jsonEncode(_controller.document.toDelta().toJson());
    final now = DateTime.now().toIso8601String();

    // 获取当前时间段
    final String currentDayPeriodKey =
        TimeUtils.getCurrentDayPeriodKey(); // 使用 Key

    // 构建笔记对象
    final quote = Quote(
      id: widget.initialQuote?.id ?? const Uuid().v4(),
      content: plainTextContent,
      date: widget.initialQuote?.date ?? now,
      aiAnalysis: widget.initialQuote?.aiAnalysis,
      source: _formatSource(_authorController.text, _workController.text),
      sourceAuthor: _authorController.text,
      sourceWork: _workController.text,
      tagIds: _selectedTagIds,
      sentiment: widget.initialQuote?.sentiment,
      keywords: widget.initialQuote?.keywords,
      summary: widget.initialQuote?.summary,
      categoryId: widget.initialQuote?.categoryId,
      colorHex: _selectedColorHex,
      location: _showLocation ? _location : null,
      weather: _showWeather ? _weather : null,
      temperature: _showWeather ? _temperature : null,
      deltaContent: deltaJson,
      editSource: 'fullscreen',
      dayPeriod:
          widget.initialQuote?.dayPeriod ?? currentDayPeriodKey, // 保存 Key
    );

    try {
      if (widget.initialQuote != null) {
        // 更新现有笔记
        await db.updateQuote(quote);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('笔记已更新')));
          // 成功更新后，关闭页面并返回
          Navigator.of(context).pop(true); // 返回true表示更新成功
        }
      } else {
        // 添加新笔记
        await db.addQuote(quote);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('笔记已保存')));
          // 成功添加后，关闭页面并返回
          Navigator.of(context).pop(true); // 返回true表示保存成功
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 格式化来源（从作者和作品）
  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$work》';
    }

    return result;
  }

  // 判断是否为表情符号
  bool _isEmoji(String? iconName) {
    if (iconName == null) return false;
    return iconName.startsWith('emoji:');
  }

  // 获取显示图标
  String _getDisplayIcon(String? iconName) {
    if (iconName == null) return '🏷️';
    if (iconName.startsWith('emoji:')) {
      return iconName.substring(6); // 移除'emoji:'前缀
    }
    return '🏷️'; // 默认标签图标
  }

  // 获取图标数据
  IconData _getIconData(String? iconName) {
    if (iconName == null) return Icons.label;
    if (iconName.startsWith('emoji:')) {
      // 表情符号由Text组件处理，这里不需要返回IconData
      return Icons.emoji_emotions;
    }

    // 使用IconUtils转换图标名到图标数据
    try {
      final iconData = IconUtils.getIconData(iconName);
      return iconData;
    } catch (e) {
      return Icons.label;
    }
  }

  // 自定义颜色选择器
  Future<void> _showCustomColorPicker(BuildContext context) async {
    final Color initialColor =
        _selectedColorHex != null
            ? Color(
              int.parse(_selectedColorHex!.substring(1), radix: 16) |
                  0xFF000000,
            )
            : Colors.transparent;

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // 预设颜色列表 - 更现代的轻柔色调
    final List<Color> presetColors = [
      Colors.transparent, // 透明/无
      const Color(0xFFF9E4E4), // 轻红色
      const Color(0xFFFFF0E1), // 轻橙色
      const Color(0xFFFFFBE5), // 轻黄色
      const Color(0xFFE8F5E9), // 轻绿色
      const Color(0xFFE1F5FE), // 轻蓝色
      const Color(0xFFF3E5F5), // 轻紫色
      const Color(0xFFFCE4EC), // 轻粉色

      const Color(0xFFFFCDD2), // 红色
      const Color(0xFFFFE0B2), // 橙色
      const Color(0xFFFFF9C4), // 黄色
      const Color(0xFFC8E6C9), // 绿色
      const Color(0xFFBBDEFB), // 蓝色
      const Color(0xFFE1BEE7), // 紫色
      const Color(0xFFF8BBD0), // 粉色

      const Color(0xFFEF9A9A), // 深红色
      const Color(0xFFFFCC80), // 深橙色
      const Color(0xFFFFF59D), // 深黄色
      const Color(0xFFA5D6A7), // 深绿色
      const Color(0xFF90CAF9), // 深蓝色
      const Color(0xFFCE93D8), // 深紫色
      const Color(0xFFF48FB1), // 深粉色
    ];

    final Color? result = await showDialog<Color>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('选择卡片颜色'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 预设颜色网格
                  Container(
                    width: 280,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            '预设颜色',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.start,
                          children:
                              presetColors.map((color) {
                                String? colorHex;
                                if (color != Colors.transparent) {
                                  colorHex =
                                      '#${color.value.toRadixString(16).substring(2)}';
                                }

                                final bool isSelected =
                                    color == Colors.transparent
                                        ? _selectedColorHex == null
                                        : _selectedColorHex == colorHex;

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).pop(color);
                                  },
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(21),
                                      border: Border.all(
                                        color:
                                            isSelected
                                                ? colorScheme.primary
                                                : color == Colors.transparent
                                                ? Colors.grey.withOpacity(0.5)
                                                : Colors.transparent,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          spreadRadius: 1,
                                          blurRadius: 3,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child:
                                          isSelected
                                              ? Icon(
                                                Icons.check_circle,
                                                color:
                                                    color ==
                                                                Colors
                                                                    .transparent ||
                                                            color.computeLuminance() >
                                                                0.7
                                                        ? colorScheme.primary
                                                        : Colors.white,
                                                size: 24,
                                              )
                                              : color == Colors.transparent
                                              ? const Icon(
                                                Icons.block,
                                                color: Colors.grey,
                                                size: 18,
                                              )
                                              : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 高级颜色选择按钮
                  OutlinedButton.icon(
                    icon: const Icon(Icons.color_lens),
                    label: const Text('自定义颜色'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(context); // 关闭当前对话框

                      // 打开高级颜色选择器
                      final Color? advancedColor = await showDialog<Color>(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: const Text('自定义颜色'),
                              content: SingleChildScrollView(
                                child: ColorPicker(
                                  color:
                                      initialColor != Colors.transparent
                                          ? initialColor
                                          : const Color(0xFFE1F5FE), // 默认蓝色
                                  onColorChanged: (color) {},
                                  width: 40,
                                  height: 40,
                                  spacing: 10,
                                  runSpacing: 10,
                                  borderRadius: 20,
                                  wheelDiameter: 200,
                                  enableShadesSelection: true,
                                  pickersEnabled: const {
                                    ColorPickerType.primary: true,
                                    ColorPickerType.accent: false,
                                    ColorPickerType.wheel: true,
                                  },
                                ),
                              ),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed:
                                      () => Navigator.of(
                                        context,
                                      ).pop(initialColor),
                                  child: const Text('选择'),
                                ),
                              ],
                            ),
                      );

                      if (advancedColor != null && mounted) {
                        setState(() {
                          _selectedColorHex =
                              advancedColor == Colors.transparent
                                  ? null
                                  : '#${advancedColor.value.toRadixString(16).substring(2)}';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
    );

    if (result != null) {
      setState(() {
        _selectedColorHex =
            result == Colors.transparent
                ? null
                : '#${result.value.toRadixString(16).substring(2)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          // 使用悬浮按钮展示元数据编辑弹窗
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '编辑元数据',
            onPressed: () => _showMetadataDialog(context),
          ),
          // AI助手按钮
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI助手',
            onPressed: () => _showAIOptions(context),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '保存',
            onPressed: _saveContent,
          ),
        ],
        automaticallyImplyLeading: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 紧凑型工具栏
            // Wrap the toolbar in a SingleChildScrollView for horizontal scrolling
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: 45,
                child: quill.QuillSimpleToolbar(controller: _controller),
              ),
            ),
            // 显示已选元数据指示条
            if (_selectedTagIds.isNotEmpty ||
                _selectedColorHex != null ||
                _showLocation ||
                _showWeather)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (_selectedTagIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text('${_selectedTagIds.length}个标签'),
                          avatar: const Icon(Icons.tag, size: 16),
                        ),
                      ),
                    if (_selectedColorHex != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Color(
                              int.parse(
                                    _selectedColorHex!.substring(1),
                                    radix: 16,
                                  ) |
                                  0xFF000000,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    if (_showLocation && _location != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          Icons.location_on,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    if (_showWeather && _weather != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          _getWeatherIcon(_weather!),
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _showMetadataDialog(context),
                      child: const Text(
                        '编辑元数据',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            // 编辑器主体
            Expanded(
              child: Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.all(16),
                child: quill.QuillEditor.basic(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 显示元数据编辑弹窗
  Future<void> _showMetadataDialog(BuildContext context) async {
    final theme = Theme.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(
                            0.4,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Row(
                        children: [
                          Text(
                            '编辑元数据',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('完成'),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          // 作者/作品输入
                          const Text(
                            '来源信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _authorController,
                                  decoration: const InputDecoration(
                                    hintText: '作者/人物',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _workController,
                                  decoration: const InputDecoration(
                                    hintText: '作品/来源',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // 标签选择
                          Row(
                            children: [
                              const Text(
                                '标签',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '已选择 ${_selectedTagIds.length} 个标签',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ExpansionTile(
                              title: const Text('选择标签'),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              children: [
                                // 搜索框
                                TextField(
                                  decoration: const InputDecoration(
                                    hintText: '搜索标签...',
                                    prefixIcon: Icon(Icons.search),
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 8.0,
                                      horizontal: 12.0,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    // 可以添加标签搜索逻辑
                                  },
                                ),
                                const SizedBox(height: 8),
                                // 标签列表
                                Container(
                                  constraints: const BoxConstraints(
                                    maxHeight: 200,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Wrap(
                                      spacing: 8.0,
                                      runSpacing: 8.0,
                                      children:
                                          widget.allTags!.map((tag) {
                                            final selected = _selectedTagIds
                                                .contains(tag.id);
                                            return FilterChip(
                                              selected: selected,
                                              label: Text(tag.name),
                                              avatar:
                                                  _isEmoji(tag.iconName)
                                                      ? Text(
                                                        _getDisplayIcon(
                                                          tag.iconName,
                                                        ),
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                        ),
                                                      )
                                                      : Icon(
                                                        _getIconData(
                                                          tag.iconName,
                                                        ),
                                                        size: 16,
                                                      ),
                                              onSelected: (bool value) {
                                                setState(() {
                                                  if (value) {
                                                    _selectedTagIds.add(tag.id);
                                                  } else {
                                                    _selectedTagIds.remove(
                                                      tag.id,
                                                    );
                                                  }
                                                });
                                              },
                                              selectedColor:
                                                  theme
                                                      .colorScheme
                                                      .primaryContainer,
                                              checkmarkColor:
                                                  theme.colorScheme.primary,
                                            );
                                          }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 显示已选标签
                          if (_selectedTagIds.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '已选标签',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8.0,
                                    runSpacing: 4.0,
                                    children:
                                        _selectedTagIds.map((tagId) {
                                          final tag = widget.allTags!.firstWhere(
                                            (t) => t.id == tagId,
                                            orElse:
                                                () => NoteCategory(
                                                  id: tagId,
                                                  name:
                                                      '未知标签(ID:${tagId.substring(0, min(4, tagId.length))}...)',
                                                  iconName: 'help_outline',
                                                ),
                                          );
                                          return Chip(
                                            label: Text(tag.name),
                                            avatar: _buildTagIcon(tag),
                                            onDeleted: () {
                                              setState(() {
                                                _selectedTagIds.remove(tagId);
                                              });
                                            },
                                          );
                                        }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 24),

                          // 颜色选择
                          const Text(
                            '颜色',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ListTile(
                              title: const Text('选择卡片颜色'),
                              subtitle: Text(
                                _selectedColorHex == null ? '无颜色' : '已设置颜色',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color:
                                      _selectedColorHex != null
                                          ? Color(
                                            int.parse(
                                                  _selectedColorHex!.substring(
                                                    1,
                                                  ),
                                                  radix: 16,
                                                ) |
                                                0xFF000000,
                                          )
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        _selectedColorHex == null
                                            ? theme.colorScheme.outline
                                            : Colors.transparent,
                                  ),
                                ),
                                child:
                                    _selectedColorHex == null
                                        ? Icon(
                                          Icons.block,
                                          size: 16,
                                          color: theme.colorScheme.outline,
                                        )
                                        : null,
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              onTap: () => _showCustomColorPicker(context),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 天气和位置
                          const Text(
                            '位置和天气',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // 位置信息按钮
                              FilterChip(
                                avatar: Icon(
                                  Icons.location_on,
                                  color:
                                      _showLocation
                                          ? theme.colorScheme.primary
                                          : Colors.grey,
                                  size: 18,
                                ),
                                label: const Text('位置'),
                                selected: _showLocation,
                                onSelected: (value) {
                                  setState(() {
                                    _showLocation = value;
                                    // 如果开启了位置但还没有数据，则自动获取
                                    if (_showLocation && _location == null) {
                                      _fetchLocationWeather();
                                    }
                                  });
                                },
                                selectedColor:
                                    theme.colorScheme.primaryContainer,
                              ),
                              const SizedBox(width: 8),
                              // 天气信息按钮
                              FilterChip(
                                avatar: Icon(
                                  _weather != null
                                      ? _getWeatherIcon(_weather!)
                                      : Icons.cloud,
                                  color:
                                      _showWeather
                                          ? theme.colorScheme.primary
                                          : Colors.grey,
                                  size: 18,
                                ),
                                label: const Text('天气'),
                                selected: _showWeather,
                                onSelected: (value) {
                                  setState(() {
                                    _showWeather = value;
                                    // 如果开启了天气但还没有数据，则自动获取
                                    if (_showWeather && _weather == null) {
                                      _fetchLocationWeather();
                                    }
                                  });
                                },
                                selectedColor:
                                    theme.colorScheme.primaryContainer,
                              ),
                              const Spacer(),
                              // 刷新按钮
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: '刷新位置和天气',
                                onPressed: () {
                                  _fetchLocationWeather();
                                  setState(() {}); // 刷新UI
                                },
                              ),
                            ],
                          ),
                          // 显示位置和天气信息
                          if (_location != null || _weather != null)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_location != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _location!,
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_weather != null)
                                    Row(
                                      children: [
                                        Icon(
                                          _getWeatherIcon(_weather!),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          WeatherService.getWeatherDescription(
                                            _weather!,
                                          ),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        if (_temperature != null)
                                          Text(
                                            ' $_temperature',
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    // 对话框关闭后刷新UI
    setState(() {});
  }

  Widget _buildTagIcon(NoteCategory tag) {
    if (_isEmoji(tag.iconName)) {
      return Text(
        _getDisplayIcon(tag.iconName),
        style: const TextStyle(fontSize: 16),
      );
    } else {
      return Icon(_getIconData(tag.iconName), size: 16);
    }
  }

  // 显示AI选项菜单
  void _showAIOptions(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12), // 使用圆角
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          '✨',
                          style: TextStyle(
                            fontSize: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI助手',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: theme.colorScheme.outline),
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: const Text('智能分析来源'),
                    subtitle: const Text('分析文本中可能的作者和作品'),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeSource();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: const Text('润色文本'),
                    subtitle: const Text('优化文本表达，使其更加流畅、优美'),
                    onTap: () {
                      Navigator.pop(context);
                      _polishText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('续写内容'),
                    subtitle: const Text('以相同的风格和语调延伸当前内容'),
                    onTap: () {
                      Navigator.pop(context);
                      _continueText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics),
                    title: const Text('深度分析'),
                    subtitle: const Text('对笔记内容进行深入分析和解读'),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeContent();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 分析来源
  Future<void> _analyzeSource() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在分析来源...'),
              ],
            ),
          );
        },
      );

      // 调用AI分析来源
      final result = await aiService.analyzeSource(plainText);

      // 关闭加载对话框
      Navigator.of(context).pop();

      // 解析JSON结果
      try {
        final Map<String, dynamic> sourceData = json.decode(result);

        String? author = sourceData['author'] as String?;
        String? work = sourceData['work'] as String?;
        String confidence = sourceData['confidence'] as String? ?? '低';
        String explanation = sourceData['explanation'] as String? ?? '';

        // 显示结果对话框
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('分析结果 (可信度: $confidence)'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (author != null && author.isNotEmpty) ...[
                      const Text(
                        '可能的作者:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(author),
                      const SizedBox(height: 8),
                    ],
                    if (work != null && work.isNotEmpty) ...[
                      const Text(
                        '可能的作品:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(work),
                      const SizedBox(height: 8),
                    ],
                    if (explanation.isNotEmpty) ...[
                      const Text(
                        '分析说明:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(explanation, style: const TextStyle(fontSize: 13)),
                    ],
                    if ((author == null || author.isEmpty) &&
                        (work == null || work.isEmpty))
                      const Text('未能识别出明确的作者或作品'),
                  ],
                ),
                actions: [
                  if ((author != null && author.isNotEmpty) ||
                      (work != null && work.isNotEmpty))
                    TextButton(
                      child: const Text('应用分析结果'),
                      onPressed: () {
                        setState(() {
                          if (author != null && author.isNotEmpty) {
                            _authorController.text = author;
                          }
                          if (work != null && work.isNotEmpty) {
                            _workController.text = work;
                          }
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                  TextButton(
                    child: const Text('关闭'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('解析结果失败: $e')));
        }
      }
    } catch (e) {
      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分析失败: $e')));
      }
    }
  }

  // 润色文本
  Future<void> _polishText() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在润色文本...'),
              ],
            ),
          );
        },
      );

      // 调用AI润色文本
      final result = await aiService.polishText(plainText);

      // 关闭加载对话框
      Navigator.of(context).pop();

      // 显示结果对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('润色结果'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(child: SelectableText(result)),
              ),
              actions: [
                TextButton(
                  child: const Text('应用更改'),
                  onPressed: () {
                    setState(() {
                      // 更新编辑器内容
                      _controller.document = quill.Document.fromJson([
                        {"insert": result},
                      ]);
                    });
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('取消'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('润色失败: $e')));
      }
    }
  }

  // 续写文本
  Future<void> _continueText() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在续写内容...'),
              ],
            ),
          );
        },
      );

      // 调用AI续写文本
      final result = await aiService.continueText(plainText);

      // 关闭加载对话框
      Navigator.of(context).pop();

      // 显示结果对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('续写结果'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(child: Text(result)),
              ),
              actions: [
                TextButton(
                  child: const Text('附加到原文'),
                  onPressed: () {
                    // 在文档末尾附加新内容
                    final int length = _controller.document.length;
                    _controller.document.insert(length, '\n\n$result');
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('取消'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('续写失败: $e')));
      }
    }
  }

  // 深度分析内容
  Future<void> _analyzeContent() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在分析内容...'),
              ],
            ),
          );
        },
      );

      // 创建临时Quote对象进行分析
      final quote = Quote(
        id: widget.initialQuote?.id ?? const Uuid().v4(),
        content: plainText,
        date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
        location: _showLocation ? _location : null,
        weather: _showWeather ? _weather : null,
        temperature: _showWeather ? _temperature : null,
      );

      // 调用AI分析
      final analysisResult = await aiService.summarizeNote(quote);

      // 关闭加载对话框
      Navigator.of(context).pop();

      // 显示结果对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('分析结果'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(child: Text(analysisResult)),
              ),
              actions: [
                TextButton(
                  child: const Text('关闭'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分析失败: $e')));
      }
    }
  }
}
