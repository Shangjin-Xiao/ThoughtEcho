import 'dart:convert';

import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

import '../agent_tool.dart';

/// 提供 AI 所需的应用上下文：用户现有标签、当前位置信息和天气信息。
class GetAppContextTool extends AgentTool {
  const GetAppContextTool({
    required DatabaseService databaseService,
    required LocationService locationService,
    required WeatherService weatherService,
  })  : _databaseService = databaseService,
        _locationService = locationService,
        _weatherService = weatherService;

  final DatabaseService _databaseService;
  final LocationService _locationService;
  final WeatherService _weatherService;

  @override
  String get name => 'get_app_context';

  @override
  String get description => '获取当前应用上下文：用户已有标签列表，以及程序当前拿到的位置和天气信息。'
      '当你要为新笔记设置标签，或判断是否建议附加当前位置/天气时，先调用它。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    final categories = await _databaseService.getCategories();
    final locationDisplay = _locationService.getLocationDisplayText();
    final locationStorage = _locationService.getFormattedLocation();
    final weatherDescription = _weatherService.weatherDescription;
    final temperature = _weatherService.temperature;

    final weatherDisplayParts = <String>[
      if (weatherDescription != null && weatherDescription.isNotEmpty)
        weatherDescription,
      if (temperature != null && temperature.isNotEmpty) temperature,
    ];

    final payload = <String, Object?>{
      'available_tags': categories
          .map(
            (tag) => <String, String>{
              'id': tag.id,
              'name': tag.name,
            },
          )
          .toList(),
      'location_weather': <String, Object?>{
        'location_display': locationDisplay,
        'location_storage': locationStorage,
        'weather_key': _weatherService.currentWeather,
        'weather_description': weatherDescription,
        'temperature': temperature,
        'weather_display': weatherDisplayParts.join(' ').trim(),
      },
    };

    return ToolResult(
      toolCallId: toolCall.id,
      content: jsonEncode(payload),
    );
  }
}
