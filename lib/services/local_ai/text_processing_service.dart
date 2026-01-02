/// 文本处理服务
///
/// 使用 Gemma 2B LLM 进行文本纠错、来源识别、标签推荐等

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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

  /// Gemma 推理会话（若创建成功则复用）
  dynamic _gemmaSession;

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
    // gemma 模型由 flutter_gemma 管理：这里仍保留 ModelManager 的标记判断，
    // 同时允许在实际调用时通过 flutter_gemma 探测可用性。
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
        logInfo('LLM 模型未下载，文本处理功能使用基础实现', source: 'TextProcessingService');
      } else {
        // 尝试初始化 flutter_gemma
        await _initializeGemma();
      }

      _initialized = true;
      logInfo('文本处理服务初始化完成', source: 'TextProcessingService');
    } catch (e) {
      logError('文本处理服务初始化失败: $e', source: 'TextProcessingService');
      // 不抛出错误，允许服务以降级模式运行
      _initialized = true;
    }
  }

  /// 初始化 flutter_gemma
  Future<void> _initializeGemma() async {
    try {
      // flutter_gemma 新版采用静态 API，需要先 initialize。
      // huggingFaceToken 为可选参数（用于 gated 模型），此处不传以避免硬编码密钥。
      FlutterGemma.initialize();

      // 尝试获取当前可用模型（如果未安装/不可用会抛出异常）
      final model = await FlutterGemma.getActiveModel(maxTokens: 512);
      _gemmaSession = await model.createSession();
      _modelLoaded = true;
      logInfo('Gemma 模型会话已准备就绪', source: 'TextProcessingService');
    } catch (e) {
      logError('初始化 Gemma 失败: $e', source: 'TextProcessingService');
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

    try {
      logInfo('加载 LLM 模型', source: 'TextProcessingService');

      FlutterGemma.initialize();
      final model = await FlutterGemma.getActiveModel(maxTokens: 512);
      _gemmaSession = await model.createSession();

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
      _gemmaSession = null;
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
      if (_modelLoaded) {
        // 使用 Gemma 进行文本纠错
        final prompt = '''请修正以下文本中的错别字和语法错误，只返回修正后的文本：

$text''';

        final response = await _tryGemmaPrompt(prompt);
        if (response != null && response.trim().isNotEmpty) {
          final corrected = response.trim();
          final corrections = _detectCorrections(text, corrected);
          return TextCorrectionResult(
            originalText: text,
            correctedText: corrected,
            corrections: corrections,
            hasChanges: text != corrected,
          );
        }
      }

      // 降级：返回无修改
      return TextCorrectionResult.noChange(text);
    } catch (e) {
      logError('AI 纠错失败: $e', source: 'TextProcessingService');
      return TextCorrectionResult.noChange(text);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 检测修正位置
  List<TextCorrection> _detectCorrections(String original, String corrected) {
    // 简单的差异检测
    final corrections = <TextCorrection>[];
    // TODO: 实现更精确的差异检测
    if (original != corrected) {
      corrections.add(TextCorrection(
        original: original,
        corrected: corrected,
        position: 0,
        reason: null,
      ));
    }
    return corrections;
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
      if (_modelLoaded) {
        // 使用 Gemma 进行来源识别
        final prompt = '''分析以下文本的来源类型（书籍、诗歌、名言、原创等），并提取作者和作品名称（如果有）。只返回JSON格式：
{"type":"类型","author":"作者","work":"作品名"}

文本：$text''';

        final response = await _tryGemmaPrompt(prompt);
        
        if (response != null && response.isNotEmpty) {
          // 尝试解析 JSON 响应
          final result = _parseSourceResponse(response);
          if (result != null) {
            return result;
          }
        }
      }

      // 降级：使用简单模式匹配
      return _simpleSourceRecognition(text);
    } catch (e) {
      logError('来源识别失败: $e', source: 'TextProcessingService');
      return _simpleSourceRecognition(text);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 解析来源识别响应
  SourceRecognitionResult? _parseSourceResponse(String response) {
    try {
      // 提取 JSON 部分
      final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(response);
      if (jsonMatch == null) return null;

      final jsonStr = jsonMatch.group(0)!;
      // 简单解析
      final typeMatch = RegExp(r'"type"\s*:\s*"([^"]*)"').firstMatch(jsonStr);
      final authorMatch = RegExp(r'"author"\s*:\s*"([^"]*)"').firstMatch(jsonStr);
      final workMatch = RegExp(r'"work"\s*:\s*"([^"]*)"').firstMatch(jsonStr);

      final typeStr = typeMatch?.group(1) ?? '';
      SourceType type = SourceType.unknown;
      
      if (typeStr.contains('书') || typeStr.contains('book')) {
        type = SourceType.book;
      } else if (typeStr.contains('诗') || typeStr.contains('poem')) {
        type = SourceType.poetry;
      } else if (typeStr.contains('名言') || typeStr.contains('quote')) {
        type = SourceType.quote;
      } else if (typeStr.contains('原创') || typeStr.contains('original')) {
        type = SourceType.original;
      }

      return SourceRecognitionResult(
        type: type,
        author: authorMatch?.group(1),
        work: workMatch?.group(1),
        confidence: 0.8,
      );
    } catch (e) {
      return null;
    }
  }

  /// 简单的模式匹配来源识别
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
      if (_modelLoaded) {
        // 使用 Gemma 进行标签推荐
        final prompt = '''为以下文本推荐3-5个标签，只返回标签列表（用逗号分隔）：

$content''';

          final response = await _tryGemmaPrompt(prompt);
        
        if (response != null && response.isNotEmpty) {
          final tags = response
              .split(RegExp(r'[,，、]'))
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty && t.length < 20)
              .take(5)
            .map((t) => SuggestedTag(name: t, confidence: 0.7))
              .toList();

          if (tags.isNotEmpty) {
            return TagSuggestionResult(
              analyzedText: content,
              tags: tags,
            );
          }
        }
      }

      // 降级：返回空标签
      return TagSuggestionResult(
        analyzedText: content,
        tags: const [],
      );
    } catch (e) {
      logError('标签推荐失败: $e', source: 'TextProcessingService');
      return TagSuggestionResult.empty;
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
      if (_modelLoaded) {
        // 使用 Gemma 进行分类
        final prompt = '''将以下文本分类为以下类别之一：日记、摘录、感悟、笔记、想法。只返回类别名称：

$content''';

        final response = await _tryGemmaPrompt(prompt);
        
        if (response != null && response.isNotEmpty) {
          final classification = _parseClassification(response);
          if (classification != null) {
            return classification;
          }
        }
      }

      // 降级：使用简单分类
      return _simpleClassification(content);
    } catch (e) {
      logError('笔记分类失败: $e', source: 'TextProcessingService');
      return _simpleClassification(content);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 解析分类响应
  ClassificationResult? _parseClassification(String response) {
    final lower = response.toLowerCase();
    
    if (lower.contains('日记') || lower.contains('diary')) {
      return const ClassificationResult(
        classification: NoteClassification.diary,
        confidence: 0.8,
      );
    }
    if (lower.contains('摘录') || lower.contains('excerpt')) {
      return const ClassificationResult(
        classification: NoteClassification.excerpt,
        confidence: 0.8,
      );
    }
    if (lower.contains('感悟') || lower.contains('insight')) {
      return const ClassificationResult(
        classification: NoteClassification.insight,
        confidence: 0.8,
      );
    }
    if (lower.contains('想法') || lower.contains('thought')) {
      return const ClassificationResult(
        classification: NoteClassification.thought,
        confidence: 0.8,
      );
    }
    
    return null;
  }

  /// 简单的关键词分类
  ClassificationResult _simpleClassification(String content) {
    final lowerContent = content.toLowerCase();

    if (lowerContent.contains('今天') ||
        lowerContent.contains('昨天') ||
        lowerContent.contains('diary')) {
      return const ClassificationResult(
        classification: NoteClassification.diary,
        confidence: 0.5,
      );
    }

    if (lowerContent.contains('摘录') ||
        lowerContent.contains('引用') ||
        content.contains('《') ||
        content.contains('》')) {
      return const ClassificationResult(
        classification: NoteClassification.excerpt,
        confidence: 0.6,
      );
    }

    if (lowerContent.contains('感悟') ||
        lowerContent.contains('思考') ||
        lowerContent.contains('insight')) {
      return const ClassificationResult(
        classification: NoteClassification.insight,
        confidence: 0.5,
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
      if (_modelLoaded) {
        // 使用 Gemma 进行情绪检测
        final prompt = '''分析以下文本的情绪，返回主要情绪（开心、悲伤、愤怒、恐惧、惊讶、平静）和强度（0-1）。格式：情绪,强度

$content''';

        final response = await _tryGemmaPrompt(prompt);
        
        if (response != null && response.isNotEmpty) {
          final emotion = _parseEmotionResponse(response);
          if (emotion != null) {
            return emotion;
          }
        }
      }

      // 降级：使用简单检测
      return _simpleEmotionDetection(content);
    } catch (e) {
      logError('情绪检测失败: $e', source: 'TextProcessingService');
      return _simpleEmotionDetection(content);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 解析情绪响应
  EmotionResult? _parseEmotionResponse(String response) {
    final lower = response.toLowerCase();
    
    EmotionType? emotion;
    double intensity = 0.5;

    if (lower.contains('开心') || lower.contains('happy') || lower.contains('joy')) {
      emotion = EmotionType.happy;
    } else if (lower.contains('悲伤') || lower.contains('sad')) {
      emotion = EmotionType.sad;
    } else if (lower.contains('愤怒') || lower.contains('angry')) {
      emotion = EmotionType.angry;
    } else if (lower.contains('恐惧') || lower.contains('fear')) {
      emotion = EmotionType.fear;
    } else if (lower.contains('惊讶') || lower.contains('surprise')) {
      emotion = EmotionType.surprise;
    } else if (lower.contains('平静') || lower.contains('calm') || lower.contains('neutral')) {
      emotion = EmotionType.neutral;
    }

    // 尝试提取强度
    final intensityMatch = RegExp(r'(\d+\.?\d*)').firstMatch(response);
    if (intensityMatch != null) {
      final parsed = double.tryParse(intensityMatch.group(1)!);
      if (parsed != null && parsed <= 1.0) {
        intensity = parsed;
      } else if (parsed != null && parsed <= 100) {
        intensity = parsed / 100;
      }
    }

    if (emotion != null) {
      return EmotionResult(
        primaryEmotion: emotion,
        intensity: intensity,
      );
    }

    return null;
  }

  /// 简单的情绪词检测
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
      );
    } else if (negativeCount > positiveCount) {
      return const EmotionResult(
        primaryEmotion: EmotionType.sad,
        intensity: 0.6,
      );
    }

    return EmotionResult.empty;
  }

  @override
  void dispose() {
    unloadModel();
    super.dispose();
  }

  /// 尝试通过 Gemma 执行一次提示词推理。
  ///
  /// flutter_gemma 的会话 API 在不同版本可能略有差异，因此这里做尽量稳健的调用：
  /// - 如果 session 支持 getResponse(prompt: ...)，优先走该路径
  /// - 否则尝试 setPrompt / addQuery 等常见方式
  ///
  /// 任意失败都会返回 null，并由上层走降级逻辑。
  Future<String?> _tryGemmaPrompt(String prompt) async {
    if (!_modelLoaded) return null;

    try {
      // 兜底：如果 session 丢失则重新创建
      if (_gemmaSession == null) {
        FlutterGemma.initialize();
        final model = await FlutterGemma.getActiveModel(maxTokens: 512);
        _gemmaSession = await model.createSession();
      }

      final session = _gemmaSession;

      // 1) 常见：getResponse(prompt: ...)
      try {
        final dynamic resp = await (session as dynamic).getResponse(prompt: prompt);
        if (resp is String) return resp;
      } catch (_) {
        // ignore and try other patterns
      }

      // 2) 常见：setPrompt / prompt 属性 + getResponse()
      try {
        await (session as dynamic).setPrompt(prompt);
        final dynamic resp = await (session as dynamic).getResponse();
        if (resp is String) return resp;
      } catch (_) {
        // ignore
      }

      // 3) 常见：addQuery + getResponse()
      try {
        await (session as dynamic).addQuery(prompt);
        final dynamic resp = await (session as dynamic).getResponse();
        if (resp is String) return resp;
      } catch (_) {
        // ignore
      }

      return null;
    } catch (e) {
      logError('Gemma 推理失败: $e', source: 'TextProcessingService');
      return null;
    }
  }
}
