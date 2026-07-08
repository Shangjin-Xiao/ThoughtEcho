import 'dart:convert';

/// Raised when rich-text Delta content cannot be serialized without data loss.
class DeltaContentSerializationException implements Exception {
  final String message;

  const DeltaContentSerializationException(this.message);

  @override
  String toString() => message;
}

/// Raised when a Delta already contains lossy media placeholders.
class LossyDeltaContentException extends DeltaContentSerializationException {
  const LossyDeltaContentException() : super('富文本内容包含有损媒体占位符，已阻止保存');
}

class DeltaContentSerializer {
  const DeltaContentSerializer._();

  static String encode(dynamic deltaData) {
    if (containsLossyMediaPlaceholder(deltaData)) {
      throw const LossyDeltaContentException();
    }

    return jsonEncode(deltaData);
  }

  static bool containsLossyMediaPlaceholder(dynamic value) {
    if (value is List) {
      return value.any(containsLossyMediaPlaceholder);
    }

    if (value is Map) {
      final insert = value['insert'];
      if (insert is Map &&
          insert['simplified'] == true &&
          (insert['type'] == 'image' || insert['type'] == 'video')) {
        return true;
      }

      return value.values.any(containsLossyMediaPlaceholder);
    }

    return false;
  }
}
