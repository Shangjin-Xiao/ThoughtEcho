import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:uuid/uuid.dart';
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../constants/card_templates.dart';
import 'ai_service.dart';
import 'settings_service.dart';

/// AI卡片生成服务
class AICardGenerationService {
  final AIService _aiService;
  final SettingsService _settingsService;
  
  AICardGenerationService(this._aiService, this._settingsService);

  /// 为单条笔记生成卡片（MVP方案：AI分析类型 + 预设模板）
  Future<GeneratedCard> generateCard({
    required Quote note,
    String? customStyle,
  }) async {
    try {
      // 1. 使用AI分析内容类型
      final cardType = await _analyzeContentType(note);

      if (kDebugMode) {
        print('AI分析结果：内容类型为 ${cardType.name}');
      }

      // 2. 使用对应的预设模板生成SVG
      final svgContent = CardTemplates.getTemplateByType(
        type: cardType,
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
      );

      // 3. 创建卡片对象
      return GeneratedCard(
        id: const Uuid().v4(),
        noteId: note.id!,
        originalContent: note.content,
        svgContent: svgContent,
        type: cardType,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('卡片生成失败，使用默认模板: $e');
      }

      // 如果分析失败，使用默认知识卡片模板
      final fallbackSVG = CardTemplates.knowledgeTemplate(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
      );

      return GeneratedCard(
        id: const Uuid().v4(),
        noteId: note.id!,
        originalContent: note.content,
        svgContent: fallbackSVG,
        type: CardType.knowledge,
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

  /// 使用AI分析内容类型
  Future<CardType> _analyzeContentType(Quote note) async {
    try {
      // 检查AI服务是否可用
      if (!await _aiService.hasValidApiKeyAsync()) {
        // 如果AI不可用，使用简单的关键词分析
        return _analyzeContentTypeByKeywords(note);
      }

      // 构建分析提示词
      final analysisPrompt = '''
请分析以下笔记内容的类型，只返回以下三个选项之一：
1. knowledge - 知识学习、技能总结、学术内容
2. quote - 名言警句、引用他人话语、经典语录
3. philosophical - 哲学思考、人生感悟、深度反思

笔记内容：
${note.content}
${note.sourceAuthor != null ? '作者：${note.sourceAuthor}' : ''}

请只返回类型名称（knowledge/quote/philosophical），不要返回其他内容。
''';

      final result = await _aiService.generateSVG(analysisPrompt);
      final typeStr = result.trim().toLowerCase();

      if (typeStr.contains('quote')) {
        return CardType.quote;
      } else if (typeStr.contains('philosophical')) {
        return CardType.philosophical;
      } else {
        return CardType.knowledge;
      }
    } catch (e) {
      if (kDebugMode) {
        print('AI类型分析失败，使用关键词分析: $e');
      }
      return _analyzeContentTypeByKeywords(note);
    }
  }

  /// 基于关键词的简单类型分析（备用方案）
  CardType _analyzeContentTypeByKeywords(Quote note) {
    final content = note.content.toLowerCase();
    final hasAuthor = note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty;

    // 引用类型关键词
    final quoteKeywords = ['说', '曰', '云', '言', '道', '"', '"', '引用', '名言', '格言'];
    if (hasAuthor || quoteKeywords.any((keyword) => content.contains(keyword))) {
      return CardType.quote;
    }

    // 哲学思考关键词
    final philosophicalKeywords = ['思考', '反思', '感悟', '人生', '哲学', '意义', '价值', '存在', '真理', '智慧'];
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
      await Gal.putImageBytes(
        imageBytes,
        name: 'card_${card.id}',
      );

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
