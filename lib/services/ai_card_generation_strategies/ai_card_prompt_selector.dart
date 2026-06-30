import '../../constants/ai_card_prompts.dart';
import '../../models/quote_model.dart';
import '../../utils/string_utils.dart';

/// AI卡片提示词选择器，负责提示词的智能路由与分发，用于解耦策略类以优化单文件长度。
class AICardPromptSelector {
  /// 智能选择最适合的提示词（改进：增加随机性和变化）
  static String selectBestPrompt(
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
        content.contains('"') ||
        content.contains('“') ||
        content.contains('”') ||
        content.contains('「') ||
        content.contains('」') ||
        content.contains('said') ||
        content.contains('says') ||
        content.contains('wrote') ||
        content.contains('quote')) {
      if (random < 30) {
        return _dispatchPrompt(
            'intelligent', note, brandName, cleanContent, formattedDate);
      } else {
        return _dispatchPrompt(
            'creative', note, brandName, cleanContent, formattedDate);
      }
    }

    // 2. 检查是否为技术/学习内容（40%视觉增强，30%智能，30%随机）
    final techKeywords = [
      '代码',
      '编程',
      '算法',
      '技术',
      '开发',
      '学习',
      '知识',
      '方法',
      '原理',
      'code',
      'program',
      'algorithm',
      'tech',
      'develop',
      'learn',
      'knowledge',
      'method',
      'principle',
      'study',
      'コード',
      'プログラミング',
      '技術',
      '学習',
      '開発',
      'développe',
      'techno',
      'apprendre',
      'étudier',
      'kod',
      'desarroll'
    ];
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
    final emotionalKeywords = [
      '感受',
      '心情',
      '生活',
      '感悟',
      '体验',
      '回忆',
      '梦想',
      '希望',
      'feel',
      'mood',
      'life',
      'experience',
      'memory',
      'dream',
      'hope',
      'sad',
      'happy',
      'love',
      'feeling',
      'emotion',
      '人生',
      '気持ち',
      '思い出',
      '夢',
      'espoir',
      'vie',
      'sentiment',
      'amour',
      'sentimiento',
      'vida'
    ];
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
  static String _dispatchPrompt(
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
