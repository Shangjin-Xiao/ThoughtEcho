import 'package:uuid/uuid.dart';

import '../../constants/card_templates.dart';
import '../../models/generated_card.dart';
import '../../models/quote_model.dart';
import '../../utils/string_utils.dart';
import '../database_service.dart';
import 'card_generation_strategy.dart';
import 'card_generation_utils.dart';

/// 基于本地模板和启发式规则的卡片生成策略。
class FallbackCardGenerationStrategy implements CardGenerationStrategy {
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
      throw AICardGenerationException('无法生成卡片：笔记ID为空');
    }

    // 智能检测最适合的模板类型
    final cardType = _determineTemplateType(note,
        isRegeneration: isRegeneration, excludeType: excludeType);
    final cleanContent = StringUtils.removeObjectReplacementChar(note.content);
    final fallbackSvg = CardTemplates.getTemplateByType(
      brandName: brandName,
      type: cardType,
      content: cleanContent,
      author: note.sourceAuthor,
      date:
          CardGenerationUtils.formatDate(note.date, languageCode: languageCode),
      source: note.fullSource,
      location: note.location,
      weather: CardGenerationUtils.localizeWeather(note.weather,
          languageCode: languageCode),
      temperature: note.temperature,
      dayPeriod: CardGenerationUtils.localizeDayPeriod(note.dayPeriod,
          languageCode: languageCode),
    );

    return GeneratedCard(
      id: const Uuid().v4(),
      noteId: noteId,
      originalContent: cleanContent,
      svgContent: fallbackSvg,
      type: cardType,
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

  /// 智能决定模板类型（基于标签、内容和随机性）
  CardType _determineTemplateType(Quote note,
      {bool isRegeneration = false, CardType? excludeType}) {
    // 重新生成时完全随机，跳过内容匹配
    if (isRegeneration) {
      final allTypes = CardType.values.where((t) => t != excludeType).toList();
      if (allTypes.isEmpty) return CardType.knowledge;
      final randomcheck = DateTime.now().microsecondsSinceEpoch;
      return allTypes[randomcheck % allTypes.length];
    }

    // 1. 优先匹配 Hitokoto 官方分类 (如果 categoryId 匹配)
    if (note.categoryId != null) {
      CardType? candidate;
      switch (note.categoryId) {
        case DatabaseService.defaultCategoryIdAnime: // 动画 -> 几何/视觉
          candidate = CardType.geometric;
          break;
        case DatabaseService.defaultCategoryIdComic: // 漫画 -> 几何/视觉
          candidate = CardType.geometric;
          break;
        case DatabaseService.defaultCategoryIdGame: // 游戏 -> 赛博/科技
          candidate = CardType.cyberpunk;
          break;
        case DatabaseService.defaultCategoryIdNovel: // 小说 -> 复古/纸张
          candidate = CardType.retro;
          break;
        case DatabaseService.defaultCategoryIdPoem: // 诗词 -> 水墨/禅意
          candidate = CardType.ink;
          break;
        case DatabaseService.defaultCategoryIdPhilosophy: // 哲学 -> 哲学/深邃
          candidate = CardType.philosophical;
          break;
        case DatabaseService.defaultCategoryIdOriginal: // 原创 -> 情感/日记
          candidate = CardType.emotional;
          break;
        case DatabaseService.defaultCategoryIdMusic: // 音乐 -> 情感/日记
          candidate = CardType.emotional;
          break;
        case DatabaseService
              .defaultCategoryIdInternet: // 网络 -> 开发者/代码 (通常是网络段子或技术梗)
          candidate = CardType.dev;
          break;
        case DatabaseService.defaultCategoryIdMovie: // 影视 -> 引用/剧照感
          candidate = CardType.quote;
          break;
        case DatabaseService.defaultCategoryIdJoke: // 抖机灵 -> 极简/留白 (突出笑点)
          candidate = CardType.minimalist;
          break;
      }
      if (candidate != null && candidate != excludeType) {
        return candidate;
      }
    }

    final content = note.content.toLowerCase();
    final keywords = note.keywords?.map((e) => e.toLowerCase()).toList() ?? [];

    // 2. 匹配明确的关键词/标签 (支持中英文)
    if (_hasKeyword(content, keywords, [
      '代码',
      '编程',
      '开发',
      'code',
      'dev',
      'programming',
      'bug',
      'flutter',
      'dart',
      'api'
    ])) {
      const candidate = CardType.dev;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords, [
      '日记',
      '心情',
      '感受',
      'diary',
      'mood',
      'feeling',
      'emotion',
      'love',
      '悲伤',
      '快乐'
    ])) {
      const candidate = CardType.emotional;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords, [
      '学习',
      '笔记',
      '复习',
      'study',
      'note',
      'learn',
      'exam',
      'research',
      'paper',
      '学术'
    ])) {
      const candidate = CardType.academic;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords, [
      '自然',
      '风景',
      'nature',
      'tree',
      'flower',
      'mountain',
      'river',
      'green',
      'eco'
    ])) {
      const candidate = CardType.nature;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords,
        ['思考', '哲学', '意义', 'philosophy', 'think', 'mind', 'reason', 'truth'])) {
      const candidate = CardType.philosophical;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords, [
      '历史',
      '复古',
      '旧',
      'retro',
      'history',
      'old',
      'vintage',
      'memory',
      'time'
    ])) {
      const candidate = CardType.retro;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords, [
      '禅',
      '道',
      '静',
      'ink',
      'zen',
      'tao',
      'chinese',
      'calligraphy',
      'buddha'
    ])) {
      const candidate = CardType.ink;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords, [
      '赛博',
      '未来',
      '科技',
      'cyber',
      'future',
      'tech',
      'neon',
      'glitch',
      'punk'
    ])) {
      const candidate = CardType.cyberpunk;
      if (candidate != excludeType) return candidate;
    }

    if (_hasKeyword(content, keywords,
        ['几何', '设计', '艺术', 'geo', 'design', 'art', 'shape', 'abstract'])) {
      const candidate = CardType.geometric;
      if (candidate != excludeType) return candidate;
    }

    // 2. 基于元数据的启发式规则
    final hasAuthor =
        note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty;
    // 如果是短文本且有作者，很可能是名言
    if (hasAuthor && note.content.length < 100) {
      // 50% 概率使用专门的引用模板
      if (DateTime.now().millisecond % 2 == 0) {
        const candidate = CardType.quote;
        if (candidate != excludeType) return candidate;
      }
    }

    // 3. 随机回退
    final allTypes = [
      CardType.knowledge,
      CardType.quote,
      CardType.philosophical,
      CardType.minimalist,
      CardType.nature,
      CardType.retro,
      CardType.ink,
      CardType.cyberpunk,
      CardType.geometric,
      CardType.academic,
      CardType.emotional,
      CardType.dev,
      CardType.mindful,
      CardType.neonCyber,
      CardType.classicSerif,
      CardType.modernPop,
      CardType.softGradient,
      CardType.polaroid,
      CardType.magazine,
      CardType.sotaModern,
    ].where((t) => t != excludeType).toList();

    if (allTypes.isEmpty) return CardType.sotaModern;

    final randomcheck = DateTime.now().microsecondsSinceEpoch;
    // 增加 SOTA Modern 的出现概率 (20%)
    if (randomcheck % 5 == 0 && excludeType != CardType.sotaModern) {
      return CardType.sotaModern;
    }
    return allTypes[randomcheck % allTypes.length];
  }

  /// 检查内容或关键词中是否包含目标词汇
  bool _hasKeyword(
      String content, List<String> keywords, List<String> targetWords) {
    for (final target in targetWords) {
      if (content.contains(target) || keywords.contains(target)) {
        return true;
      }
    }
    return false;
  }
}
