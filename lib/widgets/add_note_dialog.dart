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

class AddNoteDialog extends StatefulWidget {
  final Quote? initialQuote; // 如果是编辑笔记，则传入初始值
  final String? prefilledContent; // 预填充的内容
  final String? prefilledAuthor; // 预填充的作者
  final String? prefilledWork; // 预填充的作品
  final List<NoteCategory> tags;
  final Function(Quote)? onSave; // 保存后的回调
  
  const AddNoteDialog({
    Key? key,
    this.initialQuote,
    this.prefilledContent,
    this.prefilledAuthor,
    this.prefilledWork,
    required this.tags,
    this.onSave,
  }) : super(key: key);
  
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
  
  @override
  void initState() {
    super.initState();
    
    // 初始化控制器
    _contentController = TextEditingController(
      text: widget.initialQuote?.content ?? widget.prefilledContent ?? ''
    );
    
    _authorController = TextEditingController(
      text: widget.initialQuote?.sourceAuthor ?? widget.prefilledAuthor ?? ''
    );
    
    _workController = TextEditingController(
      text: widget.initialQuote?.sourceWork ?? widget.prefilledWork ?? ''
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
      if ((widget.initialQuote!.sourceAuthor == null || widget.initialQuote!.sourceAuthor!.isEmpty) && 
          (widget.initialQuote!.sourceWork == null || widget.initialQuote!.sourceWork!.isEmpty) && 
          widget.initialQuote!.source != null && 
          widget.initialQuote!.source!.isNotEmpty) {
        _parseSource(widget.initialQuote!.source!, _authorController, _workController);
      }
    } 
    // 如果是从一言添加，添加相关标签
    else if (widget.prefilledContent != null && widget.prefilledAuthor != null) {
      // 这里会在显示对话框后添加相关标签
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addDefaultHitokotoTags();
      });
    }
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
      String? dailyQuoteTagId = await _ensureTagExists(db, '每日一言', 'format_quote');
      if (dailyQuoteTagId != null && !_selectedTagIds.contains(dailyQuoteTagId)) {
        setState(() {
          _selectedTagIds.add(dailyQuoteTagId);
        });
      }
    } catch (e) {
      debugPrint('添加默认标签失败: $e');
    }
  }
  
  // 确保标签存在，如果不存在则创建
  Future<String?> _ensureTagExists(DatabaseService db, String name, String iconName) async {
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
  void _parseSource(String source, TextEditingController authorController, TextEditingController workController) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: '写下你的感悟...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
              maxLines: 3,
              autofocus: true,
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
                // 位置信息按钮
                Tooltip(
                  message: '添加位置: ${locationService.currentAddress ?? location}',
                  child: FilterChip(
                    avatar: Icon(
                      Icons.location_on,
                      color: _includeLocation ? theme.colorScheme.primary : Colors.grey,
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
                  message: weather != null 
                      ? '添加天气: ${weatherService.getFormattedWeather()}' 
                      : '添加天气信息',
                  child: FilterChip(
                    avatar: Icon(
                      weather != null ? weatherService.getWeatherIconData() : Icons.cloud,
                      color: _includeWeather ? theme.colorScheme.primary : Colors.grey,
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
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
                            color: _selectedColorHex == null 
                                ? theme.colorScheme.primary 
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _selectedColorHex == null
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
                      final colorHex = '#${color.value.toRadixString(16).substring(2)}';
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
                              color: isSelected 
                                  ? theme.colorScheme.primary 
                                  : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: isSelected
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
                    }).toList(),
                  ],
                ),
              ],
            ),
            
            // 标签选择区域
            const SizedBox(height: 16),
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
              childrenPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              children: [
                // 搜索框
                TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索标签...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
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
                    itemCount: widget.tags.length,
                    itemBuilder: (context, index) {
                      final tag = widget.tags[index];
                      final isSelected = _selectedTagIds.contains(tag.id);
                      return CheckboxListTile(
                        title: Row(
                          children: [
                            if (IconUtils.isEmoji(tag.iconName))
                              Text(
                                IconUtils.getDisplayIcon(tag.iconName),
                                style: const TextStyle(fontSize: 20),
                              ),
                            const SizedBox(width: 8),
                            Text(tag.name),
                          ],
                        ),
                        secondary: IconUtils.isEmoji(tag.iconName)
                            ? null
                            : Icon(IconUtils.getIconData(tag.iconName)),
                        value: isSelected,
                        dense: true,
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
                    color: theme.colorScheme.surfaceVariant,
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
                        children: _selectedTagIds.map((tagId) {
                          final tag = widget.tags.firstWhere(
                            (t) => t.id == tagId,
                            orElse: () => NoteCategory(id: tagId, name: '未知标签'),
                          );
                          return Chip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (IconUtils.isEmoji(tag.iconName))
                                  Text(
                                    IconUtils.getDisplayIcon(tag.iconName),
                                    style: const TextStyle(fontSize: 14, color: Colors.black),
                                  ),
                                const SizedBox(width: 4),
                                Text(tag.name, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            avatar: null,
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
                    final settingsService = Provider.of<SettingsService>(context, listen: false);
                    final settings = settingsService.aiSettings;
                    final bool apiConfigured = settings.apiKey.isNotEmpty &&
                                            settings.apiUrl.isNotEmpty &&
                                            settings.model.isNotEmpty;
                    
                    if (_contentController.text.isNotEmpty && _aiSummary == null && apiConfigured) {
                      return TextButton.icon(
                        onPressed: _isAnalyzing
                            ? null
                            : () async {
                                setState(() => _isAnalyzing = true);
                                try {
                                  final summary = await aiService.summarizeNote(
                                    Quote(
                                      id: widget.initialQuote?.id ?? '',
                                      content: _contentController.text,
                                      date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
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
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('AI分析失败: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    setState(() => _isAnalyzing = false);
                                  }
                                }
                              },
                        icon: _isAnalyzing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(_isAnalyzing ? '分析中...' : 'AI分析'),
                      );
                    }
                    
                    return const SizedBox.shrink();
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_contentController.text.isNotEmpty) {
                      // 创建或更新笔记
                      final Quote quote = Quote(
                        id: widget.initialQuote?.id ?? const Uuid().v4(),
                        content: _contentController.text,
                        date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
                        aiAnalysis: _aiSummary,
                        source: _formatSource(_authorController.text, _workController.text),
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
    );
  }
  
  // 显示对话框的静态方法
  static Future<void> show({
    required BuildContext context,
    Quote? initialQuote,
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    required List<NoteCategory> tags,
    Function(Quote)? onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddNoteDialog(
        initialQuote: initialQuote,
        prefilledContent: prefilledContent,
        prefilledAuthor: prefilledAuthor,
        prefilledWork: prefilledWork,
        tags: tags,
        onSave: onSave,
      ),
    );
  }
}