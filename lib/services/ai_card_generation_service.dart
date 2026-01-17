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
import 'database_service.dart';
import 'svg_to_image_service.dart';
import 'package:flutter/widgets.dart'; // 为新增的BuildContext参数添加导入

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
    // 如果用户关闭了 AI 生成功能，则直接使用模板（功能仍可用，只是没有AI增强）
    if (!isEnabled) {
      AppLogger.i('AI卡片生成已关闭，使用本地模板生成', source: 'AICardGeneration');
      return _buildFallbackCard(note);
    }

    try {
      // 1. 智能选择最适合的提示词
      var prompt = _selectBestPrompt(note, customStyle);

      // 1.1 根据笔记语言追加语言统一指令，避免出现 rain/Morning 等英文混杂
      final isChineseNote = _containsChinese(note.content);
      final langDirective = isChineseNote
          ? '使用全中文作为所有底部元数据（日期、天气、时间段等），不要出现英文单词（例如用“雨”“晨间”“夜晚”而不是 rain/Morning）。如果某项信息缺失可以省略，不要编造。'
          : 'Use the same language as the note for any footer metadata (date, weather, period). Keep language consistent and do not mix Chinese unless original content is Chinese.';
      prompt = '$prompt\n\n### 语言 / Language Constraint\n$langDirective';

      AppLogger.i(
        '开始AI生成SVG卡片，内容长度: ${note.content.length}',
        source: 'AICardGeneration',
      );

      // 2. 调用AI生成SVG
      final svgContent = await _generateSVGContent(prompt);

      // 3. 清理和验证SVG
      var cleanedSVG = _cleanSVGContent(svgContent);

      // 4. 补全缺失的底部元数据（AI 可能忽略）
      cleanedSVG = _ensureMetadataPresence(
        cleanedSVG,
        date: _formatDate(note.date),
        location: note.location,
        weather: note.weather,
        temperature: note.temperature,
        author: note.sourceAuthor,
        source: note.fullSource,
        dayPeriod: note.dayPeriod,
      );

      AppLogger.i(
        'AI生成SVG成功，长度: ${cleanedSVG.length}',
        source: 'AICardGeneration',
      );

      // 5. 创建卡片对象（AI生成默认类型：knowledge）
      return GeneratedCard(
        id: const Uuid().v4(),
        noteId: note.id!,
        originalContent: note.content,
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
    } catch (e) {
      AppLogger.w('AI生成失败，使用回退模板: $e', source: 'AICardGeneration');
      return _buildFallbackCard(note);
    }
  }

  /// 本地模板回退封装(AI关闭或失败时使用)
  GeneratedCard _buildFallbackCard(Quote note) {
    // 智能检测最适合的模板类型
    final cardType = _determineTemplateType(note);
    final fallbackSVG = CardTemplates.getTemplateByType(
      type: cardType,
      content: note.content,
      author: note.sourceAuthor,
      date: _formatDate(note.date),
      source: note.fullSource,
      location: note.location,
      weather: note.weather,
      temperature: note.temperature,
      dayPeriod: note.dayPeriod,
    );

    return GeneratedCard(
      id: const Uuid().v4(),
      noteId: note.id!,
      originalContent: note.content,
      svgContent: fallbackSVG,
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
  CardType _determineTemplateType(Quote note) {
    // 1. 优先匹配 Hitokoto 官方分类 (如果 categoryId 匹配)
    if (note.categoryId != null) {
      switch (note.categoryId) {
        case DatabaseService.defaultCategoryIdAnime: // 动画 -> 几何/视觉
          return CardType.geometric;
        case DatabaseService.defaultCategoryIdComic: // 漫画 -> 几何/视觉
          return CardType.geometric;
        case DatabaseService.defaultCategoryIdGame: // 游戏 -> 赛博/科技
          return CardType.cyberpunk;
        case DatabaseService.defaultCategoryIdNovel: // 小说 -> 复古/纸张
          return CardType.retro;
        case DatabaseService.defaultCategoryIdPoem: // 诗词 -> 水墨/禅意
          return CardType.ink;
        case DatabaseService.defaultCategoryIdPhilosophy: // 哲学 -> 哲学/深邃
          return CardType.philosophical;
        case DatabaseService.defaultCategoryIdOriginal: // 原创 -> 情感/日记
          return CardType.emotional;
        case DatabaseService.defaultCategoryIdMusic: // 音乐 -> 情感/日记
          return CardType.emotional;
        case DatabaseService
              .defaultCategoryIdInternet: // 网络 -> 开发者/代码 (通常是网络段子或技术梗)
          return CardType.dev;
        case DatabaseService.defaultCategoryIdMovie: // 影视 -> 引用/剧照感
          return CardType.quote;
        case DatabaseService.defaultCategoryIdJoke: // 抖机灵 -> 极简/留白 (突出笑点)
          return CardType.minimalist;
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
      return CardType.dev;
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
      return CardType.emotional;
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
      return CardType.academic;
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
      return CardType.nature;
    }

    if (_hasKeyword(content, keywords,
        ['思考', '哲学', '意义', 'philosophy', 'think', 'mind', 'reason', 'truth'])) {
      return CardType.philosophical;
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
      return CardType.retro;
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
      return CardType.ink;
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
      return CardType.cyberpunk;
    }

    if (_hasKeyword(content, keywords,
        ['几何', '设计', '艺术', 'geo', 'design', 'art', 'shape', 'abstract'])) {
      return CardType.geometric;
    }

    // 2. 基于元数据的启发式规则
    final hasAuthor =
        note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty;
    // 如果是短文本且有作者，很可能是名言
    if (hasAuthor && note.content.length < 100) {
      // 50% 概率使用专门的引用模板
      if (DateTime.now().millisecond % 2 == 0) {
        return CardType.quote;
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
    ];

    final randomcheck = DateTime.now().microsecondsSinceEpoch;
    return allTypes[randomcheck % allTypes.length];
  }

  /// 检查内容或关键词中是否包含目标词汇
  bool _hasKeyword(
      String content, List<String> keywords, List<String> targets) {
    // 检查内容
    for (final target in targets) {
      if (content.contains(target)) return true;
    }
    // 检查关键词
    for (final keyword in keywords) {
      for (final target in targets) {
        if (keyword.contains(target)) return true;
      }
    }
    return false;
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
        AppLogger.i(
          '正在生成第${i + 1}/${notesToProcess.length}张卡片...',
          source: 'AICardGeneration',
        );

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

        AppLogger.e(errorMsg, source: 'AICardGeneration');

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

    AppLogger.i(
      '批量生成完成: 成功${cards.length}张，失败${errors.length}张',
      source: 'AICardGeneration',
    );

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
      AppLogger.e('AI SVG生成失败: $e', error: e, source: 'AICardGeneration');
      rethrow; // 重新抛出异常，让上层处理回退
    }
  }

  /// 清理SVG内容
  String _cleanSVGContent(String response) {
    AppLogger.d(
      '开始清理SVG内容，原始长度: ${response.length}',
      source: 'AICardGeneration',
    );

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
      AppLogger.w('未找到完整SVG，尝试字符串提取...', source: 'AICardGeneration');

      final svgStartIndex = response.indexOf('<svg');
      if (svgStartIndex >= 0) {
        final svgEndIndex = response.lastIndexOf('</svg>');
        if (svgEndIndex > svgStartIndex) {
          cleaned = response.substring(svgStartIndex, svgEndIndex + 6);
          AppLogger.i(
            '字符串提取成功，SVG长度: ${cleaned.length}',
            source: 'AICardGeneration',
          );
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

    AppLogger.d('SVG清理完成，最终长度: ${cleaned.length}', source: 'AICardGeneration');

    return cleaned;
  }

  /// 保存卡片为图片
  Future<String> saveCardAsImage(
    GeneratedCard card, {
    int width = 400,
    int height = 600,
    String? customName,
    double scaleFactor = 2.0,
    ExportRenderMode renderMode = ExportRenderMode.contain,
    BuildContext? context,
  }) async {
    try {
      AppLogger.i(
        '开始保存卡片图片: ${card.id}, 尺寸: ${width}x$height, 缩放: $scaleFactor',
        source: 'AICardGeneration',
      );

      // 验证输入参数
      if (width <= 0 || height <= 0) {
        throw ArgumentError('图片尺寸必须大于0');
      }

      if (width > 4000 || height > 4000) {
        throw ArgumentError('图片尺寸过大，最大支持4000x4000');
      }

      // 强烈建议传入BuildContext以使用精准渲染
      if (context == null) {
        AppLogger.w('未提供BuildContext，渲染可能与预览不一致', source: 'AICardGeneration');
      }

      // 先渲染图片（此时尚未出现 async gap，满足 use_build_context_synchronously 规范）
      final safeContext =
          (context != null && context is Element && !context.mounted)
              ? null
              : context;

      // 关键修复：直接使用原始 svgContent，不做任何标准化处理
      // 这样保证保存时的渲染与预览完全一致（预览使用 SVGCardWidget 直接渲染原始 SVG）
      final imageBytes = await card.toImageBytes(
        width: width,
        height: height,
        scaleFactor: scaleFactor,
        renderMode: renderMode,
        context: safeContext,
      );

      AppLogger.i(
        '卡片图片渲染完成，大小: ${imageBytes.length} bytes',
        source: 'AICardGeneration',
      );

      // 再检查/申请相册权限并保存（与渲染解耦，避免 context 跨 await）
      if (!await _checkGalleryPermission()) {
        throw Exception('没有相册访问权限，请在设置中开启权限');
      }

      // 生成唯一文件名，避免重复
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = customName != null
          ? '${customName}_$timestamp'
          : '心迹_Card_$timestamp';

      // 保存到相册（仅移动端）
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await gal.Gal.putImageBytes(imageBytes, name: fileName);
      } else {
        // 桌面端或Web端的替代方案
        throw Exception('桌面端暂不支持直接保存到相册，建议使用分享功能');
      }

      AppLogger.i('卡片图片保存成功: $fileName', source: 'AICardGeneration');

      return fileName;
    } catch (e) {
      AppLogger.e('保存卡片图片失败: $e', error: e, source: 'AICardGeneration');
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
      AppLogger.e('检查相册权限失败: $e', error: e, source: 'AICardGeneration');
      return false;
    }
  }

  /// 批量保存卡片为图片
  Future<List<String>> saveMultipleCardsAsImages(
    List<GeneratedCard> cards, {
    int width = 400,
    int height = 600,
    Function(int current, int total)? onProgress,
    double scaleFactor = 2.0,
    ExportRenderMode renderMode = ExportRenderMode.contain,
    BuildContext? context,
  }) async {
    final savedFiles = <String>[];

    for (int i = 0; i < cards.length; i++) {
      try {
        final fileName = await saveCardAsImage(
          cards[i],
          width: width,
          height: height,
          scaleFactor: scaleFactor,
          renderMode: renderMode,
          context: context,
          customName:
              '心迹_Card_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
        );
        savedFiles.add(fileName);

        onProgress?.call(i + 1, cards.length);
      } catch (e) {
        AppLogger.e(
          '批量保存第${i + 1}张卡片失败: $e',
          error: e,
          source: 'AICardGeneration',
        );
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

  /// 智能选择最适合的提示词（改进：增加随机性和变化）
  String _selectBestPrompt(Quote note, String? customStyle) {
    // 分析内容特征
    final content = note.content.toLowerCase();
    final hasAuthor =
        note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty;

    // 如果指定了自定义风格，使用对应的提示词
    if (customStyle != null) {
      switch (customStyle) {
        case 'creative':
          return AICardPrompts.randomStylePosterPrompt(
            content: note.content,
            author: note.sourceAuthor,
            date: _formatDate(note.date),
            location: note.location,
            weather: note.weather,
            temperature: note.temperature,
            dayPeriod: note.dayPeriod,
            source: note.fullSource,
          );
        case 'intelligent':
          return AICardPrompts.intelligentCardPrompt(
            content: note.content,
            author: note.sourceAuthor,
            date: _formatDate(note.date),
            location: note.location,
            weather: note.weather,
            temperature: note.temperature,
            dayPeriod: note.dayPeriod,
            source: note.fullSource,
          );
        case 'visual':
          return AICardPrompts.contentAwareVisualPrompt(
            content: note.content,
            author: note.sourceAuthor,
            date: _formatDate(note.date),
            location: note.location,
            weather: note.weather,
            temperature: note.temperature,
            dayPeriod: note.dayPeriod,
            source: note.fullSource,
          );
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
        return AICardPrompts.intelligentCardPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      } else {
        return AICardPrompts.randomStylePosterPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      }
    }

    // 2. 检查是否为技术/学习内容（40%视觉增强，30%智能，30%随机）
    final techKeywords = ['代码', '编程', '算法', '技术', '开发', '学习', '知识', '方法', '原理'];
    if (techKeywords.any((keyword) => content.contains(keyword))) {
      if (random < 40) {
        return AICardPrompts.contentAwareVisualPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      } else if (random < 70) {
        return AICardPrompts.intelligentCardPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      } else {
        return AICardPrompts.randomStylePosterPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      }
    }

    // 3. 检查是否为情感/生活内容（50%随机海报，50%视觉增强）
    final emotionalKeywords = ['感受', '心情', '生活', '感悟', '体验', '回忆', '梦想', '希望'];
    if (emotionalKeywords.any((keyword) => content.contains(keyword))) {
      if (random < 50) {
        return AICardPrompts.randomStylePosterPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      } else {
        return AICardPrompts.contentAwareVisualPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      }
    }

    // 4. 根据内容长度和随机性选择
    if (note.content.length > 100) {
      // 长内容：40%随机海报，30%智能，30%视觉
      if (random < 40) {
        return AICardPrompts.randomStylePosterPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      } else if (random < 70) {
        return AICardPrompts.intelligentCardPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      } else {
        return AICardPrompts.contentAwareVisualPrompt(
          content: note.content,
          author: note.sourceAuthor,
          date: _formatDate(note.date),
          location: note.location,
          weather: note.weather,
          temperature: note.temperature,
          dayPeriod: note.dayPeriod,
          source: note.fullSource,
        );
      }
    }

    // 5. 默认使用三种提示词随机选择（各33%）
    if (random < 33) {
      return AICardPrompts.randomStylePosterPrompt(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
        location: note.location,
        weather: note.weather,
        temperature: note.temperature,
        dayPeriod: note.dayPeriod,
        source: note.fullSource,
      );
    } else if (random < 66) {
      return AICardPrompts.intelligentCardPrompt(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
        location: note.location,
        weather: note.weather,
        temperature: note.temperature,
        dayPeriod: note.dayPeriod,
        source: note.fullSource,
      );
    } else {
      return AICardPrompts.contentAwareVisualPrompt(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
        location: note.location,
        weather: note.weather,
        temperature: note.temperature,
        dayPeriod: note.dayPeriod,
        source: note.fullSource,
      );
    }
  }

  /// 如果AI未输出底部元数据，则添加一个简单信息块
  String _ensureMetadataPresence(
    String svg, {
    required String? date,
    String? location,
    String? weather,
    String? temperature,
    String? author,
    String? source,
    String? dayPeriod,
  }) {
    final lower = svg.toLowerCase();
    final hasDate = date != null && lower.contains(date.toLowerCase());
    final hasLocation =
        location != null && lower.contains(location.toLowerCase());
    final hasWeather = weather != null && lower.contains(weather.toLowerCase());
    final need = !(hasDate || hasLocation || hasWeather);
    if (!need) {
      return svg; // 已有至少一个信息
    }
    // 简单插入在 </svg> 前
    final metaParts = <String>[];
    // 规则：程序自动补全 -> 统一中文本地化
    final localizedWeather = _localizeWeather(weather);
    final localizedDayPeriod = _localizeDayPeriod(dayPeriod);

    if (date != null) metaParts.add(date); // 已是中文格式化
    if (location != null) metaParts.add(location); // 用户输入不改动
    if (localizedWeather != null) {
      metaParts.add(
        temperature != null
            ? '$localizedWeather $temperature'
            : localizedWeather,
      );
    }
    if (author != null) metaParts.add(author);
    if (source != null && source != author) metaParts.add(source);
    if (localizedDayPeriod != null) metaParts.add(localizedDayPeriod);
    metaParts.add('心迹');
    final meta = metaParts.join(' · ');
    final injection =
        '<text x="200" y="590" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#ffffff" fill-opacity="0.75">${_escape(meta)}</text>';
    final idx = svg.lastIndexOf('</svg>');
    if (idx == -1) {
      return svg; // 非法结构保持原样
    }
    return svg.substring(0, idx) + injection + svg.substring(idx);
  }

  String _escape(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // 检测是否包含中文
  bool _containsChinese(String text) =>
      RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

  // 天气本地化映射
  static const Map<String, String> _weatherMap = {
    // 基础天气类型
    'clear': '晴',
    'sunny': '晴',
    'partly_cloudy': '少云',
    'cloudy': '多云',
    'overcast': '阴',
    'fog': '雾',
    'haze': '霾',
    'windy': '有风',

    // 雨类天气
    'drizzle': '毛毛雨',
    'light rain': '小雨',
    'rain': '雨',
    'moderate rain': '中雨',
    'heavy rain': '大雨',
    'freezing_rain': '冻雨',
    'rain_shower': '阵雨',
    'thunderstorm': '雷雨',
    'thunderstorm_heavy': '雷暴雨',

    // 雪类天气
    'snow': '雪',
    'light snow': '小雪',
    'heavy snow': '大雪',
    'snow_grains': '雪粒',
    'snow_shower': '阵雪',
    'sleet': '雨夹雪',

    // 大写变体（AI可能生成的大小写不同）
    'Clear': '晴',
    'Sunny': '晴',
    'Partly_cloudy': '少云',
    'Cloudy': '多云',
    'Overcast': '阴',
    'Fog': '雾',
    'Haze': '霾',
    'Windy': '有风',
    'Drizzle': '毛毛雨',
    'Light rain': '小雨',
    'Rain': '雨',
    'Moderate rain': '中雨',
    'Heavy rain': '大雨',
    'Freezing_rain': '冻雨',
    'Rain_shower': '阵雨',
    'Thunderstorm': '雷雨',
    'Thunderstorm_heavy': '雷暴雨',
    'Snow': '雪',
    'Light snow': '小雪',
    'Heavy snow': '大雪',
    'Snow_grains': '雪粒',
    'Snow_shower': '阵雪',
    'Sleet': '雨夹雪',

    // 其他格式变体
    'rainy': '雨',
    'snowy': '雪',
    'stormy': '暴风雨',
  };

  String? _localizeWeather(String? weather) {
    if (weather == null || weather.trim().isEmpty) return null;
    final w = weather.toLowerCase();
    return _weatherMap[w] ?? weather; // 未命中保持原样（可能已是中文）
  }

  // 时间段本地化
  static const Map<String, String> _dayPeriodMap = {
    'moring': '晨间', // 兼容常见拼写错误
    'morning': '晨间',
    'noon': '正午',
    'afternoon': '午后',
    'evening': '傍晚',
    'night': '夜晚',
    'dawn': '黎明',
    'dusk': '黄昏',
    'late night': '深夜',
  };

  String? _localizeDayPeriod(String? period) {
    if (period == null || period.trim().isEmpty) return null;
    final p = period.toLowerCase();
    return _dayPeriodMap[p] ?? period; // 未命中保持原样（可能已是中文）
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

    final inferredSize = _inferSvgIntrinsicSize(normalized);

    // 移除现有的viewBox、width、height、preserveAspectRatio属性，避免AI返回的百分比尺寸导致错位
    normalized = normalized
        .replaceAll(RegExp(r'\s+viewBox="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+width="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+height="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+preserveAspectRatio="[^"]*"'), '');

    // 统一设置标准属性: 仅设置viewBox与保留比例，不强制width/height，让预览与导出一致
    normalized = normalized.replaceFirst(
      '<svg',
      '<svg viewBox="0 0 ${inferredSize.$1} ${inferredSize.$2}" preserveAspectRatio="xMidYMid meet"',
    );

    return normalized;
  }

  /// 推断SVG内在尺寸，忽略百分比/无效尺寸，防止viewBox被错误设置为100导致裁剪
  (String, String) _inferSvgIntrinsicSize(String svgContent) {
    // 1) 优先使用合法的viewBox
    final viewBoxMatch = RegExp(r'viewBox="([^"]+)"').firstMatch(svgContent);
    if (viewBoxMatch != null) {
      final parts = viewBoxMatch.group(1)!.split(RegExp(r'[\s,]+'));
      if (parts.length == 4 && parts.every((p) => double.tryParse(p) != null)) {
        return (parts[2], parts[3]);
      }
    }

    // 2) 解析根节点的width/height（忽略百分比）
    double? w = _parseNumericDimension(
      RegExp(r'width="([^"]+)"').firstMatch(svgContent)?.group(1),
    );
    double? h = _parseNumericDimension(
      RegExp(r'height="([^"]+)"').firstMatch(svgContent)?.group(1),
    );

    // 3) 如果根尺寸不可靠，尝试从首个rect推断（通常为背景矩形）
    if (w == null || h == null) {
      final rectMatch =
          RegExp(r'<rect[^>]*width="([^"]+)"[^>]*height="([^"]+)"')
              .firstMatch(svgContent);
      if (rectMatch != null) {
        w = _parseNumericDimension(rectMatch.group(1)) ?? w;
        h = _parseNumericDimension(rectMatch.group(2)) ?? h;
      }
    }

    // 4) 回退默认值
    w ??= 400;
    h ??= 600;

    return (w.toString(), h.toString());
  }

  double? _parseNumericDimension(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    if (raw.contains('%')) return null;
    final cleaned = raw.replaceAll(RegExp('[^0-9.-]'), '');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
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
        AppLogger.w('发现不安全的SVG元素: $dangerous', source: 'AICardGeneration');
        return false;
      }
    }

    return true;
  }
}
