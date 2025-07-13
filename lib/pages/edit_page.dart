import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/icon_utils.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/color_utils.dart';
import '../utils/ai_dialog_helper.dart'; // 导入新的AI助手
import 'note_qa_chat_page.dart'; // 导入问笔记聊天页面

// 添加 note_full_editor_page.dart 的导入
import '../pages/note_full_editor_page.dart';

class EditPage extends StatefulWidget {
  final Quote quote;

  const EditPage({super.key, required this.quote});

  @override
  EditPageState createState() => EditPageState();
}

class EditPageState extends State<EditPage> {
  late TextEditingController _contentController;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  late String _aiAnalysis;
  late List<String> _tagIds;
  late String? _colorHex;
  late AiDialogHelper _aiDialogHelper;

  // 添加位置和天气相关变量
  bool _includeLocation = false;
  bool _includeWeather = false;
  String? _location;
  String? _weather;
  String? _temperature;

  @override
  void initState() {
    super.initState();
    _aiDialogHelper = AiDialogHelper(context);

    // 检查是否需要跳转到全屏编辑器
    // 延迟执行，确保页面完全加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndNavigateToFullscreenEditor();
    });

    _contentController = TextEditingController(text: widget.quote.content);

    // 从source解析出author和work（如果它们为空）
    String author = widget.quote.sourceAuthor ?? '';
    String work = widget.quote.sourceWork ?? '';

    if ((author.isEmpty || work.isEmpty) && widget.quote.source != null) {
      _parseSource(widget.quote.source!);
    }

    _authorController = TextEditingController(text: author);
    _workController = TextEditingController(text: work);
    _aiAnalysis = widget.quote.aiAnalysis ?? '';
    _tagIds = List<String>.from(widget.quote.tagIds);
    _colorHex = widget.quote.colorHex;

    // 初始化位置和天气
    _location = widget.quote.location;
    _weather = widget.quote.weather;
    _temperature = widget.quote.temperature;
    _includeLocation = _location != null && _location!.isNotEmpty;
    _includeWeather = _weather != null && _weather!.isNotEmpty;

    // 如果有位置信息，解析到位置服务
    if (_includeLocation) {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      locationService.parseLocationString(_location);
    }
  }

  void _parseSource(String source) {
    // 尝试解析格式如"——作者《作品》"的字符串
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

    _authorController.text = author;
    _workController.text = work;
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
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    _workController.dispose();
    super.dispose();
  }

  // 获取当前位置和天气
  Future<void> _getCurrentLocationAndWeather() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    if (!locationService.hasLocationPermission) {
      bool permissionGranted =
          await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法获取位置权限')));
        return;
      }
    }

    final position = await locationService.getCurrentLocation();
    if (!mounted) return;
    if (position != null) {
      setState(() {
        _includeLocation = true;
        _location = locationService.getFormattedLocation();
      });

      // 获取天气
      await weatherService.getWeatherData(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _includeWeather = true;
        _weather = weatherService.currentWeather;
        _temperature = weatherService.temperature;
      });
    }
  }

  // AI 相关方法
  void _showAIOptions() {
    _aiDialogHelper.showAiOptions(
      onAnalyzeSource: _analyzeSource,
      onPolishText: _polishText,
      onContinueText: _continueText,
      onAnalyzeContent: _analyzeContent,
      onAskQuestion: _askNoteQuestion, // 添加问笔记功能
    );
  }

  Future<void> _analyzeSource() async {
    await _aiDialogHelper.analyzeSource(
      _contentController,
      _authorController,
      _workController,
    );
    setState(() {});
  }

  Future<void> _polishText() async {
    await _aiDialogHelper.polishText(_contentController);
  }

  Future<void> _continueText() async {
    await _aiDialogHelper.continueText(_contentController);
  }

  Future<void> _analyzeContent() async {
    final quote = Quote(
      id: widget.quote.id,
      content: _contentController.text,
      date: widget.quote.date,
      location: _includeLocation ? _location : null,
      weather: _includeWeather ? _weather : null,
      temperature: _includeWeather ? _temperature : null,
    );
    await _aiDialogHelper.analyzeContent(
      quote,
      onFinish: (analysisResult) {
        setState(() {
          _aiAnalysis = analysisResult;
        });
      },
    );
  }

  // 问笔记功能
  Future<void> _askNoteQuestion() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
      return;
    }

    // 创建临时Quote对象用于问答
    final tempQuote = Quote(
      id: widget.quote.id,
      content: content,
      date: DateTime.now().toIso8601String(),
      sourceAuthor:
          _authorController.text.trim().isEmpty
              ? null
              : _authorController.text.trim(),
      sourceWork:
          _workController.text.trim().isEmpty
              ? null
              : _workController.text.trim(),
      location: _includeLocation ? _location : null,
      weather: _includeWeather ? _weather : null,
      temperature: _includeWeather ? _temperature : null,
    );

    // 导航到聊天页面
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: tempQuote)),
    );
  }

  // 检查是否需要跳转到全屏编辑器
  void _checkAndNavigateToFullscreenEditor() async {
    // 如果Quote被标记为全屏编辑，则自动跳转到全屏编辑器
    if (widget.quote.editSource == 'fullscreen' ||
        widget.quote.deltaContent != null) {
      try {
        // 获取所有标签
        final databaseService = Provider.of<DatabaseService>(
          context,
          listen: false,
        );
        final allTags = await databaseService.getCategories();

        if (mounted) {
          // 创建包含当前编辑状态的更新后的Quote对象
          final updatedQuote = widget.quote.copyWith(
            content: _contentController.text,
            sourceAuthor:
                _authorController.text.trim().isEmpty
                    ? null
                    : _authorController.text.trim(),
            sourceWork:
                _workController.text.trim().isEmpty
                    ? null
                    : _workController.text.trim(),
            tagIds: _tagIds,
            colorHex: _colorHex,
            location: _includeLocation ? _location : null,
            weather: _includeWeather ? _weather : null,
            temperature: _includeWeather ? _temperature : null,
            aiAnalysis: _aiAnalysis,
          );

          // 关闭当前页面并打开全屏编辑器，传递更新后的Quote对象
          Navigator.of(context)
              .pushReplacement(
                MaterialPageRoute(
                  builder:
                      (context) => NoteFullEditorPage(
                        initialContent: _contentController.text,
                        initialQuote: updatedQuote, // 传递包含当前编辑状态的Quote对象
                        allTags: allTags, // 传递所有标签
                      ),
                ),
              )
              .catchError((error) {
                // 如果导航失败，显示错误
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('无法打开全屏编辑器: $error'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return false;
              });
        }
      } catch (e) {
        if (mounted) {
          // 显示错误信息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('准备打开全屏编辑器时出错: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final databaseService = Provider.of<DatabaseService>(context);
    final locationService = Provider.of<LocationService>(context);
    final weatherService = Provider.of<WeatherService>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light 
          ? Colors.white 
          : Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('编辑'),
        actions: [
          // 添加AI功能按钮
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI助手',
            onPressed: _showAIOptions,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              // 保存编辑后的笔记
              final newQuote = Quote(
                id: widget.quote.id,
                content: _contentController.text,
                date: widget.quote.date,
                aiAnalysis: _aiAnalysis,
                source: _formatSource(
                  _authorController.text,
                  _workController.text,
                ),
                sourceAuthor: _authorController.text,
                sourceWork: _workController.text,
                tagIds: _tagIds,
                colorHex: _colorHex,
                location: _includeLocation ? _location : null,
                weather: _includeWeather ? _weather : null,
                temperature: _includeWeather ? _temperature : null,
              );

              await databaseService.updateQuote(newQuote);

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('保存成功！')));
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: '内容',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _authorController,
                      decoration: const InputDecoration(
                        labelText: '作者/人物',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _workController,
                      decoration: const InputDecoration(
                        labelText: '作品名称',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.book),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _authorController,
                builder: (context, authorValue, child) {
                  return ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _workController,
                    builder: (context, workValue, child) {
                      return Text(
                        '将显示为: ${_formatSource(authorValue.text, workValue.text)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurface
                              .applyOpacity(0.6), // Use applyOpacity
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 16),
              // 位置和天气信息
              Row(
                children: [
                  // 位置信息
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _includeLocation = !_includeLocation;
                          if (_includeLocation && _location == null) {
                            _getCurrentLocationAndWeather();
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 4.0,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _includeLocation
                                  ? Icons.location_on
                                  : Icons.location_off,
                              size: 20,
                              color:
                                  _includeLocation
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                        context,
                                      ).colorScheme.onSurface.applyOpacity(
                                        0.5,
                                      ), // Use applyOpacity
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '位置',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          _includeLocation
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                              : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (_includeLocation && _location != null)
                                    Text(
                                      locationService.city ?? '',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface.applyOpacity(
                                          0.6,
                                        ), // Use applyOpacity
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (_includeLocation)
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 16),
                                tooltip: '刷新位置',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  _getCurrentLocationAndWeather();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 天气信息
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _includeWeather = !_includeWeather;
                          if (_includeWeather && _weather == null) {
                            _getCurrentLocationAndWeather();
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 4.0,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _includeWeather
                                  ? weatherService.getWeatherIconData()
                                  : Icons.cloud_off,
                              size: 20,
                              color:
                                  _includeWeather
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                        context,
                                      ).colorScheme.onSurface.applyOpacity(
                                        0.5,
                                      ), // Use applyOpacity
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '天气',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          _includeWeather
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                              : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (_includeWeather && _weather != null)
                                    Text(
                                      '${WeatherService.getWeatherDescription(_weather!)} ${_temperature ?? ""}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface.applyOpacity(
                                          0.6,
                                        ), // Use applyOpacity
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 仅当API已配置时显示AI分析部分
              Builder(
                builder: (context) {
                  final settingsService = Provider.of<SettingsService>(
                    context,
                    listen: false,
                  );
                  final settings = settingsService.aiSettings;
                  final bool apiConfigured =
                      settings.apiKey.isNotEmpty &&
                      settings.apiUrl.isNotEmpty &&
                      settings.model.isNotEmpty;

                  return apiConfigured
                      ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('AI 分析:'),
                          _aiAnalysis.isEmpty
                              ? const Text('暂无分析')
                              : MarkdownBody(
                                data: _aiAnalysis,
                                selectable: true,
                                styleSheet: MarkdownStyleSheet.fromTheme(
                                  Theme.of(context),
                                ).copyWith(
                                  p: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                        ],
                      )
                      : const SizedBox.shrink(); // 如果API未配置，则不显示AI分析部分
                },
              ),

              // 添加标签选择功能
              const SizedBox(height: 16),
              _buildTagSelector(),
            ],
          ),
        ),
      ),
    );
  }

  // 构建标签选择器
  Widget _buildTagSelector() {
    return FutureBuilder<List<NoteCategory>>(
      future:
          Provider.of<DatabaseService>(context, listen: false).getCategories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Text('暂无标签，请先在设置中创建标签');
        }

        final tags = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('标签:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children:
                  tags.map((tag) {
                    final isSelected = _tagIds.contains(tag.id);

                    return FilterChip(
                      selected: isSelected,
                      label: Text(tag.name),
                      avatar: _buildTagIcon(tag),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _tagIds.add(tag.id);
                          } else {
                            _tagIds.remove(tag.id);
                          }
                        });
                      },
                      selectedColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      checkmarkColor: Theme.of(context).colorScheme.primary,
                    );
                  }).toList(),
            ),
          ],
        );
      },
    );
  }

  // 构建标签图标，正确处理emoji
  Widget _buildTagIcon(NoteCategory tag) {
    // 导入IconUtils
    if (IconUtils.isEmoji(tag.iconName)) {
      return Text(
        IconUtils.getDisplayIcon(tag.iconName),
        style: const TextStyle(fontSize: 16),
      );
    } else {
      return Icon(IconUtils.getIconData(tag.iconName), size: 16);
    }
  }
}
