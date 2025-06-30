import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import '../../lib/services/ai_service.dart';
import '../../lib/models/quote_model.dart';
import '../../lib/models/ai_provider_settings.dart';

// Mock class generation annotation
@GenerateMocks([AIService])
class MockAIService extends Mock implements AIService {
  // Mock AI analysis results
  static const String _mockAnalysis = '''
这是一段充满哲理的思考，体现了对生活的深度洞察。文字中透露出一种积极向上的态度，
同时也包含了对人生经历的理性思考。这样的内容有助于启发读者进行自我反思。
  '''.trim();

  static const String _mockSentiment = 'positive';
  static const List<String> _mockKeywords = ['哲理', '思考', '生活', '洞察', '积极'];
  static const String _mockSummary = '一段关于生活哲理的深度思考，体现积极态度';

  bool _isAnalyzing = false;
  bool _isGenerating = false;

  @override
  bool get isAnalyzing => _isAnalyzing;

  @override
  bool get isGenerating => _isGenerating;

  @override
  Future<Map<String, dynamic>> analyzeQuote(Quote quote) async {
    _isAnalyzing = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    _isAnalyzing = false;
    notifyListeners();

    return {
      'analysis': _mockAnalysis,
      'sentiment': _mockSentiment,
      'keywords': _mockKeywords,
      'summary': _mockSummary,
    };
  }

  @override
  Future<void> analyzeQuoteStreaming(
    Quote quote, {
    StreamingResponseCallback? onData,
    StreamingCompleteCallback? onComplete,
    StreamingErrorCallback? onError,
  }) async {
    _isAnalyzing = true;
    notifyListeners();

    try {
      // Simulate streaming response
      final words = _mockAnalysis.split('');
      String accumulated = '';

      for (int i = 0; i < words.length; i++) {
        accumulated += words[i];
        onData?.call(accumulated);
        await Future.delayed(const Duration(milliseconds: 20));
      }

      _isAnalyzing = false;
      notifyListeners();
      onComplete?.call(accumulated);
    } catch (e) {
      _isAnalyzing = false;
      notifyListeners();
      onError?.call(e);
    }
  }

  @override
  Future<String> generateDailyPrompt() async {
    _isGenerating = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    _isGenerating = false;
    notifyListeners();

    return '今天是一个新的开始，你想要记录什么特别的想法或感受吗？';
  }

  @override
  Future<List<String>> generateTagSuggestions(String content) async {
    // Simple mock tag generation based on content
    final suggestions = <String>[];
    
    if (content.contains('工作') || content.contains('职场')) {
      suggestions.addAll(['工作', '职场', '事业']);
    }
    if (content.contains('生活') || content.contains('日常')) {
      suggestions.addAll(['生活', '日常', '感悟']);
    }
    if (content.contains('学习') || content.contains('知识')) {
      suggestions.addAll(['学习', '知识', '成长']);
    }
    if (content.contains('情感') || content.contains('心情')) {
      suggestions.addAll(['情感', '心情', '内心']);
    }
    
    // Default suggestions if no specific matches
    if (suggestions.isEmpty) {
      suggestions.addAll(['随想', '记录', '思考']);
    }
    
    return suggestions.take(5).toList();
  }

  @override
  Future<String> improveSentence(String sentence) async {
    _isGenerating = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 400));

    _isGenerating = false;
    notifyListeners();

    // Simple improvement simulation
    if (sentence.length < 10) {
      return '$sentence - 这个想法很有趣，值得进一步思考。';
    } else if (sentence.length < 50) {
      return '$sentence 这样的观察体现了深度的思考能力。';
    } else {
      return '$sentence\n\n总的来说，这是一个很有价值的思考。';
    }
  }

  @override
  Future<List<String>> generateSimilarQuotes(Quote quote) async {
    await Future.delayed(const Duration(milliseconds: 300));

    return [
      '相似的思考往往来自于对生活的细致观察。',
      '每个人的感悟都是独特的，但共鸣是普遍的。',
      '记录想法的过程本身就是一种成长。',
    ];
  }

  @override
  Future<bool> testConnection() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return true; // Always successful in mock
  }

  @override
  Future<Map<String, dynamic>> getChatCompletion({
    required String content,
    String model = 'gpt-3.5-turbo',
    Map<String, dynamic>? options,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    return {
      'choices': [
        {
          'message': {
            'content': '这是模拟的AI回复：$content',
            'role': 'assistant',
          }
        }
      ],
      'usage': {
        'prompt_tokens': content.length ~/ 4,
        'completion_tokens': 20,
        'total_tokens': (content.length ~/ 4) + 20,
      }
    };
  }

  @override
  Future<void> getChatCompletionStreaming({
    required String content,
    String model = 'gpt-3.5-turbo',
    Map<String, dynamic>? options,
    StreamingResponseCallback? onData,
    StreamingCompleteCallback? onComplete,
    StreamingErrorCallback? onError,
  }) async {
    try {
      const response = '这是模拟的流式AI回复，一个字一个字地返回。';
      String accumulated = '';

      for (int i = 0; i < response.length; i++) {
        accumulated += response[i];
        onData?.call(accumulated);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      onComplete?.call(accumulated);
    } catch (e) {
      onError?.call(e);
    }
  }

  // Test helper methods
  void setAnalyzing(bool analyzing) {
    _isAnalyzing = analyzing;
    notifyListeners();
  }

  void setGenerating(bool generating) {
    _isGenerating = generating;
    notifyListeners();
  }

  void simulateError() {
    throw Exception('Mock AI service error');
  }

  void resetState() {
    _isAnalyzing = false;
    _isGenerating = false;
    notifyListeners();
  }
}