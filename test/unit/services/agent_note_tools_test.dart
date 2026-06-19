import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/get_app_context_tool.dart';
import 'package:thoughtecho/services/agent_tools/propose_edit_tool.dart';
import 'package:thoughtecho/services/agent_tools/propose_new_note_tool.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

import '../../test_helpers.dart';

class _TestDatabaseService extends DatabaseService {
  _TestDatabaseService(this._categories) : super.forTesting();

  final List<NoteCategory> _categories;

  @override
  Future<List<NoteCategory>> getCategories() async {
    return List<NoteCategory>.from(_categories);
  }
}

class _TestLocationService extends LocationService {
  _TestLocationService({
    this.locationDisplay = '',
    this.formattedLocation = '',
  });

  final String locationDisplay;
  final String formattedLocation;

  @override
  String getLocationDisplayText() => locationDisplay;

  @override
  String getFormattedLocation() => formattedLocation;
}

class _TestWeatherService extends WeatherService {
  _TestWeatherService({
    this.weatherKey,
    this.temperatureText,
    this.descriptionText,
  });

  final String? weatherKey;
  final String? temperatureText;
  final String? descriptionText;

  @override
  String? get currentWeather => weatherKey;

  @override
  String? get temperature => temperatureText;

  @override
  String? get weatherDescription => descriptionText;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHelpers.setupTestEnvironment();
  });

  group('ProposeNewNoteTool', () {
    test('returns smart result payload with tags and location weather toggles',
        () async {
      final tool = ProposeNewNoteTool(
        _TestDatabaseService(
          [
            NoteCategory(id: 'tag_work', name: '工作'),
            NoteCategory(id: 'tag_life', name: '生活'),
          ],
        ),
      );

      final result = await tool.execute(
        ToolCall(
          id: 'call_1',
          name: 'propose_new_note',
          arguments: const {
            'title': '草稿建议',
            'content': '今天想把这段感受记下来。',
            'tag_ids': ['tag_work'],
            'include_location': true,
            'include_weather': true,
            'reason': '整理成单独笔记更方便回顾。',
          },
        ),
      );

      expect(result.isError, isFalse);
      final match = RegExp(
        r'```smart_result\s*([\s\S]*?)\s*```',
      ).firstMatch(result.content);
      expect(match, isNotNull);

      final payload = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
      expect(payload['type'], 'smart_result');
      expect(payload['title'], '草稿建议');
      expect(payload['content'], '今天想把这段感受记下来。');
      expect(payload['action'], 'create');
      expect(payload['tag_ids'], ['tag_work']);
      expect(payload['include_location'], isTrue);
      expect(payload['include_weather'], isTrue);
      expect(payload['reason'], '整理成单独笔记更方便回顾。');
    });

    test('returns smart result payload with author and source', () async {
      final tool = ProposeNewNoteTool(
        _TestDatabaseService(
          [
            NoteCategory(id: 'tag_lit', name: '文学'),
          ],
        ),
      );

      final result = await tool.execute(
        ToolCall(
          id: 'call_author',
          name: 'propose_new_note',
          arguments: const {
            'title': '读书笔记',
            'content': '这是一段读书笔记内容。',
            'author': '王小波',
            'source': '《黄金时代》',
            'tag_ids': ['tag_lit'],
            'include_location': false,
            'include_weather': false,
          },
        ),
      );

      expect(result.isError, isFalse);
      final match = RegExp(
        r'```smart_result\s*([\s\S]*?)\s*```',
      ).firstMatch(result.content);
      expect(match, isNotNull);

      final payload = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
      expect(payload['author'], '王小波');
      expect(payload['source'], '《黄金时代》');
      expect(payload['tag_ids'], ['tag_lit']);
      expect(payload['include_location'], isFalse);
      expect(payload['include_weather'], isFalse);
    });

    test('rejects tag ids that do not exist in app categories', () async {
      final tool = ProposeNewNoteTool(
        _TestDatabaseService(
          [
            NoteCategory(id: 'tag_work', name: '工作'),
          ],
        ),
      );

      final result = await tool.execute(
        ToolCall(
          id: 'call_2',
          name: 'propose_new_note',
          arguments: const {
            'title': '草稿建议',
            'content': '这是一条新笔记',
            'tag_ids': ['tag_missing'],
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(result.content, contains('tag_missing'));
    });
  });

  group('GetTagsTool', () {
    test('returns available tags excluding hidden tag', () async {
      final tool = GetTagsTool(
        _TestDatabaseService(
          [
            NoteCategory(id: 'tag_work', name: '工作'),
            NoteCategory(id: 'tag_life', name: '生活'),
            NoteCategory(
              id: 'system_hidden_tag',
              name: '隐藏',
              isDefault: true,
            ),
          ],
        ),
      );

      final result = await tool.execute(
        ToolCall(
          id: 'call_3',
          name: 'get_tags',
          arguments: const {},
        ),
      );

      expect(result.isError, isFalse);
      final payload = jsonDecode(result.content) as Map<String, dynamic>;
      expect(payload['available_tags'], [
        {'id': 'tag_work', 'name': '工作', 'is_default': false},
        {'id': 'tag_life', 'name': '生活', 'is_default': false},
      ]);
      final pagination = payload['pagination'] as Map<String, dynamic>;
      expect(pagination['total_count'], 2);
      expect(pagination['has_more'], isFalse);
    });

    test('supports pagination', () async {
      final tags = List.generate(
        5,
        (i) => NoteCategory(id: 'tag_$i', name: '标签$i'),
      );
      final tool = GetTagsTool(_TestDatabaseService(tags));

      final result = await tool.execute(
        ToolCall(
          id: 'call_3b',
          name: 'get_tags',
          arguments: const {'offset': 2, 'limit': 2},
        ),
      );

      expect(result.isError, isFalse);
      final payload = jsonDecode(result.content) as Map<String, dynamic>;
      final list = payload['available_tags'] as List;
      expect(list.length, 2);
      expect((list[0] as Map)['id'], 'tag_2');
      expect((list[1] as Map)['id'], 'tag_3');
      final pagination = payload['pagination'] as Map<String, dynamic>;
      expect(pagination['total_count'], 5);
      expect(pagination['has_more'], isTrue);
    });
  });

  group('ProposeEditTool', () {
    test('returns smart result payload with new fields', () async {
      const tool = ProposeEditTool();

      final result = await tool.execute(
        ToolCall(
          id: 'call_edit_1',
          name: 'propose_edit',
          arguments: const {
            'title': '润色建议',
            'content': '润色后的内容',
            'action': 'replace',
            'note_id': 'note_123',
            'tag_ids': ['tag_1', 'tag_2'],
            'author': '鲁迅',
            'source': '《呐喊》',
            'include_location': true,
            'include_weather': false,
            'reason': '优化表达',
          },
        ),
      );

      expect(result.isError, isFalse);
      final match = RegExp(
        r'```smart_result\s*([\s\S]*?)\s*```',
      ).firstMatch(result.content);
      expect(match, isNotNull);

      final payload = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
      expect(payload['type'], 'smart_result');
      expect(payload['title'], '润色建议');
      expect(payload['content'], '润色后的内容');
      expect(payload['action'], 'replace');
      expect(payload['note_id'], 'note_123');
      expect(payload['tag_ids'], ['tag_1', 'tag_2']);
      expect(payload['author'], '鲁迅');
      expect(payload['source'], '《呐喊》');
      expect(payload['include_location'], isTrue);
      expect(payload['include_weather'], isFalse);
      expect(payload['reason'], '优化表达');
    });

    test('returns smart result payload without optional fields', () async {
      const tool = ProposeEditTool();

      final result = await tool.execute(
        ToolCall(
          id: 'call_edit_2',
          name: 'propose_edit',
          arguments: const {
            'title': '续写建议',
            'content': '续写内容',
            'action': 'append',
          },
        ),
      );

      expect(result.isError, isFalse);
      final match = RegExp(
        r'```smart_result\s*([\s\S]*?)\s*```',
      ).firstMatch(result.content);
      expect(match, isNotNull);

      final payload = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
      expect(payload['action'], 'append');
      expect(payload.containsKey('tag_ids'), isFalse);
      expect(payload.containsKey('author'), isFalse);
      expect(payload.containsKey('source'), isFalse);
      expect(payload['include_location'], isFalse);
      expect(payload['include_weather'], isFalse);
    });
  });

  group('GetLocationWeatherTool', () {
    test('returns current location and weather snapshot', () async {
      final tool = GetLocationWeatherTool(
        locationService: _TestLocationService(
          locationDisplay: '广州市·天河区',
          formattedLocation: '中国,广东省,广州市,天河区',
        ),
        weatherService: _TestWeatherService(
          weatherKey: 'clear',
          temperatureText: '27°C',
          descriptionText: '晴',
        ),
      );

      final result = await tool.execute(
        ToolCall(
          id: 'call_4',
          name: 'get_location_weather',
          arguments: const {},
        ),
      );

      expect(result.isError, isFalse);
      final payload = jsonDecode(result.content) as Map<String, dynamic>;
      expect(payload['location_display'], '广州市·天河区');
      expect(payload['location_storage'], '中国,广东省,广州市,天河区');
      expect(payload['weather_key'], 'clear');
      expect(payload['temperature'], '27°C');
      expect(payload['weather_display'], '晴 27°C');
    });
  });
}
