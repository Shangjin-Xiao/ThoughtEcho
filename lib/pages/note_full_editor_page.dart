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
  late TextEditingController _tagSearchController; // 新增标签搜索控制器
  String _tagSearchQuery = ''; // 新增标签搜索查询
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
    // 初始化控制器
    _tagSearchController = TextEditingController(); // 初始化标签搜索控制器

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

  // 天气图标映射方法
  IconData _getWeatherIcon(String weather) {
    final weatherLower = weather.toLowerCase();

    if (weatherLower.contains('晴') &&
        !weatherLower.contains('云') &&
        !weatherLower.contains('阴')) {
      return Icons.wb_sunny;
    } else if (weatherLower.contains('多云') || weatherLower.contains('晴间多云')) {
      return Icons.wb_cloudy; 
    } else if (weatherLower.contains('阴')) {
      return Icons.cloud;
    } else if (weatherLower.contains('雨') && weatherLower.contains('雪')) {
      return Icons.snowing;
    } else if (weatherLower.contains('雨') && weatherLower.contains('雷')) {
      return Icons.thunderstorm;
    } else if (weatherLower.contains('雨')) {
      if (weatherLower.contains('小')) {
        return Icons.grain;
      } else if (weatherLower.contains('中') || weatherLower.contains('大')) {
        return Icons.water_drop;
      } else {
        return Icons.beach_access;
      }
    } else if (weatherLower.contains('雪')) {
      return Icons.ac_unit;
    } else if (weatherLower.contains('雾') || weatherLower.contains('霾')) {
      return Icons.foggy;
    } else if (weatherLower.contains('沙') || weatherLower.contains('尘')) {
      return Icons.air;
    }

    // 默认图标
    return Icons.wb_cloudy;
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
      editSource: 'fullscreen', // 标记为全屏编辑器保存的笔记
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
                    const SizedBox(height: 12),

                    // 改进的标签选择区域 - 使用ExpansionTile与短文本编辑器保持一致
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
                        // 添加标签搜索框
                        TextField(
                          controller: _tagSearchController,
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
                            setState(() {
                              _tagSearchQuery = value.toLowerCase();
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        // 标签列表
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: allTags.length,
                            itemBuilder: (context, index) {
                              final tag = allTags[index];

                              // 如果有搜索查询，过滤不匹配的标签
                              if (_tagSearchQuery.isNotEmpty &&
                                  !tag.name.toLowerCase().contains(
                                    _tagSearchQuery,
                                  )) {
                                return const SizedBox.shrink();
                              }

                              final isSelected = _selectedTagIds.contains(
                                tag.id,
                              );
                              return CheckboxListTile(
                                title: Row(
                                  children: [
                                    if (_isEmoji(tag.iconName))
                                      Text(
                                        _getDisplayIcon(tag.iconName),
                                        style: const TextStyle(fontSize: 20),
                                      )
                                    else
                                      Icon(_getIconData(tag.iconName)),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        tag.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                value: isSelected,
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedTagIds.add(tag.id);
                                    } else {
                                      _selectedTagIds.remove(tag.id);
                                    }
                                  });
                                },
                              );
                            },
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
                                spacing: 4.0,
                                runSpacing: 4.0,
                                children:
                                    _selectedTagIds.map((tagId) {
                                      final tag = allTags.firstWhere(
                                        (t) => t.id == tagId,
                                        orElse:
                                            () => NoteCategory(
                                              id: tagId,
                                              name: '未知标签',
                                            ),
                                      );
                                      return Chip(
                                        label:
                                            _isEmoji(tag.iconName)
                                                ? Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      _getDisplayIcon(
                                                        tag.iconName,
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      tag.name,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                                : Text(tag.name),
                                        avatar:
                                            !_isEmoji(tag.iconName)
                                                ? Icon(
                                                  _getIconData(tag.iconName),
                                                  size: 14,
                                                )
                                                : null,
                                        deleteIcon: const Icon(
                                          Icons.close,
                                          size: 14,
                                        ),
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

                    const SizedBox(height: 12),

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

  // 辅助方法：判断图标是否为表情符号
  bool _isEmoji(String? iconName) {
    if (iconName == null || iconName.isEmpty) return false;
    return !iconName.startsWith('icon:');
  }

  // 辅助方法：获取显示图标
  String _getDisplayIcon(String? iconName) {
    if (iconName == null || iconName.isEmpty) return '📝';
    if (_isEmoji(iconName)) return iconName;
    return '📝';
  }

  // 辅助方法：获取图标数据
  IconData _getIconData(String? iconName) {
    if (iconName == null || iconName.isEmpty) return Icons.label;

    // 如果图标以 "icon:" 开头，解析后面的内容
    if (iconName.startsWith('icon:')) {
      final iconCode = iconName.substring(5);
      switch (iconCode) {
        case 'bookmark':
          return Icons.bookmark;
        case 'favorite':
          return Icons.favorite;
        case 'star':
          return Icons.star;
        case 'label':
          return Icons.label;
        case 'lightbulb':
          return Icons.lightbulb;
        case 'psychology':
          return Icons.psychology;
        case 'auto_stories':
          return Icons.auto_stories;
        case 'menu_book':
          return Icons.menu_book;
        case 'format_quote':
          return Icons.format_quote;
        case 'campaign':
          return Icons.campaign;
        case 'article':
          return Icons.article;
        case 'brush':
          return Icons.brush;
        case 'category':
          return Icons.category;
        case 'create':
          return Icons.create;
        case 'music_note':
          return Icons.music_note;
        case 'movie':
          return Icons.movie;
        case 'public':
          return Icons.public;
        case 'sports_esports':
          return Icons.sports_esports;
        case 'theaters':
          return Icons.theaters;
        default:
          return Icons.label;
      }
    }

    return Icons.label;
  }
}
