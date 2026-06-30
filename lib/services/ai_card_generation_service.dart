import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/widgets.dart';

// 条件导入：Web平台使用stub实现，其他平台使用gal
import '../utils/stub_implementations.dart'
    if (dart.library.io) 'package:gal/gal.dart' as gal;
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../utils/app_logger.dart';
import 'ai_service.dart';
import 'settings_service.dart';
import 'svg_to_image_service.dart';

import 'ai_card_generation_strategies/ai_card_generation_strategy.dart';
import 'ai_card_generation_strategies/fallback_card_generation_strategy.dart';

/// AI卡片生成服务
class AICardGenerationService {
  final SettingsService _settingsService;
  final AiCardGenerationStrategy _aiStrategy;
  final FallbackCardGenerationStrategy _fallbackStrategy;

  AICardGenerationService(AIService aiService, this._settingsService)
      : _aiStrategy = AiCardGenerationStrategy(aiService, _settingsService),
        _fallbackStrategy = FallbackCardGenerationStrategy();

  /// 获取当前语言代码 (zh, en, ja, fr, etc.)
  String get _currentLanguageCode {
    final localeCode = _settingsService.localeCode;
    String lang;

    // 如果未设置则跟随系统
    if (localeCode == null || localeCode.isEmpty) {
      if (kIsWeb) {
        lang = 'zh'; // Web 默认中文
      } else {
        // Platform.localeName 格式可能是 'en_US', 'zh_CN'
        lang = Platform.localeName.split('_')[0].toLowerCase();
      }
    } else {
      lang = localeCode.split('_')[0].toLowerCase();
    }

    // 简单规范化
    if (lang == 'zh-hans' || lang == 'zh-hant') return 'zh';
    return lang;
  }

  /// 为单条笔记生成卡片（AI智能生成 + 模板回退）
  Future<GeneratedCard> generateCard({
    required String brandName,
    required Quote note,
    String? customStyle,
    bool isRegeneration = false,
    CardType? excludeType,
  }) async {
    final languageCode = _currentLanguageCode;

    // 如果用户关闭了 AI 生成功能，则直接使用模板（功能仍可用，只是没有AI增强）
    if (!isEnabled) {
      AppLogger.i('AI卡片生成已关闭，使用本地模板生成', source: 'AICardGeneration');
      return _fallbackStrategy.generate(
        note: note,
        brandName: brandName,
        languageCode: languageCode,
        customStyle: customStyle,
        isRegeneration: isRegeneration,
        excludeType: excludeType,
      );
    }

    try {
      return await _aiStrategy.generate(
        note: note,
        brandName: brandName,
        languageCode: languageCode,
        customStyle: customStyle,
        isRegeneration: isRegeneration,
        excludeType: excludeType,
      );
    } catch (e) {
      AppLogger.w('AI生成失败，使用回退模板: $e', source: 'AICardGeneration');
      return _fallbackStrategy.generate(
        note: note,
        brandName: brandName,
        languageCode: languageCode,
        customStyle: customStyle,
        isRegeneration: isRegeneration,
        excludeType: excludeType,
      );
    }
  }

  /// 批量为多条笔记生成卡片（主要用于精选内容展示）
  Future<List<GeneratedCard>> generateFeaturedCards({
    required String brandName,
    required List<Quote> notes,
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

        final card = await generateCard(note: note, brandName: brandName);
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
          AppLogger.e('批量生成失败率过高，停止生成', source: 'AICardGenerationService');
          break;
        }

        continue; // 跳过失败的卡片，继续生成其他卡片
      }
    }

    if (cards.isEmpty && errors.isNotEmpty) {
      throw Exception('批量生成完全失败: ${errors.join('; ')}');
    }

    AppLogger.i(
      '批量生成完成: 成功${cards.length}张，失败${errors.length}张',
      source: 'AICardGeneration',
    );

    return cards;
  }

  /// 将生成的卡片保存为图片（带权限检查）
  Future<String> saveCardAsImage(
    GeneratedCard card, {
    int width = 400,
    int height = 600,
    String? customName,
    String fileNamePrefix = 'ThoughtEcho_Card',
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
          : '${fileNamePrefix}_$timestamp';

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

  /// 检查AI卡片生成功能是否启用
  bool get isEnabled {
    // 从设置服务中获取AI卡片生成开关状态
    return _settingsService.aiCardGenerationEnabled;
  }
}
