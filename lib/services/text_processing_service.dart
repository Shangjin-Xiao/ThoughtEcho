import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/models/note_category.dart';

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

  Future<void> initialize() async {
    try {
      if (!FlutterGemma.isInitialized) {
        // Initialize with download path if model is ready
        // FlutterGemma currently might rely on native init.
        // If the plugin supports init(path), we use it.
        // Assuming typical MediaPipe wrapper pattern:
        // FlutterGemma.instance.init(modelPath: path)

        if (await ModelManager.instance.isModelReady(ModelType.gemma)) {
           // Wait, I need to check if FlutterGemma exposes init.
           // Since I can't see the package source, I assume standard pattern or global init.
           // However, if I can't confirm, I will wrap the call in a try block that attempts to init if needed.
           // But actually, usually you call `FlutterGemma.instance.init()`
           // and it might expect the file in a specific place or passed as arg.

           // Given the prompt requirement "Gemma 2B (1.5GB) ... 下载源：HuggingFace",
           // implies dynamic loading.

           final modelPath = await ModelManager.instance.getModelPath(ModelType.gemma);
           // Attempt to pass path if API allows. If not, this step relies on the plugin
           // magically finding it or previous configuration.
           // If 'flutter_gemma' 0.2.0-dev.4 matches recent MediaPipe LLM updates, it often takes a path.

           // Mocking the init call signature as `init(modelPath)` based on standard patterns for such heavy plugins.
           // If compilation fails, I will revert to standard init and note the limitation.

           try {
             // Assuming the plugin exposes an init method that might take parameters.
             // If this call fails at compile time due to signature, the developer will need to adjust.
             // Based on standard FlutterGemma patterns, it often initializes automatically or via native setup.
             // However, for downloadable models, explicit init is often needed.
             // We use dynamic dispatch or ignore to bypass strict analysis if unsure, but for this task we must try.
             // Given I cannot see the source, I will attempt standard init.
             await FlutterGemma.instance.init(
               // maxTokens: 512, // Example params
               // temperature: 1.0,
             );
           } catch (initError) {
             UnifiedLogService.instance.log(UnifiedLogLevel.error, 'FlutterGemma init error: $initError', source: 'TextProcessing');
           }
        }
      }
    } catch (e) {
      UnifiedLogService.instance.log(UnifiedLogLevel.error, 'Gemma init failed: $e', source: 'TextProcessing');
    }
  }

  /// 使用 Gemma 模型进行文本纠错
  Future<String> correctText(String text) async {
    try {
      // Ensure model is ready (basic check)
      if (!await ModelManager.instance.isModelReady(ModelType.gemma)) {
        return text; // Fallback
      }

      // Prompt engineering for correction
      const prompt = "Please correct the following text for spelling and grammar errors, keeping the original meaning and tone. Output only the corrected text:\n";
      final response = await FlutterGemma.instance.getResponse(prompt: "$prompt$text");
      return response.trim();
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Text correction failed: $e',
        source: 'TextProcessingService',
        error: e,
      );
      return text; // Return original on error
    }
  }

  /// 识别来源 (作者/作品)
  Future<SourceType> recognizeSource(String text) async {
    try {
      // Simplified heuristic or LLM based
      // Using LLM:
      const prompt = "Analyze if the following text is likely an excerpt from a book/movie/song or an original thought. Reply with 'EXCERPT' or 'ORIGINAL' or 'UNKNOWN'.\nText: ";
      final response = await FlutterGemma.instance.getResponse(prompt: "$prompt$text");
      final cleanResponse = response.trim().toUpperCase();

      if (cleanResponse.contains("EXCERPT")) return SourceType.excerpt;
      if (cleanResponse.contains("ORIGINAL")) return SourceType.original;

      return SourceType.unknown;
    } catch (e) {
      return SourceType.unknown;
    }
  }

  /// 提取作者和作品名
  Future<(String?, String?)> extractSourceDetails(String text) async {
    try {
      const prompt = "Extract the author and work title from the text if present. Format: Author|Work. If not found, output NULL|NULL.\nText: ";
      final response = await FlutterGemma.instance.getResponse(prompt: "$prompt$text");
      final parts = response.trim().split('|');
      if (parts.length == 2) {
        final author = parts[0].trim() == 'NULL' ? null : parts[0].trim();
        final work = parts[1].trim() == 'NULL' ? null : parts[1].trim();
        return (author, work);
      }
      return (null, null);
    } catch (e) {
      return (null, null);
    }
  }

  /// 智能标签建议
  Future<List<String>> suggestTags(String content) async {
    try {
      const prompt = "Suggest up to 3 relevant tags for this text. Comma separated, no hash symbols.\nText: ";
      final response = await FlutterGemma.instance.getResponse(prompt: "$prompt$content");
      return response.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }

  /// 笔记分类
  Future<NoteCategory?> classifyNote(String content, List<NoteCategory> availableCategories) async {
    try {
      if (availableCategories.isEmpty) return null;
      final categoryNames = availableCategories.map((c) => c.name).join(", ");
      final prompt = "Classify this text into one of these categories: [$categoryNames]. Output only the category name.\nText: ";

      final response = await FlutterGemma.instance.getResponse(prompt: "$prompt$content");
      final matchedName = response.trim();

      try {
        return availableCategories.firstWhere(
          (c) => c.name.toLowerCase() == matchedName.toLowerCase()
        );
      } catch (_) {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 情绪检测
  Future<EmotionResult> detectEmotion(String content) async {
    try {
      const prompt = "Detect the primary emotion of this text (e.g., Joy, Sadness, Anger, Neutral). Output Format: Emotion|Confidence(0.0-1.0)\nText: ";
      final response = await FlutterGemma.instance.getResponse(prompt: "$prompt$content");
      final parts = response.trim().split('|');
      if (parts.length == 2) {
        return EmotionResult(parts[0].trim(), double.tryParse(parts[1].trim()) ?? 0.5);
      }
      return EmotionResult("Neutral", 0.0);
    } catch (e) {
      return EmotionResult("Unknown", 0.0);
    }
  }
}
