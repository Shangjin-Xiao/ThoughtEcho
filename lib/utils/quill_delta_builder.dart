import 'dart:convert';

/// Quill Delta操作的构建工具类
/// 用于AI修改笔记时，正确处理纯文本→Delta转换、并保留嵌入式内容（图片等）
class DeltaBuilder {
  /// 将纯文本内容转换为基础的Delta操作数组
  static List<Map<String, dynamic>> textToDelta(String text) {
    if (text.isEmpty) {
      return [];
    }
    // 简单的纯文本→Delta转换
    return [
      {"insert": text},
      {"insert": "\n"}
    ];
  }

  /// 在现有Delta基础上append新的纯文本
  /// 用于append模式：新文本总是在末尾（文字后、embed前）
  static List<Map<String, dynamic>> appendTextToDelta({
    required String? originalDeltaJson,
    required String newText,
  }) {
    final ops = <Map<String, dynamic>>[];

    if (originalDeltaJson != null && originalDeltaJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(originalDeltaJson);
        final originalOps = (decoded is List)
            ? decoded
            : (decoded is Map ? decoded['ops'] ?? [] : []);

        // 分离纯文本ops和embed ops
        final textOps = <Map<String, dynamic>>[];
        final embedOps = <Map<String, dynamic>>[];

        for (final op in originalOps) {
          if (op is Map) {
            if (op.containsKey('insert') && op['insert'] is Map) {
              // 这是一个embed（图片、视频等）
              embedOps.add(Map<String, dynamic>.from(op));
            } else {
              textOps.add(Map<String, dynamic>.from(op));
            }
          }
        }

        // 构建新的ops: 原有text ops + 新文本 + 原有embeds
        ops.addAll(textOps);
        ops.addAll(textToDelta(newText));
        ops.addAll(embedOps);
      } catch (e) {
        // 如果解析失败，返回新文本（不破坏系统）
        return textToDelta(newText);
      }
    } else {
      // 没有原有Delta，直接转换新文本
      ops.addAll(textToDelta(newText));
    }

    return ops;
  }

  /// 替换Delta中的纯文本部分，保留所有embed
  /// 用于replace模式：只改文本，保存所有图片
  static List<Map<String, dynamic>> replaceTextInDelta({
    required String? originalDeltaJson,
    required String newText,
  }) {
    final ops = <Map<String, dynamic>>[];

    if (originalDeltaJson != null && originalDeltaJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(originalDeltaJson);
        final originalOps = (decoded is List)
            ? decoded
            : (decoded is Map ? decoded['ops'] ?? [] : []);

        // 只保留embed ops，删除纯文本ops
        for (final op in originalOps) {
          if (op is Map && op.containsKey('insert') && op['insert'] is Map) {
            // 这是一个embed，保留
            ops.add(Map<String, dynamic>.from(op));
          }
        }

        // 在开头插入新文本
        ops.insertAll(0, textToDelta(newText));
      } catch (e) {
        // 解析失败，返回新文本
        return textToDelta(newText);
      }
    } else {
      ops.addAll(textToDelta(newText));
    }

    return ops;
  }

  /// 将Delta操作数组转换为JSON字符串
  static String deltaToJson(List<Map<String, dynamic>> ops) {
    return jsonEncode({"ops": ops});
  }

  /// 从JSON字符串解析Delta操作数组
  static List<Map<String, dynamic>>? deltaFromJson(String? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(decoded);
      }
      if (decoded is Map && decoded['ops'] is List) {
        return List<Map<String, dynamic>>.from(decoded['ops']);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// 从Delta提取纯文本内容
  static String extractTextFromDelta(String? deltaJson) {
    if (deltaJson == null || deltaJson.isEmpty) {
      return '';
    }

    final ops = deltaFromJson(deltaJson);
    if (ops == null) {
      return '';
    }

    final buffer = StringBuffer();
    for (final op in ops) {
      if (op.containsKey('insert')) {
        final insert = op['insert'];
        if (insert is String) {
          buffer.write(insert);
        } else if (insert is Map) {
          // embed类型，根据类型生成占位符
          if (insert.containsKey('image')) {
            buffer.write('[图片]');
          } else if (insert.containsKey('video')) {
            buffer.write('[视频]');
          } else {
            buffer.write('[嵌入内容]');
          }
        }
      }
    }

    return buffer.toString();
  }
}
