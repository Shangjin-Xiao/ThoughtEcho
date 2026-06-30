import 'package:flutter/material.dart';

/// 字符串处理工具类
class StringUtils {
  /// 格式化一言/笔记的来源，将作者和作品合并为格式化的字符串
  /// 例如："——作者《作品》"
  static String formatSource(String? author, String? source) {
    if ((author == null || author.isEmpty) &&
        (source == null || source.isEmpty)) {
      return '';
    }

    String result = '';
    if (author != null && author.isNotEmpty) {
      result += '——$author';
    }

    if (source != null && source.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$source》';
    }

    return result;
  }

  // Optimization: 提取 RegExp 为静态常量，避免频繁创建对象的开销。
  static final RegExp _authorRegex = RegExp(r'——([^《]+)');
  static final RegExp _workRegex = RegExp(r'《(.+?)》');

  /// 解析格式如"——作者《作品》"的字符串，提取作者和作品
  /// 返回[作者, 作品]元组
  static List<String> parseSource(String source) {
    String author = '';
    String work = '';

    // 提取作者（在"——"之后，"《"之前）
    final authorMatch = _authorRegex.firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }

    // 提取作品（在《》之间）
    final workMatch = _workRegex.firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }

    return [author, work];
  }

  /// 解析源格式并填充到控制器中
  static void parseSourceToControllers(
    String source,
    TextEditingController authorController,
    TextEditingController workController,
  ) {
    final parsed = parseSource(source);
    authorController.text = parsed[0];
    workController.text = parsed[1];
  }

  /// 检查文本是否需要展开/折叠功能
  static bool needsExpansion(String text, {int threshold = 100}) {
    return text.length > threshold;
  }

  /// 按用户可见字符截断预览文本，避免截断 Emoji 或组合字符。
  static String truncateForPreview(
    String text,
    int maxCharacters, {
    String ellipsis = '...',
  }) {
    if (maxCharacters < 0) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters', '不能为负数');
    }

    final previewText = removeObjectReplacementChar(text);
    final characters = previewText.characters;
    if (characters.length <= maxCharacters) {
      return previewText;
    }

    return '${characters.take(maxCharacters)}$ellipsis';
  }

  /// 移除文本中的 Object Replacement Character (U+FFFC)
  ///
  /// 当富文本编辑器中包含图片、音频、视频等嵌入媒体时，
  /// toPlainText() 会用 U+FFFC 字符作为占位符，
  /// 在手机上显示为方框内写着 "OBJ" 的图标。
  /// 此方法用于在展示、AI 分析、SVG 卡片生成等场景中清除该字符。
  static String removeObjectReplacementChar(String text) {
    return text.replaceAll('\u{FFFC}', '');
  }
}
