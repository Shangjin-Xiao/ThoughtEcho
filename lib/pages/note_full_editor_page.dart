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
import 'package:flex_color_picker/flex_color_picker.dart';

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
  List<String> _selectedTagIds = [];
  String? _selectedColorHex;
  String? _location;
  String? _weather;
  String? _temperature;
  bool _showMeta = true;
  bool _showLocationWeather = false; // 新增状态变量控制是否显示位置天气

  // 预设颜色hex，与普通添加笔记页面一致
  final List<String> _presetColorHexes = [
    '#fff1f0', // red.shade100
    '#fff7e6', // orange.shade100
    '#ffffe0', // yellow.shade100
    '#f6ffed', // green.shade100
    '#e6f7ff', // blue.shade100
    '#f9f0ff', // purple.shade100
    '#fff0f6', // pink.shade100
  ];

  @override
  void initState() {
    super.initState();
    // 尝试将initialContent作为Delta解析，否则作为纯文本插入
    try {
      final document = quill.Document.fromJson(
        jsonDecode(widget.initialContent),
      );
      _controller = quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      _controller = quill.QuillController(
        document: quill.Document()..insert(0, widget.initialContent),
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
    // 作者/作品
    _authorController = TextEditingController(
      text: widget.initialQuote?.sourceAuthor ?? '',
    );
    _workController = TextEditingController(
      text: widget.initialQuote?.sourceWork ?? '',
    );
    // 标签
    _selectedTagIds = widget.initialQuote?.tagIds ?? [];
    // 颜色
    _selectedColorHex = widget.initialQuote?.colorHex;
    // 位置/天气
    _location = widget.initialQuote?.location;
    _weather = widget.initialQuote?.weather;
    _temperature = widget.initialQuote?.temperature;

    // 如果已有位置和天气数据，则显示位置天气区域
    if (_location != null || _weather != null) {
      _showLocationWeather = true;
    }
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

    // 明确区分编辑和新增模式
    final isEditing = widget.initialQuote != null;

    // 构建笔记对象
    final quote = Quote(
      id: isEditing ? widget.initialQuote!.id : const Uuid().v4(), // 保持原ID
      content: plainTextContent, // 使用纯文本内容而不是Delta JSON
      date: isEditing ? widget.initialQuote!.date : now, // 保持原创建日期
      source: _formatSource(_authorController.text, _workController.text),
      sourceAuthor: _authorController.text,
      sourceWork: _workController.text,
      tagIds: _selectedTagIds,
      colorHex: _selectedColorHex,
      location: _showLocationWeather ? _location : null,
      weather: _showLocationWeather ? _weather : null,
      temperature: _showLocationWeather ? _temperature : null,
      // 保留原有AI分析和其他元数据
      aiAnalysis: widget.initialQuote?.aiAnalysis,
      sentiment: widget.initialQuote?.sentiment,
      keywords: widget.initialQuote?.keywords,
      summary: widget.initialQuote?.summary,
      categoryId: widget.initialQuote?.categoryId,
    );

    try {
      if (isEditing) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allTags = widget.allTags ?? [];
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 优化后的元数据区域布局
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
                    const SizedBox(height: 8),

                    // 标签选择区域
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children:
                            allTags.map((tag) {
                              final selected = _selectedTagIds.contains(tag.id);
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text(tag.name),
                                  selected: selected,
                                  labelStyle: const TextStyle(fontSize: 12),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onSelected: (v) {
                                    setState(() {
                                      if (v) {
                                        _selectedTagIds.add(tag.id);
                                      } else {
                                        _selectedTagIds.remove(tag.id);
                                      }
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 颜色选择与位置天气切换
                    Row(
                      children: [
                        const Text('颜色：', style: TextStyle(fontSize: 13)),
                        ...[
                          null, // 无色
                          Colors.red.shade100,
                          Colors.orange.shade100,
                          Colors.yellow.shade100,
                          Colors.green.shade100,
                          Colors.blue.shade100,
                          Colors.purple.shade100,
                          Colors.pink.shade100,
                        ].map((color) {
                          final colorHex =
                              color == null
                                  ? null
                                  : '#${color.value.toRadixString(16).substring(2)}';
                          final isSelected =
                              _selectedColorHex == colorHex ||
                              (color == null && _selectedColorHex == null);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColorHex = colorHex;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: color ?? Colors.white,
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.grey.shade300,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child:
                                  isSelected
                                      ? Center(
                                        child: Icon(
                                          Icons.check,
                                          size: 14,
                                          color: theme.colorScheme.primary,
                                        ),
                                      )
                                      : null,
                            ),
                          );
                        }).toList(),

                        // 调色盘按钮
                        GestureDetector(
                          onTap: () async {
                            final color = await showDialog<Color>(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: const Text('选择自定义颜色'),
                                    content: ColorPicker(
                                      color:
                                          _selectedColorHex != null
                                              ? Color(
                                                int.parse(
                                                      _selectedColorHex!
                                                          .substring(1),
                                                      radix: 16,
                                                    ) |
                                                    0xFF000000,
                                              )
                                              : Colors.blue,
                                      onColorChanged: (color) {
                                        Navigator.of(context).pop(color);
                                      },
                                      pickersEnabled:
                                          const <ColorPickerType, bool>{
                                            ColorPickerType.both: false,
                                            ColorPickerType.primary: true,
                                            ColorPickerType.accent: false,
                                          },
                                      width: 24,
                                      height: 24,
                                      borderRadius: 12,
                                      spacing: 4,
                                      runSpacing: 4,
                                      showColorCode: false,
                                      showRecentColors: false,
                                    ),
                                  ),
                            );
                            if (color != null) {
                              setState(() {
                                _selectedColorHex =
                                    '#${color.value.toRadixString(16).substring(2)}';
                              });
                            }
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: Colors.grey.shade400,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.palette,
                              size: 14,
                              color: Colors.grey,
                            ),
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
                                _showLocationWeather
                                    ? theme.colorScheme.primary
                                    : Colors.grey,
                            size: 18,
                          ),
                          label: const Text('位置'),
                          selected: _showLocationWeather && _location != null,
                          onSelected: (value) {
                            setState(() {
                              _showLocationWeather = value;
                              // 如果开启了位置天气但还没有数据，则自动获取
                              if (_showLocationWeather && _location == null) {
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
                                _showLocationWeather && _weather != null
                                    ? theme.colorScheme.primary
                                    : Colors.grey,
                            size: 18,
                          ),
                          label: const Text('天气'),
                          selected: _showLocationWeather && _weather != null,
                          onSelected: (value) {
                            setState(() {
                              _showLocationWeather = value;
                              // 如果开启了位置天气但还没有数据，则自动获取
                              if (_showLocationWeather && _weather == null) {
                                _fetchLocationWeather();
                              }
                            });
                          },
                          selectedColor: theme.colorScheme.primaryContainer,
                          visualDensity: VisualDensity.compact,
                        ),

                        // 如果有位置或天气信息，显示刷新按钮
                        if (_showLocationWeather &&
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
                    if (_showLocationWeather &&
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

  IconData _getWeatherIcon(String weather) {
    switch (weather) {
      case '晴':
        return Icons.wb_sunny;
      case '阴':
      case '多云':
        return Icons.wb_cloudy;
      case '雨':
        return Icons.grain;
      case '雪':
        return Icons.ac_unit;
      default:
        return Icons.cloud;
    }
  }
}
