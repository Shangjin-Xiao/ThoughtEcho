import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/ai_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/icon_utils.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/color_utils.dart'; // Import color_utils.dart

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

  // 添加位置和天气相关变量
  bool _includeLocation = false;
  bool _includeWeather = false;
  String? _location;
  String? _weather;
  String? _temperature;

  @override
  void initState() {
    super.initState();

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

  // 显示AI选项菜单
  void _showAIOptions(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.dialogRadius),
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
                        Icon(
                          Icons.auto_awesome,
                          color: theme.colorScheme.primary,
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
    if (_contentController.text.isEmpty) {
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
        builder: (dialogContext) {
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
      ); // 调用AI分析来源
      final result = await aiService.analyzeSource(_contentController.text);

      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

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
            builder: (dialogContext) {
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
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                  TextButton(
                    child: const Text('关闭'),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
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
    if (_contentController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入内容')));
      return;
    }

    // 在异步操作前获取必要的context相关对象
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
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
      final result = await aiService.polishText(_contentController.text);
      if (!mounted) return;
      if (!context.mounted) return;
      navigator.pop();
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) {
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
                    _contentController.text = result;
                  });
                  Navigator.of(dialogContext).pop();
                },
              ),
              TextButton(
                child: const Text('取消'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      navigator.pop();

      scaffoldMessenger.showSnackBar(SnackBar(content: Text('润色失败: $e')));
    }
  }

  // 续写文本
  Future<void> _continueText() async {
    if (_contentController.text.isEmpty) {
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
        builder: (dialogContext) {
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
      final result = await aiService.continueText(_contentController.text);
      if (!mounted) return;
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('续写结果'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: MarkdownBody(data: result, selectable: true),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('附加到原文'),
                  onPressed: () {
                    setState(() {
                      _contentController.text =
                          '${_contentController.text}\n\n$result';
                    });
                    Navigator.of(dialogContext).pop();
                  },
                ),
                TextButton(
                  child: const Text('取消'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // 确保组件仍然挂载
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('续写失败: $e')));
      }
    }
  }

  // 深入分析内容
  Future<void> _analyzeContent() async {
    if (_contentController.text.isEmpty) {
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
        builder: (dialogContext) {
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

      // 调用AI分析
      final quote = Quote(
        id: widget.quote.id,
        content: _contentController.text,
        date: widget.quote.date,
        location: _includeLocation ? _location : null,
        weather: _includeWeather ? _weather : null,
        temperature: _includeWeather ? _temperature : null,
      );

      final result = await aiService.summarizeNote(quote);

      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop();

      setState(() {
        _aiAnalysis = result;
      });

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分析完成')));
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
          // 关闭当前页面并打开全屏编辑器
          Navigator.of(context)
              .pushReplacement(
                MaterialPageRoute(
                  builder:
                      (context) => NoteFullEditorPage(
                        initialContent: widget.quote.content,
                        initialQuote: widget.quote,
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
      appBar: AppBar(
        title: const Text('编辑'),
        actions: [
          // 添加AI功能按钮
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI助手',
            onPressed: () {
              _showAIOptions(context);
            },
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
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.buttonRadius,
                                    ),
                                  ),
                                ),
                                onPressed: () async {
                                  try {
                                    final aiService = Provider.of<AIService>(
                                      context,
                                      listen: false,
                                    );
                                    final summary = await aiService
                                        .summarizeNote(
                                          Quote(
                                            id: widget.quote.id,
                                            content: _contentController.text,
                                            date: widget.quote.date,
                                          ),
                                        );
                                    setState(() {
                                      _aiAnalysis = summary;
                                    });
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('AI分析失败: $e')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.auto_awesome, size: 18),
                                label: const Text('AI'),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.analytics),
                                tooltip: '分析内容',
                                onPressed: _analyzeContent,
                              ),
                              PopupMenuButton<String>(
                                onSelected: (String value) {
                                  switch (value) {
                                    case 'polish':
                                      _polishText();
                                      break;
                                    case 'continue':
                                      _continueText();
                                      break;
                                    case 'source':
                                      _analyzeSource();
                                      break;
                                  }
                                },
                                itemBuilder:
                                    (
                                      BuildContext context,
                                    ) => <PopupMenuEntry<String>>[
                                      const PopupMenuItem<String>(
                                        value: 'polish',
                                        child: Row(
                                          children: [
                                            Icon(Icons.brush, size: 20),
                                            SizedBox(width: 8),
                                            Text('润色文本'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'continue',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.add_circle_outline,
                                              size: 20,
                                            ),
                                            SizedBox(width: 8),
                                            Text('续写内容'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'source',
                                        child: Row(
                                          children: [
                                            Icon(Icons.text_fields, size: 20),
                                            SizedBox(width: 8),
                                            Text('分析来源'),
                                          ],
                                        ),
                                      ),
                                    ],
                              ),
                            ],
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
