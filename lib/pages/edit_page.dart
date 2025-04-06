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
    final tags = await databaseService.getTags();
    setState(() {
      _allTags = tags;
    });
  }
  
  void _parseSource(String source) {
    final authorMatch = RegExp(r'——([^《]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      _authorController.text = authorMatch.group(1)!.trim();
    }
    
    final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      _workController.text = workMatch.group(1)!.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑笔记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveQuote,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 内容输入框
            TextField(
              controller: _contentController,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // 标签和颜色选择行
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
                    subtitle: _colorHex != null ? '' : null,
                    selected: _colorHex != null,
                    color: _colorHex != null ? Color(int.parse('0xFF$_colorHex')) : null,
                    onTap: _showColorSelectionDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 作者输入框
            TextField(
              controller: _authorController,
              decoration: const InputDecoration(
                labelText: '作者/人物',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            
            // 作品输入框
            TextField(
              controller: _workController,
              decoration: const InputDecoration(
                labelText: '作品名称',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.auto_stories_outlined),
              ),
            ),
            const SizedBox(height: 16),
            
            // 位置和天气选项
            Row(
              children: [
                Expanded(
                  child: _buildOptionButton(
                    icon: Icons.location_on_outlined,
                    title: '位置',
                    subtitle: _location,
                    selected: _includeLocation,
                    onTap: _toggleLocation,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildOptionButton(
                    icon: Icons.cloud_outlined,
                    title: '天气',
                    subtitle: _weather != null ? '$_weather $_temperature' : null,
                    selected: _includeWeather,
                    onTap: _toggleWeather,
                  ),
                ),
              ],
            ),
          ],
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
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
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
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
    );
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
                secondary: Icon(
                  IconData(
                    int.parse('0xe${tag.iconName}', radix: 16),
                    fontFamily: 'MaterialIcons',
                  ),
                ),
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
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
          height: 200,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _colorOptions.length + 1,
            itemBuilder: (context, index) {
              if (index == _colorOptions.length) {
                return InkWell(
                  onTap: () {
                    setState(() {
                      _colorHex = null;
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
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
                );
              }
              
              final color = _colorOptions[index];
              final isSelected = _colorHex != null &&
                  color.value.toRadixString(16).substring(2) == _colorHex;
                  
              return Material(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _colorHex = color.value.toRadixString(16).substring(2);
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: Colors.white,
                              width: 2,
                            )
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _toggleLocation() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final settingsService = Provider.of<SettingsService>(context, listen: false);
    
    if (!_includeLocation) {
      if (await locationService.checkLocationPermission()) {
        await locationService.getCurrentLocation();
        setState(() {
          _includeLocation = true;
          _location = locationService.currentAddress;
        });
      }
    } else {
      setState(() {
        _includeLocation = false;
        _location = null;
      });
    }
  }

  void _toggleWeather() async {
    final weatherService = Provider.of<WeatherService>(context, listen: false);
    
    if (!_includeWeather) {
      final weather = await weatherService.getCurrentWeather();
      if (weather != null) {
        setState(() {
          _includeWeather = true;
          _weather = weather.description;
          _temperature = '${weather.temperature}°C';
        });
      }
    } else {
      setState(() {
        _includeWeather = false;
        _weather = null;
        _temperature = null;
      });
    }
  }

  void _saveQuote() async {
    final quote = Quote(
      id: widget.quote.id,
      content: _contentController.text,
      date: widget.quote.date,
      sourceAuthor: _authorController.text.isNotEmpty ? _authorController.text : null,
      sourceWork: _workController.text.isNotEmpty ? _workController.text : null,
      tagIds: _tagIds,
      aiAnalysis: _aiAnalysis,
      colorHex: _colorHex,
      location: _location,
      weather: _weather,
      temperature: _temperature,
    );
    
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.updateQuote(quote);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    _workController.dispose();
    super.dispose();
  }
}
