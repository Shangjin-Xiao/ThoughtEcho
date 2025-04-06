import 'package:flutter/material.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/tag_model.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:provider/provider.dart';

class EditPage extends StatefulWidget {
  final Quote quote;

  const EditPage({Key? key, required this.quote}) : super(key: key);

  @override
  _EditPageState createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late TextEditingController _contentController;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  late String _aiAnalysis;
  late List<String> _tagIds;
  late String? _colorHex;
  List<Tag> _allTags = [];

  // 位置和天气相关变量
  bool _includeLocation = false;
  bool _includeWeather = false;
  String? _location;
  String? _weather;
  String? _temperature;

  // 预定义的颜色选项
  final List<Color> _colorOptions = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.quote.content);

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

    _location = widget.quote.location;
    _weather = widget.quote.weather;
    _temperature = widget.quote.temperature;
    _includeLocation = _location != null && _location!.isNotEmpty;
    _includeWeather = _weather != null && _weather!.isNotEmpty;

    // 加载所有标签
    _loadTags();

    if (_includeLocation) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.parseLocationString(_location);
    }
  }

  Future<void> _loadTags() async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    _allTags = await databaseService.getTags();
    setState(() {});
  }

  void _parseSource(String source) {
    String author = '';
    String work = '';

    final authorMatch = RegExp(r'——([^《]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }

    final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }

    _authorController.text = author;
    _workController.text = work;
  }

  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) return '';

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }
    if (work.isNotEmpty) {
      result += ' 《$work》';
    }
    return result;
  }

  void _showTagSelectionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择标签'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _allTags.length,
            itemBuilder: (context, index) {
              final tag = _allTags[index];
              return CheckboxListTile(
                title: Text(tag.name),
                value: _tagIds.contains(tag.id),
                secondary: Icon(Icons.label_outline,
                    color: tag.color != null
                        ? Color(int.parse('0xFF${tag.color}'))
                        : Theme.of(context).colorScheme.primary),
                onChanged: (checked) {
                  setState(() {
                    if (checked ?? false) {
                      _tagIds.add(tag.id);
                    } else {
                      _tagIds.remove(tag.id);
                    }
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  void _showColorSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择颜色'),
        content: SizedBox(
          width: double.maxFinite,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _colorOptions)
                InkWell(
                  onTap: () {
                    setState(() {
                      _colorHex = color.value.toRadixString(16).substring(2);
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorHex != null &&
                                color.value.toRadixString(16).substring(2) ==
                                    _colorHex
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              // 添加一个清除颜色的选项
              InkWell(
                onTap: () {
                  setState(() {
                    _colorHex = null;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: Icon(
                    Icons.clear,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _getCurrentLocationAndWeather() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    if (!locationService.hasLocationPermission) {
      bool permissionGranted = await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法获取位置权限')));
        }
        return;
      }
    }

    final position = await locationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        _includeLocation = true;
        _location = locationService.getFormattedLocation();
      });

      await weatherService.getWeatherData(position.latitude, position.longitude);
      setState(() {
        _includeWeather = true;
        _weather = weatherService.currentWeather;
        _temperature = weatherService.temperature;
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

  @override
  Widget build(BuildContext context) {
    final databaseService = Provider.of<DatabaseService>(context);
    final locationService = Provider.of<LocationService>(context);
    final weatherService = Provider.of<WeatherService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              final newQuote = Quote(
                id: widget.quote.id,
                content: _contentController.text,
                date: widget.quote.date,
                aiAnalysis: _aiAnalysis,
                source: _formatSource(_authorController.text, _workController.text),
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
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('保存成功！')));
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
                  prefixIcon: Icon(Icons.edit_note_outlined),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _authorController,
                      decoration: InputDecoration(
                        labelText: '作者/人物',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _workController,
                      decoration: InputDecoration(
                        labelText: '作品名称',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.auto_stories_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                child: Text(
                  '将显示为: ${_formatSource(_authorController.text, _workController.text)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildOptionButton(
                      icon: Icons.label_outline,
                      title: '标签',
                      subtitle: _tagIds.isEmpty ? null : '已选择 ${_tagIds.length} 个',
                      selected: _tagIds.isNotEmpty,
                      onTap: _showTagSelectionDialog,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildOptionButton(
                      icon: Icons.color_lens_outlined,
                      title: '颜色',
                      selected: _colorHex != null,
                      color: _colorHex != null
                          ? Color(int.parse('0xFF$_colorHex'))
                          : null,
                      onTap: _showColorSelectionDialog,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildOptionButton(
                      icon: _includeLocation
                          ? Icons.location_on_outlined
                          : Icons.location_off_outlined,
                      title: '位置',
                      subtitle: _includeLocation ? locationService.city : null,
                      selected: _includeLocation,
                      onTap: () {
                        setState(() {
                          _includeLocation = !_includeLocation;
                          if (_includeLocation && _location == null) {
                            _getCurrentLocationAndWeather();
                          }
                        });
                      },
                      trailing: _includeLocation
                          ? IconButton(
                              icon: const Icon(Icons.refresh, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _getCurrentLocationAndWeather,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildOptionButton(
                      icon: _includeWeather
                          ? weatherService.getWeatherIconData()
                          : Icons.cloud_off_outlined,
                      title: '天气',
                      subtitle: _includeWeather
                          ? '${_weather ?? ''} ${_temperature ?? ''}'
                          : null,
                      selected: _includeWeather,
                      onTap: () {
                        setState(() {
                          _includeWeather = !_includeWeather;
                          if (_includeWeather && _weather == null) {
                            _getCurrentLocationAndWeather();
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final settingsService =
                      Provider.of<SettingsService>(context, listen: false);
                  final settings = settingsService.aiSettings;
                  final bool apiConfigured = settings.apiKey.isNotEmpty &&
                      settings.apiUrl.isNotEmpty &&
                      settings.model.isNotEmpty;

                  return apiConfigured
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.psychology_outlined,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'AI 分析',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withOpacity(0.5),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _aiAnalysis.isEmpty ? '暂无分析' : _aiAnalysis,
                                style: TextStyle(
                                  color: _aiAnalysis.isEmpty
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.5)
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  final aiService = Provider.of<AIService>(
                                    context,
                                    listen: false,
                                  );
                                  final summary = await aiService.summarizeNote(
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
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('AI分析失败: $e')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('重新生成分析'),
                            ),
                          ],
                        )
                      : const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withOpacity(0.5),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: color ??
                    (selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
