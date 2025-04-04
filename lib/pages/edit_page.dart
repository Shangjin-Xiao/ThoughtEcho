import 'package:flutter/material.dart';
import 'package:mind_trace/models/quote_model.dart';
import 'package:mind_trace/services/ai_service.dart';
import 'package:mind_trace/services/database_service.dart';
import 'package:mind_trace/services/location_service.dart';
import 'package:mind_trace/services/settings_service.dart';
import 'package:mind_trace/services/weather_service.dart';
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
  
  // 添加位置和天气相关变量
  bool _includeLocation = false;
  bool _includeWeather = false;
  String? _location;
  String? _weather;
  String? _temperature;

  @override
  void initState() {
    super.initState();
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
      final locationService = Provider.of<LocationService>(context, listen: false);
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

  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }
    
    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }
    
    if (work.isNotEmpty) {
      result += ' 《$work》';
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
    final locationService = Provider.of<LocationService>(context, listen: false);
    final weatherService = Provider.of<WeatherService>(context, listen: false);
    
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
        _includeLocation = true;
        _location = locationService.getFormattedLocation();
      });
      
      // 获取天气
      await weatherService.getWeatherData(position.latitude, position.longitude);
      setState(() {
        _includeWeather = true;
        _weather = weatherService.currentWeather;
        _temperature = weatherService.temperature;
      });
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
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              // 保存编辑后的笔记
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('保存成功！')),
                );
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
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                        child: Row(
                          children: [
                            Icon(
                              _includeLocation ? Icons.location_on : Icons.location_off,
                              size: 20,
                              color: _includeLocation 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
                                      color: _includeLocation 
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (_includeLocation && _location != null)
                                    Text(
                                      locationService.city ?? '',
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
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                        child: Row(
                          children: [
                            Icon(
                              _includeWeather 
                                  ? weatherService.getWeatherIconData() 
                                  : Icons.cloud_off,
                              size: 20,
                              color: _includeWeather 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
                                      color: _includeWeather 
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (_includeWeather && _weather != null)
                                    Text(
                                      '${_weather!} ${_temperature ?? ""}',
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
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // 仅当API已配置时显示AI分析部分
              Builder(
                builder: (context) {
                  final settingsService = Provider.of<SettingsService>(context, listen: false);
                  final settings = settingsService.aiSettings;
                  final bool apiConfigured = settings.apiKey.isNotEmpty &&
                                            settings.apiUrl.isNotEmpty &&
                                            settings.model.isNotEmpty;
                  
                  return apiConfigured
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('AI 分析:'),
                          Text(_aiAnalysis.isEmpty ? '暂无分析' : _aiAnalysis),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () async {
                              try {
                                final aiService = Provider.of<AIService>(context, listen: false);
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('AI分析失败: $e')),
                                );
                              }
                            },
                            child: const Text('生成AI分析'),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(); // 如果API未配置，则不显示AI分析部分
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}