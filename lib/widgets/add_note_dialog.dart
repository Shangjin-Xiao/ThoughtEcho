import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/icon_utils.dart';
import '../theme/app_theme.dart';
import '../pages/note_full_editor_page.dart';
import 'package:flex_color_picker/flex_color_picker.dart';

class AddNoteDialog extends StatefulWidget {
  final Quote? initialQuote; // 如果是编辑笔记，则传入初始值
  final String? prefilledContent; // 预填充的内容
  final String? prefilledAuthor; // 预填充的作者
  final String? prefilledWork; // 预填充的作品
  final Map<String, dynamic>? hitokotoData; // 添加一言API返回的完整数据
  final List<NoteCategory> tags;
  final Function(Quote)? onSave; // 保存后的回调

  const AddNoteDialog({
    super.key,
    this.initialQuote,
    this.prefilledContent,
    this.prefilledAuthor,
    this.prefilledWork,
    this.hitokotoData,
    required this.tags,
    this.onSave,
  });

  @override
  State<AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<AddNoteDialog> {
  late TextEditingController _contentController;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  final List<String> _selectedTagIds = [];
  String? _aiSummary;
  bool _isAnalyzing = false;

  // 位置和天气相关
  bool _includeLocation = false;
  bool _includeWeather = false;

  // 颜色选择
  String? _selectedColorHex;
  final List<Color> _colorOptions = [
    Colors.red.shade100,
    Colors.orange.shade100,
    Colors.yellow.shade100,
    Colors.green.shade100,
    Colors.blue.shade100,
    Colors.purple.shade100,
    Colors.pink.shade100,
  ];

  // 缓存标签future，防止FutureBuilder多次请求导致闪屏
  Future<List<NoteCategory>>? _tagFuture;

  @override
  void initState() {
    super.initState();

    // 初始化控制器
    _contentController = TextEditingController(
      text: widget.initialQuote?.content ?? widget.prefilledContent ?? '',
    );

    _authorController = TextEditingController(
      text: widget.initialQuote?.sourceAuthor ?? widget.prefilledAuthor ?? '',
    );

    _workController = TextEditingController(
      text: widget.initialQuote?.sourceWork ?? widget.prefilledWork ?? '',
    );

    // 如果是编辑已有笔记
    if (widget.initialQuote != null) {
      _aiSummary = widget.initialQuote!.aiAnalysis;
      _selectedColorHex = widget.initialQuote!.colorHex;

      // 添加标签
      if (widget.initialQuote!.tagIds.isNotEmpty) {
        _selectedTagIds.addAll(widget.initialQuote!.tagIds);
      }

      // 如果源字段存在但分离的作者/作品字段为空，尝试解析
      if ((widget.initialQuote!.sourceAuthor == null ||
              widget.initialQuote!.sourceAuthor!.isEmpty) &&
          (widget.initialQuote!.sourceWork == null ||
              widget.initialQuote!.sourceWork!.isEmpty) &&
          widget.initialQuote!.source != null &&
          widget.initialQuote!.source!.isNotEmpty) {
        _parseSource(
          widget.initialQuote!.source!,
          _authorController,
          _workController,
        );
      }
    }
    // 只有hitokotoData不为空时，才自动添加每日一言标签
    else if (widget.hitokotoData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addDefaultHitokotoTags();
      });
    }

    // 初始化标签future
    _tagFuture =
        Provider.of<DatabaseService>(context, listen: false).getCategories();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    _workController.dispose();
    super.dispose();
  }

  // 添加默认的一言相关标签
  void _addDefaultHitokotoTags() async {
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);

      // 添加"每日一言"标签
      String? dailyQuoteTagId = await _ensureTagExists(
        db,
        '每日一言',
        'format_quote',
      );
      if (dailyQuoteTagId != null &&
          !_selectedTagIds.contains(dailyQuoteTagId)) {
        setState(() {
          _selectedTagIds.add(dailyQuoteTagId);
        });
      }

      // 添加一言类型对应的标签
      if (widget.hitokotoData != null) {
        // 获取一言类型
        String? hitokotoType = _getHitokotoTypeFromApiResponse();
        if (hitokotoType != null && hitokotoType.isNotEmpty) {
          // 将类型代码转换为可读标签名称
          String tagName = _convertHitokotoTypeToTagName(hitokotoType);
          String iconName = _getIconForHitokotoType(hitokotoType);

          // 确保类型标签存在并添加到选中标签中
          String? typeTagId = await _ensureTagExists(db, tagName, iconName);
          if (typeTagId != null && !_selectedTagIds.contains(typeTagId)) {
            setState(() {
              _selectedTagIds.add(typeTagId);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('添加默认标签失败: $e');
    }
  }

  // 从hitokotoData中获取一言类型
  String? _getHitokotoTypeFromApiResponse() {
    // 一言API的类型字段是'type'
    if (widget.hitokotoData != null &&
        widget.hitokotoData!.containsKey('type')) {
      return widget.hitokotoData!['type'].toString();
    }
    return null;
  }

  // 将一言API的类型代码转换为可读标签名称
  String _convertHitokotoTypeToTagName(String typeCode) {
    // 一言API的类型映射
    const Map<String, String> typeMap = {
      'a': '动画',
      'b': '漫画',
      'c': '游戏',
      'd': '文学',
      'e': '原创',
      'f': '来自网络',
      'g': '其他',
      'h': '影视',
      'i': '诗词',
      'j': '网易云',
      'k': '哲学',
      'l': '抖机灵',
    };

    return typeMap[typeCode] ?? '其他一言';
  }

  // 为不同类型的一言选择对应的图标
  String _getIconForHitokotoType(String typeCode) {
    const Map<String, String> iconMap = {
      'a': 'movie',
      'b': 'menu_book',
      'c': 'sports_esports',
      'd': 'auto_stories',
      'e': 'create',
      'f': 'public',
      'g': 'category',
      'h': 'theaters',
      'i': 'article',
      'j': 'music_note',
      'k': 'psychology',
      'l': 'mood',
    };

    return iconMap[typeCode] ?? 'format_quote';
  }

  // 确保标签存在，如果不存在则创建
  Future<String?> _ensureTagExists(
    DatabaseService db,
    String name,
    String iconName,
  ) async {
    try {
      // 查找标签
      final categories = await db.getCategories();
      final existingTag = categories.firstWhere(
        (tag) => tag.name == name,
        orElse: () => NoteCategory(id: '', name: ''),
      );

      // 如果标签已存在，返回其ID
      if (existingTag.id.isNotEmpty) {
        return existingTag.id;
      }

      // 创建标签
      await db.addCategory(name, iconName: iconName);

      // 获取新创建的标签
      final updatedCategories = await db.getCategories();
      final newTag = updatedCategories.firstWhere(
        (tag) => tag.name == name,
        orElse: () => NoteCategory(id: '', name: ''),
      );

      return newTag.id.isNotEmpty ? newTag.id : null;
    } catch (e) {
      debugPrint('确保标签"$name"存在时出错: $e');
      return null;
    }
  }

  // 解析格式如"——作者《作品》"的字符串
  void _parseSource(
    String source,
    TextEditingController authorController,
    TextEditingController workController,
  ) {
    String author = '';
    String work = '';

    // 提取作者（在"——"之后，"《"之前）
    final authorMatch = RegExp(r'——([^《]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }

    // 提取作品（在《》之间）
    final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }

    authorController.text = author;
    workController.text = work;
  }

  // 格式化来源
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
    final db = Provider.of<DatabaseService>(context);
    final aiService = Provider.of<AIService>(context);
    final locationService = Provider.of<LocationService>(context);
    final weatherService = Provider.of<WeatherService>(context);

    // 位置和天气信息
    String? location = locationService.getFormattedLocation();
    String? weather = weatherService.currentWeather;
    String? temperature = weatherService.temperature;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: IntrinsicHeight(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              // 内容输入区，带全屏编辑按钮
              const SizedBox(height: 16),
              Stack(
                children: [
                  TextField(
                    controller: _contentController,
                    decoration: InputDecoration(
                      hintText: '写下你的感悟...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.edit),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ).copyWith(right: 48),
                    ),
                    maxLines: 3,
                    autofocus: true,
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Builder(
                      builder: (context) {
                        final isLongContent =
                            _contentController.text.length > 100;
                        return IconButton(
                          tooltip: '全屏编辑',
                          icon: Icon(
                            Icons.fullscreen,
                            color:
                                isLongContent
                                    ? theme.colorScheme.primary
                                    : theme.iconTheme.color,
                          ),
                          onPressed: () async {
                            // 首先关闭当前编辑框
                            Navigator.pop(context);

                            // 然后打开全屏编辑器
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => NoteFullEditorPage(
                                      initialContent: _contentController.text,
                                      initialQuote: widget.initialQuote,
                                      allTags: widget.tags,
                                    ),
                              ),
                            );

                            // 如果返回了结果，我们不需要处理，因为已经在全屏编辑器中保存了
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 拆分来源输入为作者和作品
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _authorController,
                      decoration: const InputDecoration(
                        hintText: '作者/人物',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      maxLines: 1,
                      onChanged: (value) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _workController,
                      decoration: const InputDecoration(
                        hintText: '作品名称',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.book),
                      ),
                      maxLines: 1,
                      onChanged: (value) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 显示格式化后的来源预览
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '将显示为: ${_formatSource(_authorController.text, _workController.text)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),

              // 位置和天气选项
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Text(
                    '添加信息',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  // 位置信息按钮
                  Tooltip(
                    message:
                        '添加位置: ${locationService.currentAddress ?? location}',
                    child: FilterChip(
                      avatar: Icon(
                        Icons.location_on,
                        color:
                            _includeLocation
                                ? theme.colorScheme.primary
                                : Colors.grey,
                        size: 18,
                      ),
                      label: const Text('位置'),
                      selected: _includeLocation,
                      onSelected: (value) {
                        setState(() {
                          _includeLocation = value;
                        });
                      },
                      selectedColor: theme.colorScheme.primaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 天气信息按钮
                  Tooltip(
                    message:
                        weather != null
                            ? '添加天气: ${weatherService.getFormattedWeather()}'
                            : '添加天气信息',
                    child: FilterChip(
                      avatar: Icon(
                        weather != null
                            ? weatherService.getWeatherIconData()
                            : Icons.cloud,
                        color:
                            _includeWeather
                                ? theme.colorScheme.primary
                                : Colors.grey,
                        size: 18,
                      ),
                      label: const Text('天气'),
                      selected: _includeWeather,
                      onSelected: (value) {
                        setState(() {
                          _includeWeather = value;
                        });
                      },
                      selectedColor: theme.colorScheme.primaryContainer,
                    ),
                  ),
                ],
              ),

              // 颜色选择区域
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '卡片颜色',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      // 默认选项（无颜色）
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedColorHex = null;
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color:
                                  _selectedColorHex == null
                                      ? theme.colorScheme.primary
                                      : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child:
                              _selectedColorHex == null
                                  ? Center(
                                    child: Icon(
                                      Icons.check,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                  : null,
                        ),
                      ),
                      ..._colorOptions.map((color) {
                        final colorHex =
                            '#${color.value.toRadixString(16).substring(2)}';
                        final isSelected = _selectedColorHex == colorHex;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedColorHex = colorHex;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(
                                color:
                                    isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.grey.shade300,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child:
                                isSelected
                                    ? Center(
                                      child: Icon(
                                        Icons.check,
                                        size: 18,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                    : null,
                          ),
                        );
                      }),
                      // 自定义颜色（如果有且不在预设内）
                      if (_selectedColorHex != null &&
                          !_colorOptions
                              .map(
                                (c) =>
                                    '#${c.value.toRadixString(16).substring(2)}',
                              )
                              .contains(_selectedColorHex))
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              // 保持当前自定义颜色选中
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(
                                      _selectedColorHex!.substring(1),
                                      radix: 16,
                                    ) |
                                    0xFF000000,
                              ),
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.check,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
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
                                    pickersEnabled: <ColorPickerType, bool>{
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
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: Colors.grey.shade400,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.palette,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // 标签选择区域
              const SizedBox(height: 16),
              FutureBuilder<List<NoteCategory>>(
                future: _tagFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('加载标签失败: \\${snapshot.error}'));
                  }
                  final tags = snapshot.data ?? [];
                  return ExpansionTile(
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
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: tags.length,
                          itemBuilder: (context, index) {
                            final tag = tags[index];
                            final isSelected = _selectedTagIds.contains(tag.id);
                            return CheckboxListTile(
                              title: Row(
                                children: [
                                  if (IconUtils.isEmoji(tag.iconName))
                                    Text(
                                      IconUtils.getDisplayIcon(tag.iconName),
                                      style: const TextStyle(fontSize: 20),
                                    )
                                  else
                                    Icon(IconUtils.getIconData(tag.iconName)),
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
                              controlAffinity: ListTileControlAffinity.trailing,
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
                  );
                },
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
                                final tag = widget.tags.firstWhere(
                                  (t) => t.id == tagId,
                                  orElse:
                                      () =>
                                          NoteCategory(id: tagId, name: '未知标签'),
                                );
                                return Chip(
                                  label:
                                      IconUtils.isEmoji(tag.iconName)
                                          ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                IconUtils.getDisplayIcon(
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
                                      !IconUtils.isEmoji(tag.iconName)
                                          ? Icon(
                                            IconUtils.getIconData(tag.iconName),
                                            size: 14,
                                          )
                                          : null,
                                  deleteIcon: const Icon(Icons.close, size: 14),
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

              // AI分析结果
              if (_aiSummary != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI分析',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_aiSummary!),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // AI分析按钮
                  Builder(
                    builder: (context) {
                      // 检查API是否已配置
                      final settingsService = Provider.of<SettingsService>(
                        context,
                        listen: false,
                      );
                      final settings = settingsService.aiSettings;
                      final bool apiConfigured =
                          settings.apiKey.isNotEmpty &&
                          settings.apiUrl.isNotEmpty &&
                          settings.model.isNotEmpty;

                      if (_contentController.text.isNotEmpty &&
                          _aiSummary == null &&
                          apiConfigured) {
                        return FilledButton.icon(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.buttonRadius,
                              ),
                            ),
                          ),
                          onPressed:
                              _isAnalyzing
                                  ? null
                                  : () async {
                                    setState(() => _isAnalyzing = true);
                                    try {
                                      final summary = await aiService
                                          .summarizeNote(
                                            Quote(
                                              id: widget.initialQuote?.id ?? '',
                                              content: _contentController.text,
                                              date:
                                                  widget.initialQuote?.date ??
                                                  DateTime.now()
                                                      .toIso8601String(),
                                            ),
                                          );
                                      if (mounted) {
                                        setState(() {
                                          _aiSummary = summary;
                                          _isAnalyzing = false;
                                        });
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('AI分析失败: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                        setState(() => _isAnalyzing = false);
                                      }
                                    }
                                  },
                          icon:
                              _isAnalyzing
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.auto_awesome),
                          label: Text(_isAnalyzing ? '分析中...' : 'AI分析'),
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.buttonRadius,
                        ),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.buttonRadius,
                        ),
                      ),
                    ),
                    onPressed: () async {
                      if (_contentController.text.isNotEmpty) {
                        // 创建或更新笔记
                        final Quote quote = Quote(
                          id: widget.initialQuote?.id ?? const Uuid().v4(),
                          content: _contentController.text,
                          date:
                              widget.initialQuote?.date ??
                              DateTime.now().toIso8601String(),
                          aiAnalysis: _aiSummary,
                          source: _formatSource(
                            _authorController.text,
                            _workController.text,
                          ),
                          sourceAuthor: _authorController.text,
                          sourceWork: _workController.text,
                          tagIds: _selectedTagIds,
                          sentiment: widget.initialQuote?.sentiment,
                          keywords: widget.initialQuote?.keywords,
                          summary: widget.initialQuote?.summary,
                          categoryId: widget.initialQuote?.categoryId,
                          colorHex: _selectedColorHex,
                          location: _includeLocation ? location : null,
                          weather: _includeWeather ? weather : null,
                          temperature: _includeWeather ? temperature : null,
                        );

                        try {
                          if (widget.initialQuote != null) {
                            // 更新已有笔记
                            await db.updateQuote(quote);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('笔记已更新')),
                            );
                          } else {
                            // 添加新笔记
                            await db.addQuote(quote);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('笔记已保存')),
                            );
                          }

                          // 调用保存回调
                          if (widget.onSave != null) {
                            widget.onSave!(quote);
                          }

                          // 关闭对话框
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('保存失败: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                    child: Text(widget.initialQuote != null ? '更新' : '保存'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // 显示对话框的静态方法
  static Future<void> show({
    required BuildContext context,
    Quote? initialQuote,
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    Map<String, dynamic>? hitokotoData,
    required List<NoteCategory> tags,
    Function(Quote)? onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => AddNoteDialog(
            initialQuote: initialQuote,
            prefilledContent: prefilledContent,
            prefilledAuthor: prefilledAuthor,
            prefilledWork: prefilledWork,
            hitokotoData: hitokotoData,
            tags: tags,
            onSave: onSave,
          ),
    );
  }
}

class FullScreenNoteEditor extends StatefulWidget {
  final String initialText;
  const FullScreenNoteEditor({super.key, required this.initialText});

  @override
  State<FullScreenNoteEditor> createState() => _FullScreenNoteEditorState();
}

class _FullScreenNoteEditorState extends State<FullScreenNoteEditor> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('全屏编辑'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存并返回',
            onPressed: () {
              Navigator.pop(context, controller.text);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '请输入内容...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
          ),
        ),
      ),
    );
  }
}
