import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/get_app_context_tool.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_create_tool.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_edit_tool.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

import '../../test_harness.dart';

class _TestDatabaseService extends DatabaseService {
  _TestDatabaseService(this._categories, {this.quote}) : super.forTesting();

  final List<NoteCategory> _categories;
  final Quote? quote;

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async =>
      quote?.id == id ? quote : null;

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
    await TestHarness.initialize();
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

  group('new note proposal tools', () {
    test('rich create accepts semantic blocks and emits canonical Quill ops',
        () async {
      final tool = ProposeNoteCreateTool(_TestDatabaseService(const []));
      final properties =
          tool.parametersSchema['properties']! as Map<String, Object?>;

      expect(properties, containsPair('document_blocks', isA<Map>()));
      expect(properties, isNot(contains('document_ops')));

      final result = await tool.execute(ToolCall(
        id: 'create_rich_blocks',
        name: 'propose_note_create',
        arguments: const {
          'proposal_title': 'Structured note',
          'document_kind': 'rich',
          'document_blocks': [
            {
              'type': 'heading',
              'level': 2,
              'children': [
                {'text': 'Packing list'}
              ],
            },
            {
              'type': 'bullet',
              'children': [
                {'text': 'Passport', 'bold': true}
              ],
            },
          ],
        },
      ));

      expect(result.isError, isFalse);
      final artifact = result.artifact! as NoteProposalArtifact;
      expect(artifact.content, 'Packing list\nPassport');
      expect(artifact.documentOps, [
        {'insert': 'Packing list'},
        {
          'insert': '\n',
          'attributes': {'header': 2}
        },
        {
          'insert': 'Passport',
          'attributes': {'bold': true}
        },
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'}
        },
      ]);
    });

    test('plain create returns a typed artifact without persisted delta',
        () async {
      final tool = ProposeNoteCreateTool(_TestDatabaseService(const []));

      final result = await tool.execute(ToolCall(
        id: 'create_plain',
        name: 'propose_note_create',
        arguments: const {
          'proposal_title': 'New note',
          'reason': 'Capture this',
          'document_kind': 'plain',
          'content': 'Plain text',
        },
      ));

      final artifact = result.artifact! as NoteProposalArtifact;
      expect(result.content, isNot(contains('smart_result')));
      expect(artifact.resultKind, NoteDocumentKind.plain);
      expect(artifact.content, 'Plain text');
      expect(artifact.documentOps, isNull);
    });

    test('create rejects model-authored raw Delta', () async {
      final tool = ProposeNoteCreateTool(_TestDatabaseService(const []));

      final result = await tool.execute(ToolCall(
        id: 'create_raw_delta',
        name: 'propose_note_create',
        arguments: const {
          'proposal_title': 'Raw Delta',
          'document_kind': 'rich',
          'document_ops': [
            {
              'insert': 'Malformed heading\n',
              'attributes': {'header': 1}
            }
          ],
        },
      ));

      expect(result.isError, isTrue);
      expect(result.retryable, isTrue);
      expect(result.content, contains('document_blocks'));
    });

    test('edit preserves rich formatting and existing media', () async {
      final quote = Quote(
        id: 'rich-note',
        content: 'Before photo after',
        date: '2026-07-15T00:00:00.000Z',
        editSource: 'fullscreen',
        deltaContent: jsonEncode(const [
          {'insert': 'Before '},
          {
            'insert': {'image': '/private/photo.jpg'}
          },
          {'insert': ' photo after\n'},
        ]),
      );
      final tool = ProposeNoteEditTool(
        _TestDatabaseService(const [], quote: quote),
      );
      final properties =
          tool.parametersSchema['properties']! as Map<String, Object?>;
      final operations = properties['operations']! as Map<String, Object?>;
      final items = operations['items']! as Map<String, Object?>;
      final operationProperties = items['properties']! as Map<String, Object?>;

      expect(operationProperties, contains('insert_text'));
      expect(operationProperties, contains('insert_blocks'));
      expect(operationProperties, isNot(contains('insert_ops')));

      final result = await tool.execute(ToolCall(
        id: 'edit_rich',
        name: 'propose_note_edit',
        arguments: {
          'proposal_title': 'Polish',
          'note_id': quote.id,
          'base_revision': ProposeNoteEditTool.revisionForQuote(quote),
          'result_kind': 'preserve',
          'operations': const [
            {
              'type': 'replace',
              'old_text': 'after',
              'insert_blocks': [
                {
                  'type': 'paragraph',
                  'children': [
                    {'text': 'later', 'italic': true}
                  ],
                }
              ],
            }
          ],
        },
      ));

      final artifact = result.artifact! as NoteProposalArtifact;
      expect(artifact.resultKind, NoteDocumentKind.rich);
      expect(artifact.documentOps.toString(), contains('/private/photo.jpg'));
      expect(artifact.content, contains('later'));
    });

    test('whole-document rich edit cannot silently remove existing media',
        () async {
      final quote = Quote(
        id: 'rich-media-note',
        content: 'Before photo after',
        date: '2026-07-15T00:00:00.000Z',
        editSource: 'fullscreen',
        deltaContent: jsonEncode(const [
          {'insert': 'Before '},
          {
            'insert': {'image': '/private/photo.jpg'}
          },
          {'insert': ' photo after\n'},
        ]),
      );
      final tool = ProposeNoteEditTool(
        _TestDatabaseService(const [], quote: quote),
      );

      final result = await tool.execute(ToolCall(
        id: 'replace_document_with_media',
        name: 'propose_note_edit',
        arguments: {
          'proposal_title': 'Rewrite',
          'note_id': quote.id,
          'base_revision': ProposeNoteEditTool.revisionForQuote(quote),
          'result_kind': 'preserve',
          'operations': const [
            {
              'type': 'replaceDocument',
              'insert_text': 'Rewritten without the photo',
            }
          ],
        },
      ));

      expect(result.isError, isTrue);
      expect(result.retryable, isTrue);
      expect(result.content, contains('媒体'));
    });

    test('edit rejects model-authored raw Delta operations', () async {
      final quote = Quote(
        id: 'plain-raw-edit',
        content: 'Before',
        date: '2026-07-15T00:00:00.000Z',
      );
      final tool = ProposeNoteEditTool(
        _TestDatabaseService(const [], quote: quote),
      );

      final result = await tool.execute(ToolCall(
        id: 'edit_raw_delta',
        name: 'propose_note_edit',
        arguments: {
          'proposal_title': 'Raw edit',
          'note_id': quote.id,
          'base_revision': ProposeNoteEditTool.revisionForQuote(quote),
          'result_kind': 'preserve',
          'operations': const [
            {
              'type': 'replaceDocument',
              'insert_ops': [
                {'insert': 'After'}
              ],
            }
          ],
        },
      ));

      expect(result.isError, isTrue);
      expect(result.retryable, isTrue);
      expect(result.content, contains('insert_text'));
    });

    test('plain formatting requires an explicit plain-to-rich transition',
        () async {
      final quote = Quote(
        id: 'plain-note',
        content: 'plain',
        date: '2026-07-15T00:00:00.000Z',
      );
      final tool = ProposeNoteEditTool(
        _TestDatabaseService(const [], quote: quote),
      );
      Map<String, Object?> arguments(String kind) => {
            'proposal_title': 'Format',
            'note_id': quote.id,
            'base_revision': ProposeNoteEditTool.revisionForQuote(quote),
            'result_kind': kind,
            'operations': const [
              {
                'type': 'replaceDocument',
                'insert_blocks': [
                  {
                    'type': 'heading',
                    'level': 1,
                    'children': [
                      {'text': 'Title', 'bold': true}
                    ],
                  }
                ],
              }
            ],
          };

      final rejected = await tool.execute(ToolCall(
        id: 'preserve',
        name: 'propose_note_edit',
        arguments: arguments('preserve'),
      ));
      final converted = await tool.execute(ToolCall(
        id: 'convert',
        name: 'propose_note_edit',
        arguments: arguments('rich'),
      ));

      expect(rejected.isError, isTrue);
      final artifact = converted.artifact! as NoteProposalArtifact;
      expect(artifact.modeTransition, NoteModeTransition.plainToRich);
    });

    test('metadata omission preserves values and clearing is explicit',
        () async {
      final quote = Quote(
        id: 'metadata-note',
        content: 'text',
        date: '2026-07-15T00:00:00.000Z',
        sourceAuthor: 'Existing',
      );
      final tool = ProposeNoteEditTool(
        _TestDatabaseService(const [], quote: quote),
      );
      final result = await tool.execute(ToolCall(
        id: 'metadata',
        name: 'propose_note_edit',
        arguments: {
          'proposal_title': 'Edit',
          'note_id': quote.id,
          'base_revision': ProposeNoteEditTool.revisionForQuote(quote),
          'result_kind': 'preserve',
          'operations': const [
            {
              'type': 'replaceDocument',
              'insert_text': 'updated',
            }
          ],
          'metadata_patch': const {
            'author': {'action': 'clear'}
          },
        },
      ));

      final metadata = (result.artifact! as NoteProposalArtifact).metadata;
      expect(metadata['author'], {'action': 'clear'});
      expect(metadata.containsKey('source'), isFalse);
      expect(metadata.containsKey('tag_ids'), isFalse);
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
