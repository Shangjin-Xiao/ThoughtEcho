part of '../quote_model.dart';

const Map<String, String> _sentimentKeyToLabel = {
  'positive': '积极',
  'negative': '消极',
  'neutral': '中性',
  'mixed': '复杂',
};
const Map<String, String> _sourceTypeKeyToLabel = {
  'manual': '手动',
  'ai': 'AI生成',
  'import': '导入',
};

bool _isValidDate(String date) {
  try {
    DateTime.parse(date);
    return true;
  } catch (e) {
    return false;
  }
}

bool _isValidColorHex(String? colorHex) {
  if (colorHex == null) return true;
  final regex = RegExp(r'^#[0-9A-Fa-f]{6}$');
  return regex.hasMatch(colorHex);
}

bool _isValidContent(String content) {
  return content.isNotEmpty && content.length <= 10000;
}

bool _parseDeletedFlag(dynamic raw) {
  if (raw == null) return false;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final text = raw.toString().trim().toLowerCase();
  return text == '1' || text == 'true';
}

String _normalizeToUtc(String? deletedAt) {
  final trimmed = deletedAt?.trim();
  if (trimmed != null && trimmed.isNotEmpty && _isValidDate(trimmed)) {
    return DateTime.parse(trimmed).toUtc().toIso8601String();
  }
  return DateTime.now().toUtc().toIso8601String();
}

String? _normalizeDeletedAtForState({
  required bool isDeleted,
  required String? deletedAt,
}) {
  if (!isDeleted) {
    return null;
  }

  final trimmed = deletedAt?.trim();
  if (trimmed != null && trimmed.isNotEmpty && _isValidDate(trimmed)) {
    return DateTime.parse(trimmed).toUtc().toIso8601String();
  }

  return DateTime.now().toUtc().toIso8601String();
}
