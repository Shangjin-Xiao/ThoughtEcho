import 'dart:convert';

import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

import '../agent_tool.dart';

class GetTagsTool extends AgentTool {
  const GetTagsTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'get_tags';

  @override
  String get description => '获取用户已有的标签列表（排除系统隐藏标签），支持分页。'
      '当你要为新笔记选择标签时，先调用此工具来获取可选标签 ID、名称及是否为默认标签。'
      '标签较多时可使用 offset 和 limit 分页获取。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'offset': {
            'type': 'integer',
            'description': '分页偏移量，默认 0',
          },
          'limit': {
            'type': 'integer',
            'description': '返回数量 (1-50, 默认 20)',
          },
        },
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    try {
      final offset = toolCall.getInt('offset', defaultValue: 0);
      final limit = toolCall.getInt('limit', defaultValue: 20).clamp(1, 50);

      final categories = await _databaseService.getCategories();
      final visibleCategories =
          categories.where((c) => c.id != 'system_hidden_tag').toList();
      final totalCount = visibleCategories.length;
      final paged = visibleCategories.skip(offset).take(limit).toList();

      final payload = <String, Object?>{
        'available_tags': paged
            .map(
              (tag) => <String, Object?>{
                    'id': tag.id,
                    'name': tag.name,
                    'is_default': tag.isDefault,
                  },
            )
            .toList(),
        'pagination': {
          'offset': offset,
          'limit': limit,
          'total_count': totalCount,
          'has_more': offset + paged.length < totalCount,
        },
      };

      return ToolResult(
        toolCallId: toolCall.id,
        content: jsonEncode(payload),
      );
    } catch (e, stack) {
      logError('GetTagsTool.execute 失败',
          error: e, stackTrace: stack, source: 'GetTagsTool');
      return ToolResult(
        toolCallId: toolCall.id,
        content: '获取标签列表时出错：$e',
        isError: true,
      );
    }
  }
}

class GetLocationWeatherTool extends AgentTool {
  const GetLocationWeatherTool({
    required LocationService locationService,
    required WeatherService weatherService,
  })  : _locationService = locationService,
        _weatherService = weatherService;

  final LocationService _locationService;
  final WeatherService _weatherService;

  @override
  String get name => 'get_location_weather';

  @override
  String get description => '获取当前位置和天气信息。'
      '当你要判断是否建议为笔记附加当前位置/天气时，调用此工具。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    try {
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
        'location_display': locationDisplay.isNotEmpty ? locationDisplay : null,
        'location_storage':
            locationStorage.isNotEmpty ? locationStorage : null,
        'weather_key': _weatherService.currentWeather,
        'weather_description': weatherDescription,
        'temperature': temperature,
        'weather_display': weatherDisplayParts.isNotEmpty
            ? weatherDisplayParts.join(' ')
            : null,
      };

      return ToolResult(
        toolCallId: toolCall.id,
        content: jsonEncode(payload),
      );
    } catch (e, stack) {
      logError('GetLocationWeatherTool.execute 失败',
          error: e, stackTrace: stack, source: 'GetLocationWeatherTool');
      return ToolResult(
        toolCallId: toolCall.id,
        content: '获取位置天气时出错：$e',
        isError: true,
      );
    }
  }
}