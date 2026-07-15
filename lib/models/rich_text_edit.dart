enum RichTextEditOperationType {
  replace,
  insertBefore,
  insertAfter,
  append,
  delete,
  replaceDocument,
}

class RichTextRun {
  const RichTextRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.link,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final String? link;

  factory RichTextRun.fromJson(Map<String, Object?> json) => RichTextRun(
        text: json['text']?.toString() ?? '',
        bold: json['bold'] == true,
        italic: json['italic'] == true,
        underline: json['underline'] == true,
        strike: json['strike'] == true,
        code: json['code'] == true,
        link: json['link']?.toString(),
      );

  Map<String, Object?> toJson() => {
        'text': text,
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (underline) 'underline': true,
        if (strike) 'strike': true,
        if (code) 'code': true,
        if (link != null) 'link': link,
      };
}

class RichTextBlock {
  const RichTextBlock({
    required this.type,
    required this.children,
    this.level,
  });

  const RichTextBlock.paragraph(List<RichTextRun> children)
      : this(type: 'paragraph', children: children);

  final String type;
  final List<RichTextRun> children;
  final int? level;

  factory RichTextBlock.fromJson(Map<String, Object?> json) {
    final rawChildren = json['children'];
    return RichTextBlock(
      type: json['type']?.toString() ?? 'paragraph',
      level: json['level'] is int ? json['level'] as int : null,
      children: rawChildren is List
          ? rawChildren
              .whereType<Map>()
              .map((item) => RichTextRun.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .toList(growable: false)
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
        'type': type,
        if (level != null) 'level': level,
        'children': children.map((child) => child.toJson()).toList(),
      };
}

class RichTextEditOperation {
  const RichTextEditOperation({
    required this.type,
    this.oldText,
    this.anchorText,
    this.blocks = const [],
    this.insertOps = const [],
  });

  const RichTextEditOperation.replace({
    required String oldText,
    required List<RichTextBlock> blocks,
  }) : this(
          type: RichTextEditOperationType.replace,
          oldText: oldText,
          blocks: blocks,
        );

  final RichTextEditOperationType type;
  final String? oldText;
  final String? anchorText;
  final List<RichTextBlock> blocks;
  final List<Map<String, dynamic>> insertOps;

  factory RichTextEditOperation.fromJson(Map<String, Object?> json) {
    final rawBlocks = json['blocks'];
    final rawInsertOps = json['insert_ops'];
    final typeName = json['type']?.toString();
    final type = RichTextEditOperationType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => throw FormatException('不支持的富文本操作: $typeName'),
    );
    return RichTextEditOperation(
      type: type,
      oldText: json['old_text']?.toString(),
      anchorText: json['anchor_text']?.toString(),
      blocks: rawBlocks is List
          ? rawBlocks
              .whereType<Map>()
              .map((item) => RichTextBlock.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .toList(growable: false)
          : const [],
      insertOps: rawInsertOps is List
          ? rawInsertOps
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
        'type': type.name,
        if (oldText != null) 'old_text': oldText,
        if (anchorText != null) 'anchor_text': anchorText,
        if (blocks.isNotEmpty)
          'blocks': blocks.map((block) => block.toJson()).toList(),
        if (insertOps.isNotEmpty) 'insert_ops': insertOps,
      };
}

class RichTextEditRequest {
  RichTextEditRequest({
    required this.baseRevision,
    required List<RichTextEditOperation> operations,
  }) : operations = List.unmodifiable(operations);

  final String baseRevision;
  final List<RichTextEditOperation> operations;

  factory RichTextEditRequest.fromJson(Map<String, Object?> json) {
    final rawOperations = json['operations'];
    return RichTextEditRequest(
      baseRevision: json['base_revision']?.toString() ?? '',
      operations: rawOperations is List
          ? rawOperations
              .whereType<Map>()
              .map((item) => RichTextEditOperation.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .toList(growable: false)
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
        'base_revision': baseRevision,
        'operations':
            operations.map((operation) => operation.toJson()).toList(),
      };
}

class RichTextEditPreview {
  const RichTextEditPreview({
    required this.type,
    required this.oldText,
    required this.newText,
  });

  final RichTextEditOperationType type;
  final String oldText;
  final String newText;
}

class RichTextEditResult {
  RichTextEditResult({
    required List<Map<String, dynamic>> ops,
    required List<RichTextEditPreview> preview,
  })  : ops = List.unmodifiable(ops),
        preview = List.unmodifiable(preview);

  final List<Map<String, dynamic>> ops;
  final List<RichTextEditPreview> preview;
}

class RichTextEditConflict implements Exception {
  const RichTextEditConflict(this.message);
  final String message;

  @override
  String toString() => message;
}

class RichTextEditMatchFailure implements Exception {
  const RichTextEditMatchFailure({
    required this.target,
    required this.matchCount,
  });

  final String target;
  final int matchCount;

  @override
  String toString() =>
      matchCount == 0 ? '找不到要修改的原文。' : '原文匹配到 $matchCount 处，无法确定要修改哪一处。';
}
