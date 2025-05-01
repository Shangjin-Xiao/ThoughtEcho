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
import '../utils/time_utils.dart'; // 导入时间工具类
import 'package:flex_color_picker/flex_color_picker.dart';
import '../utils/icon_utils.dart';

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
  bool _showMeta = true;
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
    final String currentDayPeriod = TimeUtils.getCurrentDayPeriod();

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
      dayPeriod: widget.initialQuote?.dayPeriod ?? currentDayPeriod,
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
    final Color initialColor = _selectedColorHex != null
        ? Color(int.parse(_selectedColorHex!.substring(1), radix: 16) | 0xFF000000)
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
      builder: (context) => AlertDialog(
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
                      children: presetColors.map((color) {
                        String? colorHex;
                        if (color != Colors.transparent) {
                          colorHex = '#${color.value.toRadixString(16).substring(2)}';
                        }
                        
                        final bool isSelected = color == Colors.transparent 
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
                                color: isSelected
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
                              child: isSelected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: color == Colors.transparent || color.computeLuminance() > 0.7
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
                    builder: (context) => AlertDialog(
                      title: const Text('自定义颜色'),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          color: initialColor != Colors.transparent 
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
                          onPressed: () => Navigator.of(context).pop(initialColor),
                          child: const Text('选择'),
                        ),
                      ],
                    ),
                  );
                  
                  if (advancedColor != null && mounted) {
                    setState(() {
                      _selectedColorHex = advancedColor == Colors.transparent
                          ? null
                          : '#${advancedColor.value.toRadixString(16).substring(2)}';
                    });
                  }
                },
              )
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    
    if (result != null) {
      setState(() {
        _selectedColorHex = result == Colors.transparent
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
          IconButton(
            icon: Icon(_showMeta ? Icons.expand_less : Icons.expand_more),
            tooltip: _showMeta ? '收起元数据' : '展开元数据',
            onPressed: () => setState(() => _showMeta = !_showMeta),
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
            if (_showMeta)
              // 可滚动的元数据区域，防止标签过多时溢出
              SizedBox(
                height: 240,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 12),

                      // 使用ExpansionTile替代标签选择，使之与普通添加笔记页面相似
                      ExpansionTile(
                        title: const Text(
                          '选择标签',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        leading: const Icon(Icons.tag),
                        initiallyExpanded: false,
                        childrenPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
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
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: SingleChildScrollView(
                              child: Wrap(
                                spacing: 8.0,
                                runSpacing: 8.0,
                                children: widget.allTags!
                                    .map((tag) {
                                  final selected = _selectedTagIds.contains(tag.id);
                                  return FilterChip(
                                    selected: selected,
                                    label: Text(tag.name),
                                    avatar: _isEmoji(tag.iconName)
                                        ? Text(
                                            _getDisplayIcon(tag.iconName),
                                            style: const TextStyle(fontSize: 16),
                                          )
                                        : Icon(_getIconData(tag.iconName), size: 16),
                                    onSelected: (bool value) {
                                      setState(() {
                                        if (value) {
                                          _selectedTagIds.add(tag.id);
                                        } else {
                                          _selectedTagIds.remove(tag.id);
                                        }
                                      });
                                    },
                                    selectedColor: theme.colorScheme.primaryContainer,
                                    checkmarkColor: theme.colorScheme.primary,
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // 显示已选标签
                      _selectedTagIds.isEmpty
                          ? const SizedBox.shrink()
                          : Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '已选标签',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 4.0,
                                  children: _selectedTagIds.map((tagId) {
                                    final tag = widget.allTags!.firstWhere(
                                      (t) => t.id == tagId,
                                      orElse: () => NoteCategory(
                                        id: tagId,
                                        name: '未知标签',
                                      ),
                                    );
                                    return Chip(
                                      label: Text(tag.name),
                                      avatar: _isEmoji(tag.iconName)
                                          ? Text(
                                              _getDisplayIcon(tag.iconName),
                                              style: const TextStyle(fontSize: 16),
                                            )
                                          : Icon(_getIconData(tag.iconName), size: 16),
                                      onDeleted: () {
                                        setState(() {
                                          _selectedTagIds.remove(tagId);
                                        });
                                      },
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),

                      const SizedBox(height: 12),

                      // 颜色选择器 - 改进UI
                      ExpansionTile(
                        title: const Text(
                          '颜色选择',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        leading: const Icon(Icons.palette),
                        initiallyExpanded: false,
                        childrenPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 当前选择显示
                                Row(
                                  children: [
                                    Text(
                                      '当前选择:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: _selectedColorHex != null
                                            ? Color(
                                                int.parse(_selectedColorHex!.substring(1), radix: 16) |
                                                    0xFF000000,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: _selectedColorHex == null
                                              ? theme.colorScheme.outline
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: _selectedColorHex == null
                                          ? Icon(
                                              Icons.block,
                                              size: 16,
                                              color: theme.colorScheme.outline,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _selectedColorHex == null ? '无' : '自定义',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 16),
                                
                                // 预设颜色选项
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.palette),
                                  label: const Text('选择卡片颜色'),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                                  ),
                                  onPressed: () => _showCustomColorPicker(context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 使用与短文本编辑框一致的天气和位置UI
                      Row(
                        children: [
                          const Text('添加信息：', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 8),
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
                            selected: _showLocation && _location != null,
                            onSelected: (value) {
                              setState(() {
                                _showLocation = value;
                                // 如果开启了位置天气但还没有数据，则自动获取
                                if (_showLocation && _location == null) {
                                  _fetchLocationWeather();
                                }
                              });
                            },
                            selectedColor: theme.colorScheme.primaryContainer,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          // 天气信息按钮
                          FilterChip(
                            avatar: Icon(
                              _weather != null
                                  ? _getWeatherIcon(_weather!)
                                  : Icons.cloud,
                              color:
                                  _showWeather && _weather != null
                                      ? theme.colorScheme.primary
                                      : Colors.grey,
                              size: 18,
                            ),
                            label: const Text('天气'),
                            selected: _showWeather && _weather != null,
                            onSelected: (value) {
                              setState(() {
                                _showWeather = value;
                                // 如果开启了位置天气但还没有数据，则自动获取
                                if (_showWeather && _weather == null) {
                                  _fetchLocationWeather();
                                }
                              });
                            },
                            selectedColor: theme.colorScheme.primaryContainer,
                            visualDensity: VisualDensity.compact,
                          ),

                          // 如果有位置或天气信息，显示刷新按钮
                          if (_showLocation &&
                              (_location != null || _weather != null))
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 16),
                              tooltip: '刷新天气/位置',
                              onPressed: _fetchLocationWeather,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                            ),
                        ],
                      ),

                      // 如果启用了位置天气，显示当前信息
                      if (_showLocation &&
                          (_location != null || _weather != null))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              if (_weather != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_getWeatherIcon(_weather!), size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      _weather!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    if (_temperature != null)
                                      Text(
                                        ' $_temperature',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                              if (_weather != null && _location != null)
                                const SizedBox(width: 12),
                              if (_location != null)
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on, size: 16),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          _location!,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            quill.QuillSimpleToolbar(controller: _controller),
            Expanded(
              child: Container(
                color: theme.colorScheme.surface,
                child: quill.QuillEditor.basic(
                  controller: _controller,
                  config: const quill.QuillEditorConfig(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
