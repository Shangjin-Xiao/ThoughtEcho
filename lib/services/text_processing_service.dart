import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/services/model_manager.dart';

enum SourceType {
  original,
  excerpt,
  unknown,
}

class EmotionResult {
  final String primaryEmotion;
  final double confidence;

  EmotionResult(this.primaryEmotion, this.confidence);
}

class TextProcessingService {
  static final TextProcessingService _instance = TextProcessingService._internal();
  static TextProcessingService get instance => _instance;

  TextProcessingService._internal();

  InferenceModel? _model;

  Future<void> initialize() async {
    try {
      if (_model == null) {
        if (await ModelManager.instance.isModelReady(AppModelType.gemma)) {
           final modelPath = await ModelManager.instance.getModelPath(AppModelType.gemma);
           final gemma = FlutterGemmaPlugin.instance;

           try {
             // Use dynamic invocation to attempt loading model from path
             // FlutterGemma 0.10.2's ModelFileManager usually has loadModel(String)
             await (gemma.modelManager as dynamic).loadModel(modelPath);
           } catch (e) {
             UnifiedLogService.instance.log(UnifiedLogLevel.warning, 'Model load warning: $e', source: 'TextProcessing');
           }

           // Create model instance
           // ModelType here refers to FlutterGemma's enum, which likely has 'gemma' or 'gemmaIt'
           // We use ModelType.gemma (from package) if available, otherwise fallback.
           // Since we imported flutter_gemma, ModelType refers to the package enum.
           // AppModelType refers to our local enum.
           _model = await gemma.createModel(modelType: ModelType.gemmaIt);
        }
      }
    } catch (e) {
      UnifiedLogService.instance.log(UnifiedLogLevel.error, 'Gemma init failed: $e', source: 'TextProcessing');
    }
  }

  Future<String> _processWithGemma(String prompt) async {
    if (_model == null) {
      await initialize();
      if (_model == null) return '';
    }

    InferenceModelSession? session;
    try {
      session = await _model!.createSession();
      await session.addQueryChunk(Message(text: prompt));
      return await session.getResponse();
    } catch (e) {
      UnifiedLogService.instance.log(UnifiedLogLevel.error, 'Gemma processing failed: $e', source: 'TextProcessing');
      return '';
    } finally {
      session?.close();
    }
  }

  /// 使用 Gemma 模型进行文本纠错
  Future<String> correctText(String text) async {
    if (text.isEmpty) return text;
    final prompt = "Please correct the following text for spelling and grammar errors, keeping the original meaning and tone. Output only the corrected text:\n$text";
    final result = await _processWithGemma(prompt);
    return result.isEmpty ? text : result.trim();
  }

  /// 识别来源 (作者/作品)
  Future<SourceType> recognizeSource(String text) async {
    if (text.isEmpty) return SourceType.unknown;
    final prompt = "Analyze if the following text is likely an excerpt from a book/movie/song or an original thought. Reply with 'EXCERPT' or 'ORIGINAL' or 'UNKNOWN'.\nText: $text";
    final response = await _processWithGemma(prompt);
    final cleanResponse = response.trim().toUpperCase();

    if (cleanResponse.contains("EXCERPT")) return SourceType.excerpt;
    if (cleanResponse.contains("ORIGINAL")) return SourceType.original;

    return SourceType.unknown;
  }

  /// 提取作者和作品名
  Future<(String?, String?)> extractSourceDetails(String text) async {
    if (text.isEmpty) return (null, null);
    final prompt = "Extract the author and work title from the text if present. Format: Author|Work. If not found, output NULL|NULL.\nText: $text";
    final response = await _processWithGemma(prompt);
    final parts = response.trim().split('|');
    if (parts.length == 2) {
      final author = parts[0].trim() == 'NULL' ? null : parts[0].trim();
      final work = parts[1].trim() == 'NULL' ? null : parts[1].trim();
      return (author, work);
    }
    return (null, null);
  }

  /// 智能标签建议
  Future<List<String>> suggestTags(String content) async {
    if (content.isEmpty) return [];
    final prompt = "Suggest up to 3 relevant tags for this text. Comma separated, no hash symbols.\nText: $content";
    final response = await _processWithGemma(prompt);
    return response.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// 笔记分类
  Future<NoteCategory?> classifyNote(String content, List<NoteCategory> availableCategories) async {
    if (content.isEmpty || availableCategories.isEmpty) return null;
    final categoryNames = availableCategories.map((c) => c.name).join(", ");
    final prompt = "Classify this text into one of these categories: [$categoryNames]. Output only the category name.\nText: $content";

    final response = await _processWithGemma(prompt);
    final matchedName = response.trim();

    try {
      return availableCategories.firstWhere(
        (c) => c.name.toLowerCase() == matchedName.toLowerCase()
      );
    } catch (_) {
      return null;
    }
  }

  /// 情绪检测
  Future<EmotionResult> detectEmotion(String content) async {
    if (content.isEmpty) return EmotionResult("Neutral", 0.0);
    final prompt = "Detect the primary emotion of this text (e.g., Joy, Sadness, Anger, Neutral). Output Format: Emotion|Confidence(0.0-1.0)\nText: $content";
    final response = await _processWithGemma(prompt);
    final parts = response.trim().split('|');
    if (parts.length == 2) {
      return EmotionResult(parts[0].trim(), double.tryParse(parts[1].trim()) ?? 0.5);
    }
    return EmotionResult("Neutral", 0.0);
  }
}
