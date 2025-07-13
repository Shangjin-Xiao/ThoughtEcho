import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:uuid/uuid.dart';
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../constants/ai_card_prompts.dart';
import '../constants/card_templates.dart';
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
      // 1. 首先尝试AI智能生成SVG
      final prompt = AICardPrompts.intelligentCardPrompt(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
      );

      if (kDebugMode) {
        print('开始AI生成SVG卡片...');
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
  }) async {
    final cards = <GeneratedCard>[];

    for (final note in notes.take(maxCards)) {
      try {
        final card = await generateCard(note: note);
        cards.add(card);
      } catch (e) {
        if (kDebugMode) {
          print('生成卡片失败: ${note.id}, 错误: $e');
        }
        continue; // 跳过失败的卡片，继续生成其他卡片
      }
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
    cleaned =
        cleaned
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
    if (!cleaned.contains('<svg') || !cleaned.contains('</svg>')) {
      throw const AICardGenerationException('AI返回的内容不包含有效的SVG代码');
    }

    // 确保SVG有正确的命名空间
    if (!cleaned.contains('xmlns="http://www.w3.org/2000/svg"')) {
      cleaned = cleaned.replaceFirst(
        '<svg',
        '<svg xmlns="http://www.w3.org/2000/svg"',
      );
    }

    // 确保有viewBox或width/height
    if (!cleaned.contains('viewBox') &&
        !cleaned.contains('width=') &&
        !cleaned.contains('height=')) {
      cleaned = cleaned.replaceFirst('<svg', '<svg viewBox="0 0 400 600"');
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
  Future<String> saveCardAsImage(GeneratedCard card) async {
    try {
      // 使用卡片的toImageBytes方法获取图片数据
      final imageBytes = await card.toImageBytes();

      // 保存到相册
      await Gal.putImageBytes(imageBytes, name: 'card_${card.id}');

      return 'card_${card.id}';
    } catch (e) {
      throw Exception('保存图片失败: $e');
    }
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
}
