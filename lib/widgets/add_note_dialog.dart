import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/icon_utils.dart';
import '../utils/time_utils.dart'; // 导入时间工具类
import '../theme/app_theme.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // 导入 markdown 库
import '../utils/color_utils.dart'; // Import color_utils
import 'add_note_ai_menu.dart'; // 导入 AI 菜单组件
import '../pages/note_full_editor_page.dart'; // 导入全屏富文本编辑器
import 'package:thoughtecho/utils/app_logger.dart';
import '../constants/app_constants.dart';

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

  // 分类选择
  NoteCategory? _selectedCategory;

  // 位置和天气相关
  bool _includeLocation = false;
  bool _includeWeather = false;

  // 保存原始笔记的位置和天气信息（用于编辑模式）
  String? _originalLocation;
  String? _originalWeather;
  String? _originalTemperature;
  // 颜色选择
  String? _selectedColorHex;

  // 标签搜索控制器
  final TextEditingController _tagSearchController = TextEditingController();

  // 性能优化：缓存Provider引用，避免重复查找
  LocationService? _cachedLocationService;
  WeatherService? _cachedWeatherService;

  // 搜索防抖和过滤缓存
  Timer? _searchDebounceTimer;
  List<NoteCategory> _filteredTags = [];
  String _lastSearchQuery = '';

  // 优化：缓存过滤结果，避免重复计算
  final Map<String, List<NoteCategory>> _filterCache = {};

  // 一言类型到固定分类 ID 的映射
  static final Map<String, String> _hitokotoTypeToCategoryIdMap = {
    'a': DatabaseService.defaultCategoryIdAnime, // 动画
    'b': DatabaseService.defaultCategoryIdComic, // 漫画
    'c': DatabaseService.defaultCategoryIdGame, // 游戏
    'd': DatabaseService.defaultCategoryIdNovel, // 文学
    'e': DatabaseService.defaultCategoryIdOriginal, // 原创
    'f': DatabaseService.defaultCategoryIdInternet, // 来自网络
    'g': DatabaseService.defaultCategoryIdOther, // 其他
    'h': DatabaseService.defaultCategoryIdMovie, // 影视
    'i': DatabaseService.defaultCategoryIdPoem, // 诗词
    'j': DatabaseService.defaultCategoryIdMusic, // 网易云
    'k': DatabaseService.defaultCategoryIdPhilosophy, // 哲学
    'l': DatabaseService.defaultCategoryIdJoke, // 抖机灵
  };

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

    // 初始化过滤结果
    _filteredTags = widget.tags;
    _lastSearchQuery = '';

    // 延迟初始化服务缓存，避免在构建过程中查找Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _cachedLocationService =
            Provider.of<LocationService>(context, listen: false);
        _cachedWeatherService =
            Provider.of<WeatherService>(context, listen: false);
      }
    });

    // 添加搜索防抖监听器
    _tagSearchController.addListener(_onSearchChanged);

    // 如果是编辑已有笔记
    if (widget.initialQuote != null) {
      _aiSummary = widget.initialQuote!.aiAnalysis;
      _selectedColorHex = widget.initialQuote!.colorHex;

      // 保存原始的位置和天气信息
      _originalLocation = widget.initialQuote!.location;
      _originalWeather = widget.initialQuote!.weather;
      _originalTemperature = widget.initialQuote!.temperature;

      // 根据现有笔记的位置和天气信息设置复选框状态
      _includeLocation = widget.initialQuote!.location != null;
      _includeWeather = widget.initialQuote!.weather != null;

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

    // 延迟执行重量级操作，避免阻塞UI构建
    if (widget.hitokotoData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addDefaultHitokotoTags();
      });
    }
  }

  // 搜索变化处理 - 使用防抖优化
  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      final query = _tagSearchController.text.toLowerCase();
      if (query != _lastSearchQuery) {
        _lastSearchQuery = query;
        _updateFilteredTags(query);
      }
    });
  }

  // 更新过滤标签 - 使用缓存优化
  void _updateFilteredTags(String query) {
    if (!mounted) return;

    setState(() {
      if (query.isEmpty) {
        _filteredTags = widget.tags;
      } else {
        // 优化：使用缓存避免重复计算
        if (_filterCache.containsKey(query)) {
          _filteredTags = _filterCache[query]!;
        } else {
          _filteredTags = widget.tags.where((tag) {
            return tag.name.toLowerCase().contains(query);
          }).toList();

          // 缓存结果，限制缓存大小防止内存泄漏
          if (_filterCache.length < 50) {
            _filterCache[query] = _filteredTags;
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _contentController.dispose();
    _authorController.dispose();
    _workController.dispose();
    _tagSearchController.dispose();
    super.dispose();
  }

  // 添加默认的一言相关标签（异步执行，不阻塞UI）
  Future<void> _addDefaultHitokotoTags() async {
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);

      // 添加"每日一言"标签
      String? dailyQuoteTagId = await _ensureTagExists(
        db,
        '每日一言',
        '💭',
      );
      if (dailyQuoteTagId != null &&
          !_selectedTagIds.contains(dailyQuoteTagId)) {
        if (mounted) {
          setState(() {
            _selectedTagIds.add(dailyQuoteTagId);
          });
        }
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
            if (mounted) {
              setState(() {
                _selectedTagIds.add(typeTagId);
              });
            }
          }

          // 设置分类
          if (_hitokotoTypeToCategoryIdMap.containsKey(hitokotoType)) {
            final categoryId = _hitokotoTypeToCategoryIdMap[hitokotoType];
            final category = await db.getCategoryById(categoryId!);
            if (mounted) {
              setState(() {
                _selectedCategory = category;
              });
            }
          }
        }
      }
    } catch (e) {
      logDebug('添加默认标签失败: $e');
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
      'a': '🎬', // 动画
      'b': '📚', // 漫画
      'c': '🎮', // 游戏
      'd': '📖', // 文学
      'e': '✨', // 原创
      'f': '🌐', // 来自网络
      'g': '📝', // 其他
      'h': '🎭', // 影视
      'i': '🌸', // 诗词
      'j': '🎵', // 网易云
      'k': '🤔', // 哲学
      'l': '😄', // 抖机灵
    };

    return iconMap[typeCode] ?? '💭';
  }

  // 确保标签存在，如果不存在则创建
  Future<String?> _ensureTagExists(
    DatabaseService db,
    String name,
    String iconName,
  ) async {
    try {
      // 首先，检查是否有固定ID映射
      String? fixedId;
      for (var entry in _hitokotoTypeToCategoryIdMap.entries) {
        if (_convertHitokotoTypeToTagName(entry.key) == name) {
          fixedId = entry.value;
          break;
        }
      }

      // 如果是"每日一言"标签的特殊情况
      if (name == '每日一言') {
        fixedId = DatabaseService.defaultCategoryIdHitokoto;
      }

      // 无论标签是否被重命名，优先通过固定ID查找
      // 这样可以确保即使标签被重命名，仍然能正确关联
      if (fixedId != null) {
        final category = await db.getCategoryById(fixedId);
        if (category != null) {
          logDebug('通过固定ID找到标签: ${category.name}(ID=${category.id})');
          return category.id; // 返回已存在的固定ID标签，即使它已被重命名
        }
      }

      // 如果固定ID没有找到对应标签，再通过名称查找
      final categories = await db.getCategories();
      final existingTag = categories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteCategory(id: '', name: ''),
      );

      // 如果标签已存在，返回其ID
      if (existingTag.id.isNotEmpty) {
        return existingTag.id;
      }

      // 如果有固定ID但未创建，使用固定ID创建
      if (fixedId != null) {
        try {
          // 使用固定ID创建标签
          await db.addCategoryWithId(fixedId, name, iconName: iconName);
          return fixedId;
        } catch (e) {
          logDebug('使用固定ID创建标签失败: $e');
          // 如果固定ID创建失败，尝试常规创建
          await db.addCategory(name, iconName: iconName);
        }
      } else {
        // 创建新标签
        await db.addCategory(name, iconName: iconName);
      }

      // 获取新创建的标签
      final updatedCategories = await db.getCategories();
      final newTag = updatedCategories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteCategory(id: '', name: ''),
      );

      return newTag.id.isNotEmpty ? newTag.id : null;
    } catch (e) {
      logDebug('确保标签"$name"存在时出错: $e');
      // 尝试获取现有标签作为回退方案
      try {
        final allCategories = await db.getCategories();
        // 尝试通过名称匹配
        final matchingTag = allCategories.firstWhere(
          (tag) => tag.name.toLowerCase() == name.toLowerCase(),
          orElse: () => NoteCategory(id: '', name: ''),
        );
        if (matchingTag.id.isNotEmpty) {
          logDebug('虽然发生错误，但找到了匹配的标签: ${matchingTag.id}');
          return matchingTag.id;
        }
        // 如果没有匹配标签，返回任何可用标签的ID或null
        return allCategories.isNotEmpty ? allCategories.first.id : null;
      } catch (_) {
        return null;
      }
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

    // 优化：使用缓存的服务或延迟获取
    final locationService = _cachedLocationService ??
        Provider.of<LocationService>(context, listen: false);
    final weatherService = _cachedWeatherService ??
        Provider.of<WeatherService>(context, listen: false);

    // 位置和天气信息 - 只在需要时获取
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
            // 内容输入区，带全屏编辑按钮
            const SizedBox(height: 16),
            Stack(
              children: [
                TextField(
                  controller: _contentController,
                  decoration: const InputDecoration(
                    hintText: '写下你的感悟...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.edit),
                    contentPadding: EdgeInsets.fromLTRB(16, 16, 48, 16),
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
                      return Stack(
                        children: [
                          // 如果是长文本，添加一个提示小红点
                          if (isLongContent)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: isLongContent ? '建议全屏编辑长文本' : '全屏编辑',
                            icon: Icon(
                              Icons.fullscreen,
                              color: theme.colorScheme.primary,
                            ),
                            onPressed: () async {
                              if (!context.mounted) return;
                              try {
                                // 获取所有标签数据
                                final databaseService =
                                    Provider.of<DatabaseService>(
                                  context,
                                  listen: false,
                                );
                                final allTags =
                                    await databaseService.getCategories();

                                // 修复内存泄露：在异步操作后检查mounted状态
                                if (!mounted) return;
                                if (!context.mounted) return;

                                // 创建包含当前元数据的临时Quote对象，确保全屏编辑器能继承所有元数据
                                final locationService =
                                    Provider.of<LocationService>(
                                  context,
                                  listen: false,
                                );
                                final weatherService =
                                    Provider.of<WeatherService>(
                                  context,
                                  listen: false,
                                );

                                // 获取位置和天气信息
                                String? currentLocation;
                                String? currentWeather;
                                String? currentTemperature;

                                if (_includeLocation) {
                                  currentLocation = _originalLocation ??
                                      locationService.getFormattedLocation();
                                }

                                if (_includeWeather) {
                                  currentWeather = _originalWeather ??
                                      weatherService.currentWeather;
                                  currentTemperature = _originalTemperature ??
                                      weatherService.temperature;
                                }

                                // 创建包含当前所有元数据的临时Quote对象
                                final tempQuote = Quote(
                                  id: widget
                                      .initialQuote?.id, // 保持原有ID（如果是编辑模式）
                                  content: _contentController.text,
                                  date: widget.initialQuote?.date ??
                                      DateTime.now().toIso8601String(),
                                  sourceAuthor:
                                      _authorController.text.trim().isEmpty
                                          ? null
                                          : _authorController.text.trim(),
                                  sourceWork:
                                      _workController.text.trim().isEmpty
                                          ? null
                                          : _workController.text.trim(),
                                  tagIds: _selectedTagIds,
                                  colorHex: _selectedColorHex,
                                  location: currentLocation,
                                  weather: currentWeather,
                                  temperature: currentTemperature,
                                  aiAnalysis: widget.initialQuote?.aiAnalysis,
                                  sentiment: widget.initialQuote?.sentiment,
                                  keywords: widget.initialQuote?.keywords,
                                  summary: widget.initialQuote?.summary,
                                  categoryId: widget.initialQuote?.categoryId,
                                  editSource: widget.initialQuote?.editSource,
                                  deltaContent:
                                      widget.initialQuote?.deltaContent,
                                  dayPeriod: widget.initialQuote?.dayPeriod,
                                );

                                if (!context.mounted) return;
                                final navigator = Navigator.of(context);
                                final result = await navigator.push(
                                  MaterialPageRoute(
                                    builder: (context) => NoteFullEditorPage(
                                      initialContent: _contentController.text,
                                      initialQuote:
                                          tempQuote, // 传递包含当前元数据的临时Quote对象
                                      allTags: allTags,
                                    ),
                                  ),
                                );

                                if (!mounted) return;

                                if (result != null && result == true) {
                                  // 如果笔记已在全屏编辑器中保存，关闭本对话框
                                  if (mounted && context.mounted) {
                                    Navigator.pop(context);
                                  }
                                }
                              } catch (e) {
                                // 修复内存泄露：检查mounted状态
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('打开全屏编辑器失败: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
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
            const SizedBox(width: 8),
            // 显示格式化后的来源预览
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '将显示为: ${_formatSource(_authorController.text, _workController.text)}',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.applyOpacity(
                    0.6,
                  ), // MODIFIED
                ),
              ),
            ),

            // 位置和天气选项
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
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
                      color: _includeLocation
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
                  message: weather != null
                      ? '添加天气: ${weatherService.getFormattedWeather()}'
                      : '添加天气信息',
                  child: FilterChip(
                    avatar: Icon(
                      weather != null
                          ? weatherService.getWeatherIconData()
                          : Icons.cloud,
                      color: _includeWeather
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
                const SizedBox(width: 8),
                // 颜色选择按钮
                Tooltip(
                  message: _selectedColorHex != null ? '已设置卡片颜色' : '设置卡片颜色',
                  child: FilterChip(
                    avatar: _selectedColorHex != null
                        ? Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(
                                      _selectedColorHex!.substring(1),
                                      radix: 16,
                                    ) |
                                    0xFF000000,
                              ),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: Colors.white,
                                width: 1,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.color_lens,
                            size: 18,
                            color: Colors.grey,
                          ),
                    label: const Text('颜色'),
                    selected: _selectedColorHex != null,
                    onSelected: (value) {
                      if (value) {
                        _showCustomColorPicker(context);
                      } else {
                        setState(() {
                          _selectedColorHex = null;
                        });
                      }
                    },
                    selectedColor: theme.colorScheme.primaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ), // 标签选择区域
            const SizedBox(height: 16),
            _buildTagSelectionSection(widget.tags),

            // 显示已选标签
            _buildSelectedTags(theme),

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
                    MarkdownBody(
                      data: _aiSummary!,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        theme,
                      ).copyWith(p: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // AI助手按钮
                AddNoteAIMenu(
                  contentController: _contentController,
                  authorController: _authorController,
                  workController: _workController,
                  onAiAnalysisCompleted: (result) {
                    setState(() {
                      _aiSummary = result;
                    });
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
                      // 获取当前时间段
                      final String currentDayPeriodKey =
                          TimeUtils.getCurrentDayPeriodKey(); // 使用 Key

                      // 创建或更新笔记
                      final Quote quote = Quote(
                        id: widget.initialQuote?.id ?? const Uuid().v4(),
                        content: _contentController.text,
                        date: widget.initialQuote?.date ??
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
                        categoryId: _selectedCategory?.id ??
                            widget.initialQuote?.categoryId,
                        colorHex: _selectedColorHex,
                        location: _includeLocation
                            ? (widget.initialQuote != null
                                ? _originalLocation
                                : location)
                            : null,
                        weather: _includeWeather
                            ? (widget.initialQuote != null
                                ? _originalWeather
                                : weather)
                            : null,
                        temperature: _includeWeather
                            ? (widget.initialQuote != null
                                ? _originalTemperature
                                : temperature)
                            : null,
                        dayPeriod: widget.initialQuote?.dayPeriod ??
                            currentDayPeriodKey, // 保存 Key
                        editSource: widget.initialQuote?.editSource, // 保证兼容
                        deltaContent: widget.initialQuote?.deltaContent, // 保证兼容
                      );

                      try {
                        final db = Provider.of<DatabaseService>(
                          context,
                          listen: false,
                        );

                        if (widget.initialQuote != null) {
                          // 更新已有笔记
                          await db.updateQuote(quote);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('笔记已更新'),
                              duration: AppConstants.snackBarDurationImportant,
                            ),
                          );
                        } else {
                          // 添加新笔记
                          await db.addQuote(quote);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('笔记已保存'),
                              duration: AppConstants.snackBarDurationImportant,
                            ),
                          );
                        }

                        // 调用保存回调
                        if (widget.onSave != null) {
                          widget.onSave!(quote);
                        }

                        // 关闭对话框
                        if (this.context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('保存失败: $e'),
                              duration: AppConstants.snackBarDurationError,
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

  // 自定义颜色选择器
  Future<void> _showCustomColorPicker(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Color initialColor = _selectedColorHex != null
        ? Color(
            int.parse(_selectedColorHex!.substring(1), radix: 16) | 0xFF000000,
          )
        : Colors.transparent;

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

      const Color(0xFFEF9A9A), // 红色
      const Color(0xFFFFCC80), // 橙色
      const Color(0xFFFFF59D), // 黄色
      const Color(0xFFA5D6A7), // 绿色
      const Color(0xFF90CAF9), // 蓝色
      const Color(0xFFCE93D8), // 紫色
      const Color(0xFFF48FB1), // 粉色

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
                          colorHex =
                              '#${color.toARGB32().toRadixString(16).substring(2)}';
                        }

                        final bool isSelected = color == Colors.transparent
                            ? _selectedColorHex == null
                            : _selectedColorHex == colorHex;

                        return GestureDetector(
                          onTap: () {
                            if (!mounted) return;
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
                                        ? Colors.grey.applyOpacity(
                                            0.5,
                                          ) // MODIFIED
                                        : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.applyOpacity(
                                    0.05,
                                  ), // MODIFIED
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
                                      color: color == Colors.transparent ||
                                              color.computeLuminance() > 0.7
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
                  Color selectedColor = initialColor;
                  final Color? advancedColor = await showDialog<Color>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('自定义颜色'),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          color: initialColor != Colors.transparent
                              ? initialColor
                              : const Color(0xFFE1F5FE), // 默认蓝色
                          onColorChanged: (color) {
                            selectedColor = color;
                          },
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
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(selectedColor),
                          child: const Text('选择'),
                        ),
                      ],
                    ),
                  );

                  if (advancedColor != null && mounted) {
                    setState(() {
                      _selectedColorHex = advancedColor == Colors.transparent
                          ? null
                          : '#${advancedColor.toARGB32().toRadixString(16).substring(2)}'; // MODIFIED
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
        _selectedColorHex = result == Colors.transparent
            ? null
            : '#${result.toARGB32().toRadixString(16).substring(2)}'; // MODIFIED
      });
    }
  }

  // 优化的标签选择区域
  Widget _buildTagSelectionSection(List<NoteCategory> tags) {
    if (tags.isEmpty) {
      return const Center(child: Text('暂无可用标签，请先添加标签'));
    }

    return ExpansionTile(
      title: Text(
        '选择标签 (${_selectedTagIds.length})',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      leading: const Icon(Icons.tag),
      initiallyExpanded: false, // 默认收起，减少初始渲染负担
      childrenPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      children: [
        // 搜索框
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
          // 移除onChanged，现在使用监听器和防抖
        ),
        const SizedBox(height: 8),
        // 标签列表 - 使用缓存的过滤结果
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: _filteredTags.isEmpty
              ? const Center(
                  child: Text('没有找到匹配的标签'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredTags.length,
                  itemBuilder: (context, index) {
                    final tag = _filteredTags[index];
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
  } // 渲染已选标签的Widget，直接使用传入的标签数据

  Widget _buildSelectedTags(ThemeData theme) {
    if (_selectedTagIds.isEmpty) {
      return const SizedBox.shrink();
    }

    // 直接使用widget.tags，避免异步查询
    final tags = widget.tags;

    return Container(
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
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4.0,
            runSpacing: 4.0,
            children: _selectedTagIds.map((tagId) {
              // 从最新的标签列表中查找
              final tag = tags.firstWhere(
                (t) => t.id == tagId,
                orElse: () => NoteCategory(id: tagId, name: '未知标签'),
              );
              return Chip(
                label: IconUtils.isEmoji(tag.iconName)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            IconUtils.getDisplayIcon(tag.iconName),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tag.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      )
                    : Text(tag.name),
                avatar: !IconUtils.isEmoji(tag.iconName)
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
    );
  }
}
