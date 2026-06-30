import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../constants/ai_card_prompts.dart';
import '../../models/generated_card.dart';
import '../../models/quote_model.dart';
import '../../utils/app_logger.dart';
import '../../utils/string_utils.dart';
import '../ai_service.dart';
import '../settings_service.dart';
import 'card_generation_strategy.dart';
import 'card_generation_utils.dart';
import 'svg_processing_isolate.dart';

class AiCardGenerationStrategy implements CardGenerationStrategy {
  final AIService _aiService;
  final SettingsService _settingsService;

  AiCardGenerationStrategy(this._aiService, this._settingsService);

  @override
  Future<GeneratedCard> generate({
    required Quote note,
    required String brandName,
    required String languageCode,
    String? customStyle,
    bool isRegeneration = false,
    CardType? excludeType,
  }) async {
    final noteId = note.id;
    if (noteId == null || noteId.isEmpty) {
      throw const AICardGenerationException('无法生成卡片：笔记ID为空');
    }

    if (excludeType == CardType.knowledge) {
      throw const AICardGenerationException(
        'AI 路径无法满足 excludeType=knowledge，请回退到其他策略',
      );
    }

    final formattedDate = CardGenerationUtils.formatDate(note.date,
        languageCode: languageCode);

    // 1. 智能选择最适合的提示词
    var prompt = _selectBestPrompt(
      note,
      customStyle,
      brandName: brandName,
      isRegeneration: isRegeneration,
      languageCode: languageCode,
      formattedDate: formattedDate,
    );

    // 1.1 根据用户语言设置追加语言统一指令
    String langDirective;
    switch (languageCode) {
      case 'zh':
        langDirective =
            '使用全中文作为所有底部元数据（日期、天气、时间段等），不要出现英文单词（例如用"雨""晨间""夜晚"而不是 rain/Morning）。如果某项信息缺失可以省略，不要编造。';
        break;
      case 'ja':
        langDirective =
            'Use Japanese for all footer metadata (date, weather, period). Do not mix English. If some info is missing, omit it.';
        break;
      case 'fr':
        langDirective =
            'Use French for all footer metadata (date, weather, period). Do not mix English. If some info is missing, omit it.';
        break;
      case 'en':
      default:
        langDirective =
            'Use English for all footer metadata (date, weather, period). Do not mix Chinese. If some info is missing, omit it.';
        break;
    }

    prompt = '$prompt\n\n### 语言 / Language Constraint\n$langDirective';

    AppLogger.i(
      '开始AI生成SVG卡片，内容长度: ${note.content.length}',
      source: 'AICardGeneration',
    );

    // 2. 调用AI生成SVG
    final svgContent = await _generateSVGContent(prompt);

    // 3. 在后台 isolate 中处理 SVG (清理 + 元数据补全)
    final processingData = AICardProcessingData(
      svgContent: svgContent,
      brandName: brandName,
      date: formattedDate,
      location: note.location,
      weather: note.weather,
      temperature: note.temperature,
      author: note.sourceAuthor,
      source: note.fullSource,
      dayPeriod: note.dayPeriod,
      languageCode: languageCode,
    );

    final result = await compute(processSVGTask, processingData);

    // 4. 重放日志
    for (final log in result.logs) {
      switch (log.level) {
        case 'ERROR':
          AppLogger.e(log.message, source: 'AICardGeneration');
          break;
        case 'WARN':
          AppLogger.w(log.message, source: 'AICardGeneration');
          break;
        case 'INFO':
          AppLogger.i(log.message, source: 'AICardGeneration');
          break;
        case 'DEBUG':
        default:
          AppLogger.d(log.message, source: 'AICardGeneration');
          break;
      }
    }

    final cleanedSVG = result.svg;

    AppLogger.i(
      'AI生成SVG成功，长度: ${cleanedSVG.length}',
      source: 'AICardGeneration',
    );

    // 5. 创建卡片对象（AI生成默认类型：knowledge）
    return GeneratedCard(
      id: const Uuid().v4(),
      noteId: noteId,
      originalContent: StringUtils.removeObjectReplacementChar(note.content),
      svgContent: cleanedSVG,
      type: CardType.knowledge,
      createdAt: DateTime.now(),
      author: note.sourceAuthor,
      source: note.fullSource,
      location: note.location,
      weather: note.weather,
      temperature: note.temperature,
      date: note.date,
      dayPeriod: note.dayPeriod,
    );
  }

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
      AppLogger.e('AI SVG生成失败: $e', error: e, source: 'AICardGeneration');
      rethrow; // 重新抛出异常，让上层处理回退
    }
  }

  /// 智能选择最适合的提示词（改进：增加随机性和变化）
  String _selectBestPrompt(
    Quote note,
    String? customStyle, {
    required String brandName,
    required String formattedDate,
    bool isRegeneration = false,
    String languageCode = 'zh',
  }) {
    // 移除媒体占位符(U+FFFC)，避免发送给AI时产生干扰
    final cleanContent = StringUtils.removeObjectReplacementChar(note.content);
    // 重新生成时完全随机，跳过内容匹配
    if (isRegeneration) {
      final random = DateTime.now().millisecondsSinceEpoch % 3;
      switch (random) {
        case 0:
          return _dispatchPrompt(
              'creative', note, brandName, cleanContent, formattedDate);
        case 1:
          return _dispatchPrompt(
              'intelligent', note, brandName, cleanContent, formattedDate);
        case 2:
        default:
          return _dispatchPrompt(
              'visual', note, brandName, cleanContent, formattedDate);
      }
    }

    // 分析内容特征
    final content = cleanContent.toLowerCase();
    final hasAuthor =
        note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty;

    // 如果指定了自定义风格，使用对应的提示词
    if (customStyle != null) {
      switch (customStyle) {
        case 'creative':
          return _dispatchPrompt(
              'creative', note, brandName, cleanContent, formattedDate);
        case 'intelligent':
          return _dispatchPrompt(
              'intelligent', note, brandName, cleanContent, formattedDate);
        case 'visual':
          return _dispatchPrompt(
              'visual', note, brandName, cleanContent, formattedDate);
      }
    }

    // 使用随机化的智能选择，避免单调
    final random = DateTime.now().millisecondsSinceEpoch % 100;

    // 1. 检查是否为引用/名言（30%概率使用智能卡片，70%随机海报）
    if (hasAuthor ||
        content.contains('说') ||
        content.contains('曰') ||
        content.contains('"')) {
      if (random < 30) {
        return _dispatchPrompt(
            'intelligent', note, brandName, cleanContent, formattedDate);
      } else {
        return _dispatchPrompt(
            'creative', note, brandName, cleanContent, formattedDate);
      }
    }

    // 2. 检查是否为技术/学习内容（40%视觉增强，30%智能，30%随机）
    final techKeywords = ['代码', '编程', '算法', '技术', '开发', '学习', '知识', '方法', '原理'];
    if (techKeywords.any((keyword) => content.contains(keyword))) {
      if (random < 40) {
        return _dispatchPrompt(
            'visual', note, brandName, cleanContent, formattedDate);
      } else if (random < 70) {
        return _dispatchPrompt(
            'intelligent', note, brandName, cleanContent, formattedDate);
      } else {
        return _dispatchPrompt(
            'creative', note, brandName, cleanContent, formattedDate);
      }
    }

    // 3. 检查是否为情感/生活内容（50%随机海报，50%视觉增强）
    final emotionalKeywords = ['感受', '心情', '生活', '感悟', '体验', '回忆', '梦想', '希望'];
    if (emotionalKeywords.any((keyword) => content.contains(keyword))) {
      if (random < 50) {
        return _dispatchPrompt(
            'creative', note, brandName, cleanContent, formattedDate);
      } else {
        return _dispatchPrompt(
            'visual', note, brandName, cleanContent, formattedDate);
      }
    }

    // 4. 根据内容长度和随机性选择
    if (cleanContent.length > 100) {
      // 长内容：40%随机海报，30%智能，30%视觉
      if (random < 40) {
        return _dispatchPrompt(
            'creative', note, brandName, cleanContent, formattedDate);
      } else if (random < 70) {
        return _dispatchPrompt(
            'intelligent', note, brandName, cleanContent, formattedDate);
      } else {
        return _dispatchPrompt(
            'visual', note, brandName, cleanContent, formattedDate);
      }
    }

    // 5. 默认使用三种提示词随机选择（各33%）
    if (random < 33) {
      return _dispatchPrompt(
          'creative', note, brandName, cleanContent, formattedDate);
    } else if (random < 66) {
      return _dispatchPrompt(
          'intelligent', note, brandName, cleanContent, formattedDate);
    } else {
      return _dispatchPrompt(
          'visual', note, brandName, cleanContent, formattedDate);
    }
  }

  /// 根据风格分发调用对应的提示词方法，减少重复参数列表构建
  String _dispatchPrompt(
    String type,
    Quote note,
    String brandName,
    String cleanContent,
    String formattedDate,
  ) {
    switch (type) {
      case 'creative':
        return AICardPrompts.randomStylePosterPrompt(
          brandName: brandName,
          content: cleanContent,
          author: note.sourceAuthor,
          date: formattedDate,
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      case 'intelligent':
        return AICardPrompts.intelligentCardPrompt(
          brandName: brandName,
          content: cleanContent,
          author: note.sourceAuthor,
          date: formattedDate,
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      case 'visual':
      default:
        return AICardPrompts.contentAwareVisualPrompt(
          brandName: brandName,
          content: cleanContent,
          author: note.sourceAuthor,
          date: formattedDate,
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
    }
  }
}
