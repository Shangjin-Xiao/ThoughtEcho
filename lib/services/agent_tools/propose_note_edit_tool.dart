import '../../models/note_proposal_artifact.dart';
import '../../models/quote_model.dart';
import '../../models/rich_text_edit.dart';
import '../../utils/agent_note_document_codec.dart';
import '../../utils/quill_delta_builder.dart';
import '../../utils/quill_structured_edit.dart';
import '../agent_tool.dart';
import '../database_service.dart';
import 'tool_argument_validator.dart';

class ProposeNoteEditTool extends AgentTool {
  const ProposeNoteEditTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'propose_note_edit';

  @override
  String get description => '对已有笔记提出经 revision 校验的局部或整篇修改（提案需要用户确认，不会直接落库）。\n'
      '调用前必须先用 get_note_detail 取得该笔记的最新 document_revision 与完整正文；'
      'revision 过期会得到「笔记已发生变化，请重新读取后再修改。」，此时要重新读取而不是重试同样的参数。\n'
      'old_text / anchor_text 必须原样复制自 get_note_detail 返回的正文（<note> 标签本身不属于正文），'
      '且必须在全文中唯一：找不到会得到「未找到 old_text…」，匹配多处会得到「找到 N 处匹配…」，'
      '两种情况都要补充上下文而不是照原样重试。\n'
      '普通替换传 insert_text，需要格式时传 insert_blocks（二者不能同时使用）。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'proposal_title': {
            'type': 'string',
            'description': '提案标题，展示在确认卡片顶部。必填且不能为空。',
          },
          'reason': {
            'type': 'string',
            'description': '为什么这么改（一句话），展示给用户帮助其判断是否采纳。',
          },
          'note_id': {
            'type': 'string',
            'description': '要修改的笔记 ID。只能来自 explore_notes / get_note_detail 的返回或'
                '应用提供的绑定笔记，不能编造；不存在时返回「未找到指定笔记。」',
          },
          'base_revision': {
            'type': 'string',
            'description': '原样填写 get_note_detail 返回的 document_revision。'
                '不要自行拼接或复用更早的值，否则会触发 revision 冲突。',
          },
          'result_kind': {
            'type': 'string',
            'enum': ['preserve', 'rich'],
            'description': '结果形态。preserve=保持笔记原本的编辑器模式（默认选择）；'
                'rich=显式把普通笔记转换成富文本。'
                'result_kind=preserve 且原笔记为普通笔记时不能使用 insert_blocks。',
          },
          'operations': {
            'type': 'array',
            'minItems': 1,
            'description':
                '按顺序应用的修改操作，至少一条。默认必须优先使用局部替换/插入/删除操作；仅当整篇重写且局部操作明显不适用时才允许使用 replaceDocument，并必须在 reason 中说明原因。',
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
                  'description':
                      'replace/delete 需要 old_text；insertBefore/insertAfter 需要 '
                          'anchor_text；append 追加到文末；replaceDocument 整篇替换（仅在整篇重构且局部 op 不适用时使用，需在 reason 说明原因）。',
                },
                'old_text': {
                  'type': 'string',
                  'description': 'type=replace 或 delete 时必须提供：要被替换/删除的原文，'
                      '原样复制自笔记正文且需在全文唯一。',
                },
                'anchor_text': {
                  'type': 'string',
                  'description':
                      'type=insertBefore 或 insertAfter 时必须提供：插入位置的锚点原文，'
                          '要求同 old_text。',
                },
                'insert_text': {
                  'type': 'string',
                  'description':
                      '除 delete 外必须提供 insert_text 或 insert_blocks 之一：'
                          '要写入的纯文本。不要写 Markdown 标记。',
                },
                'insert_blocks': _insertBlocksSchema,
              },
              'required': ['type'],
            },
          },
          'metadata_patch': _metadataPatchSchema,
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
    final validationError = validateToolArguments(
      toolName: name,
      schema: parametersSchema,
      arguments: call.arguments,
    );
    if (validationError != null) {
      return _error(call, validationError);
    }
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
          _normalizeInsertion(json, resultKind, type);
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
      if (!AgentNoteDocumentCodec.hasSameEmbeds(originalOps, finalOps)) {
        throw const FormatException(
          '为避免丢失笔记中的媒体，请保留图片、音频和视频，并改用不跨越媒体的局部文本修改。',
        );
      }
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

  void _normalizeInsertion(
    Map<String, Object?> operation,
    NoteDocumentKind resultKind,
    String? type,
  ) {
    final rawBlocks = operation.remove('insert_blocks');
    final insertText = operation.remove('insert_text');
    if (rawBlocks != null && insertText != null) {
      throw const FormatException('insert_text 和 insert_blocks 不能同时使用。');
    }
    if (rawBlocks != null) {
      if (resultKind == NoteDocumentKind.plain) {
        throw const FormatException('普通笔记不能使用 insert_blocks；如需格式请选择 rich。');
      }
      if (rawBlocks is! List || rawBlocks.isEmpty) {
        throw const FormatException('insert_blocks 不能为空。');
      }
      operation['blocks'] = rawBlocks;
      return;
    }
    if (insertText is String && insertText.isNotEmpty) {
      operation['insert_ops'] = AgentNoteDocumentCodec.validateAndNormalize(
        resultKind,
        [
          {'insert': insertText}
        ],
        document: type == 'replaceDocument',
      );
      return;
    }
    throw const FormatException('非删除操作必须提供 insert_text 或 insert_blocks。');
  }

  ToolResult _error(ToolCall call, String message) => ToolResult(
        toolCallId: call.id,
        content: message,
        isError: true,
        retryable: true,
      );
}

const Map<String, Object?> _insertBlocksSchema = {
  'type': 'array',
  'minItems': 1,
  'description': '需要格式（标题、列表、引用等）时替代 insert_text 使用的语义化块数组。'
      '只有 result_kind=rich 或原笔记本身是富文本时可用，普通笔记使用会返回'
      '「普通笔记不能使用 insert_blocks；如需格式请选择 rich。」；不要提交原始 Quill Delta。',
  'items': {
    'type': 'object',
    'properties': {
      'type': {
        'type': 'string',
        'enum': ['paragraph', 'heading', 'bullet', 'ordered', 'quote', 'code'],
        'description': '块类型：paragraph 段落、heading 标题、bullet 无序列表项、'
            'ordered 有序列表项、quote 引用、code 代码块。',
      },
      'level': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 6,
        'description': 'type=heading 时的标题级别 1-6，其他块类型不要提供。',
      },
      'children': {
        'type': 'array',
        'minItems': 1,
        'description': '该块内的文本片段，按顺序拼接；至少一段。',
        'items': {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': '这一段的纯文本，必填。不要在其中写 Markdown 标记。',
            },
            'bold': {'type': 'boolean', 'description': '是否加粗。'},
            'italic': {'type': 'boolean', 'description': '是否斜体。'},
            'underline': {'type': 'boolean', 'description': '是否下划线。'},
            'strike': {'type': 'boolean', 'description': '是否删除线。'},
            'code': {'type': 'boolean', 'description': '是否行内代码样式。'},
            'link': {'type': 'string', 'description': '超链接地址（可选）。'},
          },
          'required': ['text'],
        },
      },
    },
    'required': ['type', 'children'],
  },
};

/// 元数据补丁：只支持 tag_ids / author / source 三个字段，
/// 每个字段都是 `{action: set|clear, value?}` 结构，省略字段表示保持原值。
const Map<String, Object?> _metadataPatchSchema = {
  'type': 'object',
  'description': '可选。只修改用户明确要求修改的元数据；省略某字段表示保持原值，'
      '清除必须显式使用 action=clear。包含其他字段会返回'
      '「metadata_patch 包含不支持的字段或动作。」',
  'properties': {
    'tag_ids': {
      'type': 'object',
      'description': '标签补丁。action=set 时 value 必须是非空的标签 ID 数组，'
          'ID 只能来自 get_tags 的返回，不能编造（否则返回「metadata_patch 包含不存在的标签。」）。',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['set', 'clear'],
          'description': 'set=替换为 value；clear=清空全部标签。',
        },
        'value': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'action=set 时必须提供的非空标签 ID 数组。',
        },
      },
      'required': ['action'],
    },
    'author': {
      'type': 'object',
      'description': '作者补丁。action=set 时 value 必须是非空字符串，只填名字本身'
          '（如 `苏轼`）——显示时应用会自动加「——」前缀，不要自带破折号或书名号。',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['set', 'clear'],
          'description': 'set=改为 value；clear=清空作者。',
        },
        'value': {'type': 'string', 'description': 'action=set 时的新作者。'},
      },
      'required': ['action'],
    },
    'source': {
      'type': 'object',
      'description': '出处补丁。action=set 时 value 必须是非空字符串，只填作品名本身'
          '（如 `东坡志林`）——显示时应用会自动包上《》，自带书名号会显示成《《东坡志林》》。',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['set', 'clear'],
          'description': 'set=改为 value；clear=清空出处。',
        },
        'value': {'type': 'string', 'description': 'action=set 时的新出处。'},
      },
      'required': ['action'],
    },
  },
};
