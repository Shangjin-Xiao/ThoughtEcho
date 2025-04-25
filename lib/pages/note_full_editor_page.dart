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
  const NoteFullEditorPage({super.key, required this.initialContent, this.initialQuote, this.allTags});

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

  @override
  void initState() {
    super.initState();
    // 尝试将initialContent作为Delta解析，否则作为纯文本插入
    try {
      final document = quill.Document.fromJson(jsonDecode(widget.initialContent));
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
    _authorController = TextEditingController(text: widget.initialQuote?.sourceAuthor ?? '');
    _workController = TextEditingController(text: widget.initialQuote?.sourceWork ?? '');
    // 标签
    _selectedTagIds = widget.initialQuote?.tagIds ?? [];
    // 颜色
    _selectedColorHex = widget.initialQuote?.colorHex;
    // 位置/天气
    _location = widget.initialQuote?.location;
    _weather = widget.initialQuote?.weather;
    _temperature = widget.initialQuote?.temperature;
    // 自动获取天气和位置（可选）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLocationWeather();
    });
  }

  Future<void> _fetchLocationWeather() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    // 检查并请求权限
    if (!locationService.hasLocationPermission) {
      bool permissionGranted = await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法获取位置权限')),
          );
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
      await weatherService.getWeatherData(position.latitude, position.longitude);
      setState(() {
        _weather = weatherService.currentWeather;
        _temperature = weatherService.temperature;
      });
    }
  }

  Future<void> _saveContent() async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    final deltaJson = jsonEncode(_controller.document.toDelta().toJson());
    final now = DateTime.now().toIso8601String();
    final Quote quote = Quote(
      id: widget.initialQuote?.id ?? const Uuid().v4(),
      content: deltaJson,
      date: widget.initialQuote?.date ?? now,
      source: _authorController.text.isNotEmpty || _workController.text.isNotEmpty
          ? '${_authorController.text}——${_workController.text}'
          : null,
      sourceAuthor: _authorController.text,
      sourceWork: _workController.text,
      tagIds: _selectedTagIds,
      colorHex: _selectedColorHex,
      location: _location,
      weather: _weather,
      temperature: _temperature,
      aiAnalysis: widget.initialQuote?.aiAnalysis,
      sentiment: widget.initialQuote?.sentiment,
      keywords: widget.initialQuote?.keywords,
      summary: widget.initialQuote?.summary,
      categoryId: widget.initialQuote?.categoryId,
    );
    try {
      if (widget.initialQuote != null) {
        await db.updateQuote(quote);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('笔记已更新')),
          );
        }
      } else {
        await db.addQuote(quote);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('笔记已保存')),
          );
        }
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标签选择
                    Wrap(
                      spacing: 8,
                      children: allTags.map((tag) {
                        final selected = _selectedTagIds.contains(tag.id);
                        return FilterChip(
                          label: Text(tag.name),
                          selected: selected,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selectedTagIds.add(tag.id);
                              } else {
                                _selectedTagIds.remove(tag.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    // 作者/作品
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _authorController,
                            decoration: const InputDecoration(
                              hintText: '作者/人物',
                              border: OutlineInputBorder(),
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
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 天气/位置
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_weather != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.wb_cloudy, size: 18),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _weather!,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_temperature != null) 
                                  Flexible(
                                    child: Text(
                                      ' $_temperature',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          if (_location != null) ...[
                            const SizedBox(width: 12),
                            const Icon(Icons.location_on, size: 18),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _location!,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            tooltip: '刷新天气/位置',
                            onPressed: _fetchLocationWeather,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 颜色选择
                    Row(
                      children: [
                        const Text('颜色：'),
                        ColorPicker(
                          color: _selectedColorHex != null
                              ? Color(int.parse(_selectedColorHex!.substring(1), radix: 16) | 0xFF000000)
                              : Colors.transparent,
                          onColorChanged: (color) {
                            setState(() {
                              _selectedColorHex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                            });
                          },
                          pickersEnabled: const <ColorPickerType, bool>{
                            ColorPickerType.both: false,
                            ColorPickerType.primary: true,
                            ColorPickerType.accent: false,
                          },
                          width: 28,
                          height: 28,
                          borderRadius: 14,
                          spacing: 4,
                          runSpacing: 4,
                          showColorCode: false,
                          showRecentColors: false,
                        ),
                      ],
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
}