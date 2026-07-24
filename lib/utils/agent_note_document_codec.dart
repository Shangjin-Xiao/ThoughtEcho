import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/note_proposal_artifact.dart';

class AgentNoteDocumentException implements Exception {
  const AgentNoteDocumentException(this.code);

  final String code;

  @override
  String toString() => code;
}

class AgentNoteDocumentCodec {
  const AgentNoteDocumentCodec._();

  static const _inlineAttributes = {
    'bold',
    'italic',
    'underline',
    'strike',
    'code',
    'link',
    'font',
    'size',
    'color',
    'background',
  };
  static const _lineAttributes = {
    'header',
    'list',
    'blockquote',
    'code-block',
    'align',
    'direction',
    'indent',
  };

  static List<Map<String, dynamic>> validateAndNormalize(
    NoteDocumentKind kind,
    Object? input, {
    bool document = true,
    bool allowExistingEmbeds = false,
  }) {
    final raw = input is Map ? input['ops'] : input;
    if (raw is! List || raw.isEmpty) {
      throw const AgentNoteDocumentException('invalid_ops');
    }
    final normalized = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map || !item.containsKey('insert')) {
        throw const AgentNoteDocumentException('invalid_op');
      }
      final insert = item['insert'];
      if (insert is! String) {
        if (!allowExistingEmbeds) {
          throw const AgentNoteDocumentException('embed_not_allowed');
        }
      } else if (insert.isEmpty) {
        continue;
      }
      final attributes = _normalizeAttributes(
        item['attributes'],
        insert: insert,
        kind: kind,
      );
      final op = <String, dynamic>{
        'insert': _deepCopy(insert),
        if (attributes.isNotEmpty) 'attributes': attributes,
      };
      if (insert is String &&
          normalized.isNotEmpty &&
          normalized.last['insert'] is String &&
          _jsonEqual(normalized.last['attributes'], op['attributes'])) {
        normalized.last = {
          ...normalized.last,
          'insert': '${normalized.last['insert']}$insert',
        };
      } else {
        normalized.add(op);
      }
    }
    if (normalized.isEmpty) {
      throw const AgentNoteDocumentException('empty_document');
    }
    if (document) {
      final lastInsert = normalized.last['insert'];
      if (lastInsert is! String || !lastInsert.endsWith('\n')) {
        normalized.add({'insert': '\n'});
      }
    }
    return normalized;
  }

  static Map<String, dynamic> _normalizeAttributes(
    Object? raw, {
    required Object? insert,
    required NoteDocumentKind kind,
  }) {
    if (raw == null) return <String, dynamic>{};
    if (kind == NoteDocumentKind.plain) {
      throw const AgentNoteDocumentException('plain_attributes_not_allowed');
    }
    if (raw is! Map) {
      throw const AgentNoteDocumentException('invalid_attributes');
    }
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (!_inlineAttributes.contains(key) && !_lineAttributes.contains(key)) {
        throw const AgentNoteDocumentException('unsupported_attribute');
      }
      if (_lineAttributes.contains(key) &&
          (insert is! String || !insert.contains('\n'))) {
        throw const AgentNoteDocumentException(
            'line_attribute_without_newline');
      }
      if (key == 'link') {
        final link = entry.value?.toString() ?? '';
        final uri = Uri.tryParse(link);
        if (uri == null ||
            !{'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())) {
          throw const AgentNoteDocumentException('unsafe_link');
        }
        result[key] = link;
      } else {
        result[key] = _validatedAttributeValue(key, entry.value);
      }
    }
    return result;
  }

  static Object _validatedAttributeValue(String key, Object? value) {
    if ({
      'bold',
      'italic',
      'underline',
      'strike',
      'code',
      'blockquote',
      'code-block'
    }.contains(key)) {
      if (value != true) {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return true;
    }
    if (key == 'header') {
      if (value is! int || value < 1 || value > 6) {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return value;
    }
    if (key == 'indent') {
      if (value is! int || value < 1 || value > 8) {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return value;
    }
    if (key == 'list') {
      if (value is! String ||
          !{'ordered', 'bullet', 'checked', 'unchecked'}.contains(value)) {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return value;
    }
    if (key == 'align') {
      if (value is! String ||
          !{'left', 'center', 'right', 'justify'}.contains(value)) {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return value;
    }
    if (key == 'direction') {
      if (value != 'rtl') {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return 'rtl';
    }
    if (key == 'color' || key == 'background') {
      if (value is! String ||
          !RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(value)) {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return value;
    }
    if (key == 'font' || key == 'size') {
      if (value is! String || value.trim().isEmpty || value.length > 100) {
        throw const AgentNoteDocumentException('invalid_attribute_value');
      }
      return value;
    }
    throw const AgentNoteDocumentException('unsupported_attribute');
  }

  static String plainTextOf(List<Map<String, dynamic>> ops) => ops
      .map((op) => op['insert'] is String ? op['insert'] as String : '\uFFFC')
      .join()
      .replaceFirst(RegExp(r'\n$'), '');

  static String revisionOf(List<Map<String, dynamic>> ops) =>
      sha256.convert(utf8.encode(jsonEncode(ops))).toString();

  static List<Map<String, dynamic>> sanitizeForModel(
    List<Map<String, dynamic>> ops,
  ) {
    return ops.map((op) {
      if (op['insert'] is String) return Map<String, dynamic>.from(op);
      return <String, dynamic>{'insert': '[media]'};
    }).toList(growable: false);
  }

  static bool hasSameEmbeds(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) {
    Map<String, int> counts(List<Map<String, dynamic>> ops) {
      final result = <String, int>{};
      for (final op in ops) {
        if (op['insert'] is String) continue;
        final key = jsonEncode(op['insert']);
        result[key] = (result[key] ?? 0) + 1;
      }
      return result;
    }

    final beforeCounts = counts(before);
    final afterCounts = counts(after);
    if (beforeCounts.length != afterCounts.length) return false;
    return beforeCounts.entries.every(
      (entry) => afterCounts[entry.key] == entry.value,
    );
  }

  static Object? _deepCopy(Object? value) =>
      value == null ? null : jsonDecode(jsonEncode(value));

  static bool _jsonEqual(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);
}
