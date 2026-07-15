import '../../models/note_proposal_artifact.dart';
import '../../models/quote_model.dart';
import '../../models/rich_text_edit.dart';
import '../../utils/agent_note_document_codec.dart';
import '../../utils/quill_delta_builder.dart';
import '../../utils/quill_structured_edit.dart';
import '../agent_tool.dart';
import '../database_service.dart';

class ProposeNoteEditTool extends AgentTool {
  const ProposeNoteEditTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'propose_note_edit';

  @override
  String get description => '对已有笔记提出 revision 校验的局部或整篇修改。preserve 保持原编辑器模式；'
      'rich 可显式把普通笔记转换为富文本。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'proposal_title': {'type': 'string'},
          'reason': {'type': 'string'},
          'note_id': {'type': 'string'},
          'base_revision': {'type': 'string'},
          'result_kind': {
            'type': 'string',
            'enum': ['preserve', 'rich'],
          },
          'operations': {
            'type': 'array',
            'minItems': 1,
            'items': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'enum': [
                    'replace',
                    'insertBefore',
                    'insertAfter',
                    'append',
                    'delete',
                    'replaceDocument',
                  ],
                },
                'old_text': {'type': 'string'},
                'anchor_text': {'type': 'string'},
                'insert_ops': {
                  'type': 'array',
                  'items': {'type': 'object'},
                },
              },
              'required': ['type'],
            },
          },
          'metadata_patch': {'type': 'object'},
        },
        'required': [
          'proposal_title',
          'note_id',
          'base_revision',
          'result_kind',
          'operations',
        ],
      };

  static NoteDocumentKind kindForQuote(Quote quote) =>
      quote.editSource == 'fullscreen' && quote.deltaContent != null
          ? NoteDocumentKind.rich
          : NoteDocumentKind.plain;

  static List<Map<String, dynamic>> opsForQuote(Quote quote) {
    final kind = kindForQuote(quote);
    final raw = kind == NoteDocumentKind.rich
        ? DeltaBuilder.deltaFromJson(quote.deltaContent)
        : <Map<String, dynamic>>[
            {'insert': quote.content}
          ];
    if (raw == null) {
      throw const AgentNoteDocumentException('invalid_stored_delta');
    }
    return AgentNoteDocumentCodec.validateAndNormalize(
      kind,
      raw,
      allowExistingEmbeds: true,
    );
  }

  static String revisionForQuote(Quote quote) =>
      AgentNoteDocumentCodec.revisionOf(opsForQuote(quote));

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      final title = call.getString('proposal_title').trim();
      final noteId = call.getString('note_id').trim();
      final resultKindName = call.getString('result_kind');
      if (title.isEmpty || noteId.isEmpty) {
        throw const FormatException('proposal_title 和 note_id 不能为空。');
      }
      if (resultKindName != 'preserve' && resultKindName != 'rich') {
        throw const FormatException('result_kind 必须为 preserve 或 rich。');
      }
      final quote = await _databaseService.getQuoteById(noteId);
      if (quote == null) {
        return _error(call, '未找到指定笔记。');
      }
      final originalKind = kindForQuote(quote);
      final resultKind =
          resultKindName == 'rich' ? NoteDocumentKind.rich : originalKind;
      final rawOperations = call.arguments['operations'];
      if (rawOperations is! List || rawOperations.isEmpty) {
        throw const FormatException('operations 不能为空。');
      }
      final normalizedOperations = rawOperations.whereType<Map>().map((raw) {
        final json = raw.map((key, value) => MapEntry(key.toString(), value));
        final type = json['type']?.toString();
        if (type != 'delete') {
          json['insert_ops'] = AgentNoteDocumentCodec.validateAndNormalize(
            resultKind,
            json['insert_ops'],
            document: type == 'replaceDocument',
          );
        }
        return RichTextEditOperation.fromJson(json);
      }).toList(growable: false);
      final originalOps = opsForQuote(quote);
      final request = RichTextEditRequest(
        baseRevision: call.getString('base_revision'),
        operations: normalizedOperations,
      );
      final edited = QuillStructuredEdit.apply(
        originalOps: originalOps,
        request: request,
      );
      final finalOps = AgentNoteDocumentCodec.validateAndNormalize(
        resultKind,
        edited.ops,
        allowExistingEmbeds: true,
      );
      final content = AgentNoteDocumentCodec.plainTextOf(finalOps);
      if (content.trim().isEmpty) {
        throw const FormatException('修改后的笔记正文不能为空。');
      }
      final metadataPatch =
          await _metadataPatch(call.arguments['metadata_patch']);
      final artifact = NoteProposalArtifact(
        action: NoteProposalAction.edit,
        proposalTitle: title,
        reason: call.getString('reason').trim(),
        noteId: noteId,
        originalKind: originalKind,
        resultKind: resultKind,
        modeTransition: originalKind == NoteDocumentKind.plain &&
                resultKind == NoteDocumentKind.rich
            ? NoteModeTransition.plainToRich
            : null,
        content: content,
        documentOps: resultKind == NoteDocumentKind.rich ? finalOps : null,
        metadata: metadataPatch,
        changes: edited.preview
            .map((item) => NoteProposalChange(
                  type: item.type.name,
                  before: item.oldText,
                  after: item.newText,
                ))
            .toList(growable: false),
        baseRevision: request.baseRevision,
      );
      return ToolResult(
        toolCallId: call.id,
        content: '笔记修改提案已准备好，等待用户确认。',
        artifact: artifact,
      );
    } on RichTextEditConflict catch (error) {
      return _error(call, error.message);
    } on RichTextEditMatchFailure catch (error) {
      return _error(call, error.toString());
    } on FormatException catch (error) {
      return _error(call, error.message);
    } on AgentNoteDocumentException catch (error) {
      return _error(call, error.code);
    }
  }

  Future<Map<String, Object?>> _metadataPatch(Object? raw) async {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw const FormatException('metadata_patch 必须是对象。');
    }
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (!{'tag_ids', 'author', 'source'}.contains(key) ||
          entry.value is! Map) {
        throw const FormatException('metadata_patch 包含不支持的字段或动作。');
      }
      final patch = entry.value as Map;
      final action = patch['action']?.toString();
      if (action != 'set' && action != 'clear') {
        throw const FormatException('metadata_patch 动作必须为 set 或 clear。');
      }
      if (action == 'set') {
        final value = patch['value'];
        if (key == 'tag_ids') {
          if (value is! List || value.isEmpty) {
            throw const FormatException(
              '设置标签必须提供非空 tag_ids；清除请使用 clear。',
            );
          }
          final available = await _databaseService.getCategories();
          final ids = available.map((tag) => tag.id).toSet();
          if (value.any((id) => !ids.contains(id.toString()))) {
            throw const FormatException('metadata_patch 包含不存在的标签。');
          }
        } else if (value is! String || value.trim().isEmpty) {
          throw const FormatException('设置元数据必须提供非空 value；清除请使用 clear。');
        }
      }
      result[key] = Map<String, Object?>.from(patch);
    }
    return result;
  }

  ToolResult _error(ToolCall call, String message) => ToolResult(
        toolCallId: call.id,
        content: message,
        isError: true,
        retryable: true,
      );
}
