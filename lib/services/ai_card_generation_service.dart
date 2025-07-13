import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:uuid/uuid.dart';
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../constants/ai_card_prompts.dart';
import 'ai_service.dart';
import 'settings_service.dart';

/// AI卡片生成服务
class AICardGenerationService {
  final AIService _aiService;
  final SettingsService _settingsService;
  
  AICardGenerationService(this._aiService, this._settingsService);

  /// 为单条笔记生成卡片（智能选择风格）
  Future<GeneratedCard> generateCard({
    required Quote note,
    String? customStyle,
  }) async {
    try {
      // 1. 使用智能提示词
      final prompt = AICardPrompts.intelligentCardPrompt(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
      );

      // 2. 调用AI生成SVG
      final svgContent = await _generateSVGContent(prompt);

      // 3. 清理和验证SVG
      final cleanedSVG = _cleanSVGContent(svgContent);

      // 4. 创建卡片对象（AI会智能选择类型）
      return GeneratedCard(
        id: const Uuid().v4(),
        noteId: note.id!,
        originalContent: note.content,
        svgContent: cleanedSVG,
        type: _parseCardTypeFromSVG(cleanedSVG), // 从SVG内容解析卡片类型
        createdAt: DateTime.now(),
      );
    } catch (e) {
      throw AICardGenerationException('卡片生成失败: $e');
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

  /// 保存卡片为图片
  Future<String> saveCardAsImage(GeneratedCard card) async {
    try {
      // 使用卡片的toImageBytes方法获取图片数据
      final imageBytes = await card.toImageBytes();

      // 保存到相册
      final result = await ImageGallerySaver.saveImage(
        imageBytes,
        name: 'card_${card.id}',
      );

      return result['filePath'] ?? result['uri'] ?? '';
    } catch (e) {
      throw Exception('保存图片失败: $e');
    }
  }



  /// 增强的SVG清理逻辑，确保只保留SVG代码
  String _cleanSVGContent(String response) {
    String cleaned = response.trim();

    // 移除常见的markdown标记
    cleaned = cleaned
        .replaceAll('```svg', '')
        .replaceAll('```xml', '')
        .replaceAll('```', '')
        .replaceAll('`', '')
        .trim();

    // 移除可能的说明文字（在SVG前后）
    final lines = cleaned.split('\n');
    final svgLines = <String>[];
    bool inSvg = false;

    for (final line in lines) {
      final trimmedLine = line.trim();

      // 检测SVG开始
      if (trimmedLine.startsWith('<svg')) {
        inSvg = true;
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
    if (!cleaned.contains('<svg') || !cleaned.contains('</svg>')) {
      final svgStartIndex = response.indexOf('<svg');
      if (svgStartIndex >= 0) {
        final svgEndIndex = response.lastIndexOf('</svg>');
        if (svgEndIndex > svgStartIndex) {
          cleaned = response.substring(svgStartIndex, svgEndIndex + 6);
        }
      }
    }

    // 验证SVG基本结构
    if (!cleaned.contains('<svg') || !cleaned.contains('</svg>')) {
      throw const AICardGenerationException('AI返回的内容不包含有效的SVG代码');
    }

    return cleaned;
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

  /// 生成SVG内容
  Future<String> _generateSVGContent(String prompt) async {
    // 检查AI服务是否可用
    if (!await _aiService.hasValidApiKeyAsync()) {
      throw const AICardGenerationException('请先在设置中配置 API Key');
    }

    // 直接使用AI服务的内部方法生成SVG
    // 这里我们需要模拟generateInsights的逻辑，但使用自定义prompt
    try {
      // 获取当前provider
      final multiSettings = _settingsService.multiAISettings;
      final currentProvider = multiSettings.currentProvider;

      if (currentProvider == null) {
        throw const AICardGenerationException('未找到可用的AI提供商配置');
      }

      // 使用专门的SVG生成方法
      return await _aiService.generateSVG(prompt);
    } catch (e) {
      throw AICardGenerationException('生成SVG内容失败', e);
    }
  }

  /// 从SVG内容解析卡片类型
  /// 通过分析SVG中的元数据或内容特征来确定卡片类型
  CardType _parseCardTypeFromSVG(String svgContent) {
    try {
      // 查找SVG中的元数据注释或特定标识
      if (svgContent.contains('data-card-type="quote"') || 
          svgContent.contains('<!-- card-type: quote -->')) {
        return CardType.quote;
      }
      
      if (svgContent.contains('data-card-type="philosophical"') || 
          svgContent.contains('<!-- card-type: philosophical -->')) {
        return CardType.philosophical;
      }
      
      if (svgContent.contains('data-card-type="knowledge"') || 
          svgContent.contains('<!-- card-type: knowledge -->')) {
        return CardType.knowledge;
      }
      
      // 基于内容特征进行智能判断
      final lowerContent = svgContent.toLowerCase();
      
      // 检查是否包含引用特征
      if (lowerContent.contains('"') || lowerContent.contains('"') || 
          lowerContent.contains('quote') || lowerContent.contains('说') ||
          lowerContent.contains('引用') || lowerContent.contains('名言')) {
        return CardType.quote;
      }
      
      // 检查是否包含哲学思考特征
      if (lowerContent.contains('philosophy') || lowerContent.contains('philosophical') ||
          lowerContent.contains('哲学') || lowerContent.contains('思辨') ||
          lowerContent.contains('反思') || lowerContent.contains('思考') ||
          lowerContent.contains('人生') || lowerContent.contains('智慧')) {
        return CardType.philosophical;
      }
      
      // 默认返回知识类型
      return CardType.knowledge;
    } catch (e) {
      // 解析失败时返回默认类型
      return CardType.knowledge;
    }
  }

  /// 检查AI卡片生成功能是否启用
  bool get isEnabled {
    // 从设置服务中获取AI卡片生成开关状态
    return _settingsService.aiCardGenerationEnabled;
  }
}
