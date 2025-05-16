import 'package:flutter/material.dart';

/// 字符串处理工具类
class StringUtils {
  /// 格式化一言/笔记的来源，将作者和作品合并为格式化的字符串
  /// 例如："——作者《作品》"
  static String formatSource(String? author, String? source) {
    if ((author == null || author.isEmpty) && (source == null || source.isEmpty)) {
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
  
  /// 解析格式如"——作者《作品》"的字符串，提取作者和作品
  /// 返回[作者, 作品]元组
  static List<String> parseSource(String source) {
    String author = '';
    String work = '';
    
    // 提取作者（在"——"之后，"《"之前）
    final authorMatch = RegExp(r'——([^《]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }
    
    // 提取作品（在《》之间）
    final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }
    
    return [author, work];
  }
  
  /// 解析源格式并填充到控制器中
  static void parseSourceToControllers(
    String source, 
    TextEditingController authorController, 
    TextEditingController workController
  ) {
    final parsed = parseSource(source);
    authorController.text = parsed[0];
    workController.text = parsed[1];
  }
  
  /// 检查文本是否需要展开/折叠功能
  static bool needsExpansion(String text, {int threshold = 100}) {
    return text.length > threshold;
  }
}