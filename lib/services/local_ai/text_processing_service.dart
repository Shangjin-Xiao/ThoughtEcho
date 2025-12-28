/// 文本处理服务
///
/// 使用 Gemma 2B LLM 进行文本纠错、来源识别、标签推荐等

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/text_processing_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';

/// 文本处理服务
class TextProcessingService extends ChangeNotifier {
  static TextProcessingService? _instance;

  /// 单例实例
  static TextProcessingService get instance {
    _instance ??= TextProcessingService._();
    return _instance!;
  }

  TextProcessingService._();

  /// 模型管理器
  final ModelManager _modelManager = ModelManager.instance;

  /// 是否已初始化
  bool _initialized = false;

  /// LLM 模型是否已加载
  bool _modelLoaded = false;

  /// 当前是否正在处理
  bool _isProcessing = false;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 模型是否已加载
  bool get isModelLoaded => _modelLoaded;

  /// 是否正在处理
  bool get isProcessing => _isProcessing;

  /// 检查 LLM 模型是否可用
  bool get isModelAvailable {
    return _modelManager.isModelDownloaded('gemma-2b');
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 确保模型管理器已初始化
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 检查是否有可用的 LLM 模型
      if (!isModelAvailable) {
        logInfo('LLM 模型未下载，文本处理功能暂不可用', source: 'TextProcessingService');
      }

      _initialized = true;
      logInfo('文本处理服务初始化完成', source: 'TextProcessingService');
    } catch (e) {
      logError('文本处理服务初始化失败: $e', source: 'TextProcessingService');
      rethrow;
    }
  }

  /// 加载 LLM 模型
  Future<void> loadModel() async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (_modelLoaded) {
      logDebug('LLM 模型已加载', source: 'TextProcessingService');
      return;
    }

    if (!isModelAvailable) {
      throw Exception('LLM 模型未下载，请先下载 Gemma 2B 模型');
    }

    try {
      // TODO: 集成 flutter_gemma 加载 Gemma 2B 模型
      logInfo('加载 LLM 模型（占位实现）', source: 'TextProcessingService');

      // 模拟加载过程
      await Future.delayed(const Duration(seconds: 2));

      _modelLoaded = true;
      notifyListeners();

      logInfo('LLM 模型加载完成', source: 'TextProcessingService');
    } catch (e) {
      logError('加载 LLM 模型失败: $e', source: 'TextProcessingService');
      rethrow;
    }
  }

  /// 卸载模型
  Future<void> unloadModel() async {
    if (!_modelLoaded) return;

    try {
      // TODO: 卸载 Gemma 模型释放内存
      _modelLoaded = false;
      notifyListeners();

      logInfo('LLM 模型已卸载', source: 'TextProcessingService');
    } catch (e) {
      logError('卸载 LLM 模型失败: $e', source: 'TextProcessingService');
    }
  }

  /// AI 文本纠错
  Future<TextCorrectionResult> correctText(String text) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (text.trim().isEmpty) {
      return TextCorrectionResult.noChange(text);
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // TODO: 集成 flutter_gemma 进行文本纠错
      logInfo('AI 纠错（占位实现）: ${text.substring(0, text.length.clamp(0, 50))}...', source: 'TextProcessingService');

      // 模拟处理
      await Future.delayed(const Duration(milliseconds: 500));

      // 返回无修改的结果（占位）
      return TextCorrectionResult.noChange(text);
    } catch (e) {
      logError('AI 纠错失败: $e', source: 'TextProcessingService');
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 识别文本来源
  Future<SourceRecognitionResult> recognizeSource(String text) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (text.trim().isEmpty) {
      return SourceRecognitionResult.empty;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // TODO: 集成 flutter_gemma 进行来源识别
      logInfo('识别来源（占位实现）: ${text.substring(0, text.length.clamp(0, 50))}...', source: 'TextProcessingService');

      // 模拟处理
      await Future.delayed(const Duration(milliseconds: 500));

      // 简单的模式匹配识别（占位）
      final result = _simpleSourceRecognition(text);

      return result;
    } catch (e) {
      logError('来源识别失败: $e', source: 'TextProcessingService');
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 简单的模式匹配来源识别（占位实现）
  SourceRecognitionResult _simpleSourceRecognition(String text) {
    // 检测常见的引用格式
    final authorPattern = RegExp(r'[—–-]\s*([^，。、\n]+)$');
    final match = authorPattern.firstMatch(text);

    if (match != null) {
      return SourceRecognitionResult(
        type: SourceType.quote,
        author: match.group(1)?.trim(),
        confidence: 0.6,
      );
    }

    // 检测书名号
    final bookPattern = RegExp(r'《([^》]+)》');
    final bookMatch = bookPattern.firstMatch(text);

    if (bookMatch != null) {
      return SourceRecognitionResult(
        type: SourceType.book,
        work: bookMatch.group(1),
        confidence: 0.7,
      );
    }

    return SourceRecognitionResult.empty;
  }

  /// 智能标签推荐
  Future<TagSuggestionResult> suggestTags(String content) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (content.trim().isEmpty) {
      return TagSuggestionResult.empty;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // TODO: 集成 flutter_gemma 进行智能标签推荐
      logInfo('标签推荐（占位实现）', source: 'TextProcessingService');

      // 模拟处理
      await Future.delayed(const Duration(milliseconds: 300));

      // 返回空结果（占位）
      return TagSuggestionResult(
        analyzedText: content,
        tags: const [],
      );
    } catch (e) {
      logError('标签推荐失败: $e', source: 'TextProcessingService');
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 笔记分类
  Future<ClassificationResult> classifyNote(String content) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (content.trim().isEmpty) {
      return ClassificationResult.empty;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // TODO: 集成 flutter_gemma 进行笔记分类
      logInfo('笔记分类（占位实现）', source: 'TextProcessingService');

      // 模拟处理
      await Future.delayed(const Duration(milliseconds: 300));

      // 简单的关键词分类（占位）
      final classification = _simpleClassification(content);

      return classification;
    } catch (e) {
      logError('笔记分类失败: $e', source: 'TextProcessingService');
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 简单的关键词分类（占位实现）
  ClassificationResult _simpleClassification(String content) {
    final lowerContent = content.toLowerCase();

    if (lowerContent.contains('今天') ||
        lowerContent.contains('昨天') ||
        lowerContent.contains('diary')) {
      return const ClassificationResult(
        classification: NoteClassification.diary,
        confidence: 0.5,
        reason: '包含日期相关词汇',
      );
    }

    if (lowerContent.contains('摘录') ||
        lowerContent.contains('引用') ||
        content.contains('《') ||
        content.contains('》')) {
      return const ClassificationResult(
        classification: NoteClassification.excerpt,
        confidence: 0.6,
        reason: '包含引用格式',
      );
    }

    if (lowerContent.contains('感悟') ||
        lowerContent.contains('思考') ||
        lowerContent.contains('insight')) {
      return const ClassificationResult(
        classification: NoteClassification.insight,
        confidence: 0.5,
        reason: '包含感悟相关词汇',
      );
    }

    return const ClassificationResult(
      classification: NoteClassification.note,
      confidence: 0.3,
    );
  }

  /// 情绪检测
  Future<EmotionResult> detectEmotion(String content) async {
    if (!_initialized) {
      throw Exception('服务未初始化');
    }

    if (content.trim().isEmpty) {
      return EmotionResult.empty;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // TODO: 集成 flutter_gemma 进行情绪检测
      logInfo('情绪检测（占位实现）', source: 'TextProcessingService');

      // 模拟处理
      await Future.delayed(const Duration(milliseconds: 300));

      // 简单的情绪词检测（占位）
      final emotion = _simpleEmotionDetection(content);

      return emotion;
    } catch (e) {
      logError('情绪检测失败: $e', source: 'TextProcessingService');
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 简单的情绪词检测（占位实现）
  EmotionResult _simpleEmotionDetection(String content) {
    final positiveWords = ['开心', '快乐', '高兴', '幸福', '感谢', 'happy', 'joy', 'grateful'];
    final negativeWords = ['难过', '伤心', '悲伤', '失望', '愤怒', 'sad', 'angry', 'disappointed'];

    int positiveCount = 0;
    int negativeCount = 0;

    for (final word in positiveWords) {
      if (content.contains(word)) positiveCount++;
    }

    for (final word in negativeWords) {
      if (content.contains(word)) negativeCount++;
    }

    if (positiveCount > negativeCount) {
      return const EmotionResult(
        primaryEmotion: EmotionType.happy,
        intensity: 0.6,
        summary: '检测到积极情绪词汇',
      );
    } else if (negativeCount > positiveCount) {
      return const EmotionResult(
        primaryEmotion: EmotionType.sad,
        intensity: 0.6,
        summary: '检测到消极情绪词汇',
      );
    }

    return EmotionResult.empty;
  }

  @override
  void dispose() {
    unloadModel();
    super.dispose();
  }
}
