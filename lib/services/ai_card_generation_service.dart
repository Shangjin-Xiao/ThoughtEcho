import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';
// 条件导入：Web平台使用stub实现，其他平台使用gal
import '../utils/stub_implementations.dart'
    if (dart.library.io) 'package:gal/gal.dart' as gal;
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../constants/ai_card_prompts.dart';
import '../constants/card_templates.dart';
import '../utils/app_logger.dart';
import 'ai_service.dart';
import 'settings_service.dart';

/// AI卡片生成服务
class AICardGenerationService {
  final AIService _aiService;
  final SettingsService _settingsService;

  AICardGenerationService(this._aiService, this._settingsService);

  /// 为单条笔记生成卡片（AI智能生成 + 模板回退）
  Future<GeneratedCard> generateCard({
    required Quote note,
    String? customStyle,
  }) async {
    try {
      // 1. 智能选择最适合的提示词
      final prompt = _selectBestPrompt(note, customStyle);

      if (kDebugMode) {
        print('开始AI生成SVG卡片，内容长度: ${note.content.length}');
      }

      // 2. 调用AI生成SVG
      final svgContent = await _generateSVGContent(prompt);

      // 3. 清理和验证SVG
      final cleanedSVG = _cleanSVGContent(svgContent);

      if (kDebugMode) {
        print('AI生成SVG成功，长度: ${cleanedSVG.length}');
      }

      // 4. 创建卡片对象
      return GeneratedCard(
        id: const Uuid().v4(),
        noteId: note.id!,
        originalContent: note.content,
        svgContent: cleanedSVG,
        type: CardType.knowledge, // AI生成的默认为knowledge类型
        createdAt: DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('AI生成失败，使用回退模板: $e');
      }

      // AI生成失败时，使用预设模板作为回退方案
      final cardType = _analyzeContentTypeByKeywords(note);
      final fallbackSVG = CardTemplates.getTemplateByType(
        type: cardType,
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
      );

      return GeneratedCard(
        id: const Uuid().v4(),
        noteId: note.id!,
        originalContent: note.content,
        svgContent: fallbackSVG,
        type: cardType,
        createdAt: DateTime.now(),
      );
    }
  }

  /// 批量生成（用于周期报告）
  Future<List<GeneratedCard>> generateFeaturedCards(
    List<Quote> notes, {
    int maxCards = 6,
    Function(int current, int total, String? error)? onProgress,
  }) async {
    final cards = <GeneratedCard>[];
    final errors = <String>[];
    final notesToProcess = notes.take(maxCards).toList();

    for (int i = 0; i < notesToProcess.length; i++) {
      final note = notesToProcess[i];

      try {
        if (kDebugMode) {
          print('正在生成第${i + 1}/${notesToProcess.length}张卡片...');
        }

        final card = await generateCard(note: note);
        cards.add(card);

        // 报告进度
        onProgress?.call(i + 1, notesToProcess.length, null);

        // 添加延迟避免API调用过于频繁
        if (i < notesToProcess.length - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        final errorMsg =
            '生成第${i + 1}张卡片失败: ${note.content.substring(0, 30)}... - $e';
        errors.add(errorMsg);

        if (kDebugMode) {
          print(errorMsg);
        }

        // 报告错误进度
        onProgress?.call(i + 1, notesToProcess.length, e.toString());

        // 如果失败卡片太多，停止生成
        if (errors.length > maxCards ~/ 2) {
          logError('批量生成失败率过高，停止生成', source: 'AICardGenerationService');
          break;
        }

        continue; // 跳过失败的卡片，继续生成其他卡片
      }
    }

    if (cards.isEmpty && errors.isNotEmpty) {
      throw AICardGenerationException('批量生成完全失败: ${errors.join('; ')}');
    }

    if (kDebugMode) {
      print('批量生成完成: 成功${cards.length}张，失败${errors.length}张');
    }

    return cards;
  }

  /// 生成SVG内容
  Future<String> _generateSVGContent(String prompt) async {
    // 检查AI服务是否可用
    if (!await _aiService.hasValidApiKeyAsync()) {
      throw const AICardGenerationException('请先在设置中配置 API Key');
    }

    try {
      // 获取当前provider
      final multiSettings = _settingsService.multiAISettings;
      final currentProvider = multiSettings.currentProvider;

      if (currentProvider == null) {
        throw const AICardGenerationException('未找到可用的AI提供商配置');
      }

      // 使用专门的SVG生成方法
      final svgContent = await _aiService.generateSVG(prompt);

      // 验证生成的SVG是否有效
      if (svgContent.trim().isEmpty) {
        throw const AICardGenerationException('AI返回了空的SVG内容');
      }

      return svgContent;
    } catch (e) {
      if (kDebugMode) {
        print('AI SVG生成失败: $e');
      }
      rethrow; // 重新抛出异常，让上层处理回退
    }
  }

  /// 清理SVG内容
  String _cleanSVGContent(String response) {
    if (kDebugMode) {
      print('开始清理SVG内容，原始长度: ${response.length}');
    }

    String cleaned = response.trim();

    // 移除常见的markdown标记和说明文字
    cleaned = cleaned
        .replaceAll('```svg', '')
        .replaceAll('```xml', '')
        .replaceAll('```html', '')
        .replaceAll('```', '')
        .replaceAll('`', '')
        .trim();

    // 移除可能的说明文字（在SVG前后）
    final lines = cleaned.split('\n');
    final svgLines = <String>[];
    bool inSvg = false;
    bool foundSvgStart = false;

    for (final line in lines) {
      final trimmedLine = line.trim();

      // 跳过空行和注释行（除非在SVG内部）
      if (!inSvg && (trimmedLine.isEmpty || trimmedLine.startsWith('//'))) {
        continue;
      }

      // 检测SVG开始
      if (trimmedLine.startsWith('<svg')) {
        inSvg = true;
        foundSvgStart = true;
        svgLines.add(line);
        continue;
      }

      // 检测SVG结束
      if (trimmedLine.contains('</svg>')) {
        svgLines.add(line);
        break; // SVG结束后停止处理
      }

      // 在SVG内部时保留所有行
      if (inSvg) {
        svgLines.add(line);
      }
    }

    cleaned = svgLines.join('\n').trim();

    // 如果没有找到完整的SVG，尝试简单的字符串提取
    if (!foundSvgStart ||
        !cleaned.contains('<svg') ||
        !cleaned.contains('</svg>')) {
      if (kDebugMode) {
        print('未找到完整SVG，尝试字符串提取...');
      }

      final svgStartIndex = response.indexOf('<svg');
      if (svgStartIndex >= 0) {
        final svgEndIndex = response.lastIndexOf('</svg>');
        if (svgEndIndex > svgStartIndex) {
          cleaned = response.substring(svgStartIndex, svgEndIndex + 6);
          if (kDebugMode) {
            print('字符串提取成功，SVG长度: ${cleaned.length}');
          }
        }
      }
    }

    // 验证SVG基本结构
    if (!_isValidSVGStructure(cleaned)) {
      throw const AICardGenerationException('AI返回的内容不包含有效的SVG代码');
    }

    // 标准化SVG属性
    cleaned = _normalizeSVGAttributes(cleaned);

    // 验证SVG内容安全性
    if (!_isSafeSVGContent(cleaned)) {
      throw const AICardGenerationException('SVG内容包含不安全的元素');
    }

    if (kDebugMode) {
      print('SVG清理完成，最终长度: ${cleaned.length}');
    }

    return cleaned;
  }

  /// 基于关键词的简单类型分析（备用方案）
  CardType _analyzeContentTypeByKeywords(Quote note) {
    final content = note.content.toLowerCase();
    final hasAuthor =
        note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty;

    // 引用类型关键词
    final quoteKeywords = ['说', '曰', '云', '言', '道', '"', '"', '引用', '名言', '格言'];
    if (hasAuthor ||
        quoteKeywords.any((keyword) => content.contains(keyword))) {
      return CardType.quote;
    }

    // 哲学思考关键词
    final philosophicalKeywords = [
      '思考',
      '反思',
      '感悟',
      '人生',
      '哲学',
      '意义',
      '价值',
      '存在',
      '真理',
      '智慧',
    ];
    if (philosophicalKeywords.any((keyword) => content.contains(keyword))) {
      return CardType.philosophical;
    }

    // 默认为知识类型
    return CardType.knowledge;
  }

  /// 保存卡片为图片
  Future<String> saveCardAsImage(
    GeneratedCard card, {
    int width = 400,
    int height = 600,
    String? customName,
  }) async {
    try {
      if (kDebugMode) {
        print('开始保存卡片图片: ${card.id}');
      }

      // 验证输入参数
      if (width <= 0 || height <= 0) {
        throw ArgumentError('图片尺寸必须大于0');
      }

      if (width > 4000 || height > 4000) {
        throw ArgumentError('图片尺寸过大，最大支持4000x4000');
      }

      // 检查相册权限
      if (!await _checkGalleryPermission()) {
        throw Exception('没有相册访问权限，请在设置中开启权限');
      }

      // 使用卡片的toImageBytes方法获取图片数据
      final imageBytes = await card.toImageBytes(
        width: width,
        height: height,
      );

      // 生成唯一文件名，避免重复
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = customName != null
          ? '${customName}_$timestamp'
          : '心迹_Card_$timestamp'; // 保存到相册（仅移动端）
      if (!kIsWeb && Platform.isAndroid || Platform.isIOS) {
        await gal.Gal.putImageBytes(imageBytes, name: fileName);
      } else {
        // 桌面端或Web端的替代方案
        throw Exception('桌面端暂不支持直接保存到相册，建议使用分享功能');
      }

      if (kDebugMode) {
        print('卡片图片保存成功: $fileName');
      }

      return fileName;
    } catch (e) {
      if (kDebugMode) {
        print('保存卡片图片失败: $e');
      }
      rethrow; // 重新抛出异常让上层处理
    }
  }

  /// 检查当前平台是否支持相册功能
  bool _isPlatformSupported() {
    // gal插件只支持Android和iOS平台
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  /// 检查相册权限
  Future<bool> _checkGalleryPermission() async {
    // 检查平台支持
    if (!_isPlatformSupported()) {
      return false;
    }
    try {
      // 仅在移动端检查权限
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final hasAccess = await gal.Gal.hasAccess();
        if (!hasAccess) {
          // 请求权限
          final hasAccessAfterRequest = await gal.Gal.requestAccess();
          return hasAccessAfterRequest;
        }
        return true;
      }
      return false; // 桌面端不支持
    } catch (e) {
      if (kDebugMode) {
        print('检查相册权限失败: $e');
      }
      return false;
    }
  }

  /// 批量保存卡片为图片
  Future<List<String>> saveMultipleCardsAsImages(
    List<GeneratedCard> cards, {
    int width = 400,
    int height = 600,
    Function(int current, int total)? onProgress,
  }) async {
    final savedFiles = <String>[];

    for (int i = 0; i < cards.length; i++) {
      try {
        final fileName = await saveCardAsImage(
          cards[i],
          width: width,
          height: height,
          customName:
              '心迹_Card_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
        );
        savedFiles.add(fileName);

        onProgress?.call(i + 1, cards.length);
      } catch (e) {
        if (kDebugMode) {
          print('批量保存第${i + 1}张卡片失败: $e');
        }
        // 继续处理其他卡片
        savedFiles.add(''); // 添加空字符串表示失败
      }
    }

    return savedFiles;
  }

  /// 格式化日期
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}年${date.month}月${date.day}日';
    } catch (e) {
      return dateStr;
    }
  }

  /// 检查AI卡片生成功能是否启用
  bool get isEnabled {
    // 从设置服务中获取AI卡片生成开关状态
    return _settingsService.aiCardGenerationEnabled;
  }

  /// 智能选择最适合的提示词
  String _selectBestPrompt(Quote note, String? customStyle) {
    // 分析内容特征
    final content = note.content.toLowerCase();
    final hasAuthor =
        note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty;

    // 如果指定了自定义风格，使用对应的提示词
    if (customStyle != null) {
      switch (customStyle) {
        case 'creative':
          return AICardPrompts.randomStylePosterPrompt(content: note.content);
        case 'intelligent':
          return AICardPrompts.intelligentCardPrompt(
            content: note.content,
            author: note.sourceAuthor,
            date: _formatDate(note.date),
          );
        case 'visual':
          return AICardPrompts.contentAwareVisualPrompt(content: note.content);
      }
    }

    // 根据内容特征智能选择提示词

    // 1. 检查是否为技术/学习内容
    final techKeywords = ['代码', '编程', '算法', '技术', '开发', '学习', '知识', '方法', '原理'];
    if (techKeywords.any((keyword) => content.contains(keyword))) {
      return AICardPrompts.contentAwareVisualPrompt(content: note.content);
    }

    // 2. 检查是否为情感/生活内容
    final emotionalKeywords = ['感受', '心情', '生活', '感悟', '体验', '回忆', '梦想', '希望'];
    if (emotionalKeywords.any((keyword) => content.contains(keyword))) {
      return AICardPrompts.contentAwareVisualPrompt(content: note.content);
    }

    // 3. 检查是否为引用/名言
    if (hasAuthor ||
        content.contains('说') ||
        content.contains('曰') ||
        content.contains('"')) {
      return AICardPrompts.intelligentCardPrompt(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
      );
    }

    // 4. 检查内容长度，长内容使用创意海报风格
    if (note.content.length > 100) {
      return AICardPrompts.randomStylePosterPrompt(content: note.content);
    }

    // 5. 默认使用智能卡片提示词
    return AICardPrompts.intelligentCardPrompt(
      content: note.content,
      author: note.sourceAuthor,
      date: _formatDate(note.date),
    );
  }

  /// 验证SVG基本结构
  bool _isValidSVGStructure(String svgContent) {
    if (svgContent.trim().isEmpty) return false;

    // 基本结构检查
    if (!svgContent.contains('<svg') || !svgContent.contains('</svg>')) {
      return false;
    }

    // 检查标签是否正确闭合（简单检查）
    final openTags = '<svg'.allMatches(svgContent).length;
    final closeTags = '</svg>'.allMatches(svgContent).length;
    if (openTags != closeTags) {
      return false;
    }

    // 检查是否有基本的SVG内容
    if (svgContent.length < 50) {
      // 太短的SVG可能无效
      return false;
    }

    return true;
  }

  /// 标准化SVG属性
  String _normalizeSVGAttributes(String svgContent) {
    String normalized = svgContent;

    // 确保SVG有正确的命名空间
    if (!normalized.contains('xmlns="http://www.w3.org/2000/svg"')) {
      normalized = normalized.replaceFirst(
        '<svg',
        '<svg xmlns="http://www.w3.org/2000/svg"',
      );
    }

    // 确保有viewBox或width/height属性
    if (!normalized.contains('viewBox') &&
        !normalized.contains('width=') &&
        !normalized.contains('height=')) {
      normalized = normalized.replaceFirst(
        '<svg',
        '<svg width="400" height="600" viewBox="0 0 400 600"',
      );
    }

    return normalized;
  }

  /// 验证SVG内容安全性
  bool _isSafeSVGContent(String svgContent) {
    // 检查是否包含潜在危险的元素
    final dangerousElements = [
      '<script',
      '<iframe',
      '<object',
      '<embed',
      'javascript:',
      'data:text/html',
      'onload=',
      'onclick=',
      'onerror=',
    ];

    final lowerContent = svgContent.toLowerCase();
    for (final dangerous in dangerousElements) {
      if (lowerContent.contains(dangerous)) {
        if (kDebugMode) {
          print('发现不安全的SVG元素: $dangerous');
        }
        return false;
      }
    }

    return true;
  }
}
