/// Mock AI Service for testing
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/ai_analysis_model.dart';
import '../test_utils/test_data.dart';

class MockAIService extends ChangeNotifier {
  bool _isInitialized = false;
  bool _hasValidApiKey = false;
  String? _lastError;
  Map<String, String> _analysisResults = {};
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get hasValidApiKey => _hasValidApiKey;
  String? get lastError => _lastError;

  /// Initialize mock AI service
  Future<void> initialize() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _isInitialized = true;
    notifyListeners();
  }

  /// Set API key validity
  void setApiKeyValid(bool valid) {
    _hasValidApiKey = valid;
    notifyListeners();
  }

  /// Check if has valid API key
  Future<bool> hasValidApiKeyAsync() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return _hasValidApiKey;
  }

  /// Test connection
  Future<void> testConnection() async {
    await Future.delayed(const Duration(milliseconds: 200));
    
    if (!_hasValidApiKey) {
      throw Exception('请先在设置中配置 API Key');
    }
    
    // Simulate successful connection
  }

  /// Test connection with multiple providers
  Future<void> testConnectionWithMultiProvider() async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (!_hasValidApiKey) {
      throw Exception('请先在设置中配置 API Key');
    }
    
    // Simulate multi-provider test
  }

  /// Summarize note with multi-provider
  Future<String> summarizeNoteWithMultiProvider(Quote quote) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!_hasValidApiKey) {
      throw Exception('请先在设置中配置 API Key');
    }
    
    if (quote.content.trim().isEmpty) {
      throw Exception('没有可分析的文本内容');
    }
    
    // Generate mock analysis
    final mockAnalysis = '''
这是一个关于"${quote.content.substring(0, quote.content.length > 20 ? 20 : quote.content.length)}"的分析：

**主要内容**：这是一个${_getContentType(quote.content)}类型的文本。

**情感倾向**：${_analyzeSentiment(quote.content)}

**关键要点**：
- 内容长度：${quote.content.length}字符
- 包含积极元素
- 具有一定的思考深度

**总结**：这是一个有价值的记录，体现了作者的思考和感悟。
''';
    
    _analysisResults[quote.id ?? 'unknown'] = mockAnalysis;
    return mockAnalysis;
  }

  /// Generate insights from quotes
  Future<String> generateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
    String? customPrompt,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (!_hasValidApiKey) {
      throw Exception('请先在设置中配置 API Key');
    }
    
    if (quotes.isEmpty) {
      throw Exception('没有可分析的笔记');
    }
    
    // Generate mock insights
    final mockInsights = '''
## 笔记洞察分析 (${analysisType})

**分析范围**：${quotes.length}条笔记
**分析时间**：${DateTime.now().toString().substring(0, 19)}
**分析风格**：$analysisStyle

### 📊 总体概况
您的笔记展现了丰富的思考维度，涵盖了工作、生活、学习等多个方面。

### 🎯 主要主题
${quotes.take(3).map((q) => '- ${q.content.substring(0, q.content.length > 30 ? 30 : q.content.length)}...').join('\n')}

### 💭 情感变化
整体情感倾向积极向上，体现了健康的心理状态。

### 🔮 成长建议
建议继续保持记录习惯，定期回顾和反思，促进个人成长。
''';
    
    return mockInsights;
  }

  /// Stream generate insights
  Stream<String> streamGenerateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
    String? customPrompt,
  }) {
    final controller = StreamController<String>();
    
    _generateInsightsStreamly(controller, quotes, analysisType, analysisStyle, customPrompt);
    
    return controller.stream;
  }

  /// Generate insights in streaming fashion
  void _generateInsightsStreamly(
    StreamController<String> controller,
    List<Quote> quotes,
    String analysisType,
    String analysisStyle,
    String? customPrompt,
  ) async {
    try {
      if (!_hasValidApiKey) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        return;
      }
      
      if (quotes.isEmpty) {
        controller.addError(Exception('没有可分析的笔记'));
        return;
      }
      
      // Simulate streaming response
      final chunks = [
        '## 笔记洞察分析\n\n',
        '**分析范围**：${quotes.length}条笔记\n',
        '**分析时间**：${DateTime.now().toString().substring(0, 19)}\n\n',
        '### 📊 总体概况\n',
        '您的笔记展现了丰富的思考维度，',
        '涵盖了工作、生活、学习等多个方面。\n\n',
        '### 🎯 主要主题\n',
        ...quotes.take(3).map((q) => '- ${q.content.substring(0, q.content.length > 30 ? 30 : q.content.length)}...\n'),
        '\n### 💭 情感变化\n',
        '整体情感倾向积极向上，',
        '体现了健康的心理状态。\n\n',
        '### 🔮 成长建议\n',
        '建议继续保持记录习惯，',
        '定期回顾和反思，',
        '促进个人成长。\n',
      ];
      
      for (final chunk in chunks) {
        await Future.delayed(const Duration(milliseconds: 100));
        controller.add(chunk);
      }
      
      controller.close();
    } catch (e) {
      controller.addError(e);
      controller.close();
    }
  }

  /// Stream QA with note
  Stream<String> streamQAWithNote(Quote quote, String question) {
    final controller = StreamController<String>();
    
    _qaWithNoteStreamly(controller, quote, question);
    
    return controller.stream;
  }

  /// Generate QA response in streaming fashion
  void _qaWithNoteStreamly(
    StreamController<String> controller,
    Quote quote,
    String question,
  ) async {
    try {
      if (!_hasValidApiKey) {
        controller.addError(Exception('请先在设置中配置 API Key'));
        return;
      }
      
      if (quote.content.trim().isEmpty) {
        controller.addError(Exception('没有可分析的文本内容'));
        return;
      }
      
      // Generate mock QA response
      final mockAnswer = '''
根据您的笔记"${quote.content.substring(0, quote.content.length > 50 ? 50 : quote.content.length)}..."，针对问题"$question"的回答：

这是一个很好的问题。从您的笔记内容来看，可以从以下几个角度来分析：

1. 内容层面：您的记录体现了深度思考
2. 情感层面：展现了积极的心态
3. 实践层面：可以考虑进一步的行动计划

希望这个回答对您有帮助。
''';
      
      // Stream the response in chunks
      final chunks = mockAnswer.split('。');
      for (final chunk in chunks) {
        if (chunk.trim().isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 150));
          controller.add(chunk + '。');
        }
      }
      
      controller.close();
    } catch (e) {
      controller.addError(e);
      controller.close();
    }
  }

  /// Get content type
  String _getContentType(String content) {
    if (content.contains('工作') || content.contains('项目')) return '工作';
    if (content.contains('学习') || content.contains('知识')) return '学习';
    if (content.contains('生活') || content.contains('日常')) return '生活';
    if (content.contains('思考') || content.contains('反思')) return '思考';
    return '综合';
  }

  /// Analyze sentiment
  String _analyzeSentiment(String content) {
    final positiveWords = ['好', '棒', '开心', '快乐', '满意', '成功', '进步'];
    final negativeWords = ['不好', '难', '困难', '失败', '沮丧', '烦恼'];
    
    int positiveCount = 0;
    int negativeCount = 0;
    
    for (final word in positiveWords) {
      if (content.contains(word)) positiveCount++;
    }
    
    for (final word in negativeWords) {
      if (content.contains(word)) negativeCount++;
    }
    
    if (positiveCount > negativeCount) return '积极正面';
    if (negativeCount > positiveCount) return '需要关注';
    return '中性平衡';
  }

  /// Simulate error
  void simulateError(String error) {
    _lastError = error;
    notifyListeners();
  }

  /// Get analysis result
  String? getAnalysisResult(String quoteId) {
    return _analysisResults[quoteId];
  }

  /// Clear analysis results
  void clearAnalysisResults() {
    _analysisResults.clear();
    notifyListeners();
  }
}