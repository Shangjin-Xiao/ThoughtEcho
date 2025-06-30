/// Test data utilities for ThoughtEcho test suite
/// Provides common test data objects and factory methods
library test_utils;

import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/ai_analysis_model.dart';
import 'package:thoughtecho/models/weather_data.dart';

class TestData {
  /// Test quotes data
  static Quote createTestQuote({
    String? id,
    String? content,
    String? date,
    String? categoryId,
    List<String>? tagIds,
    String? location,
    String? weather,
    String? temperature,
    String? deltaContent,
  }) {
    return Quote(
      id: id ?? 'test-quote-1',
      content: content ?? '这是一个测试笔记内容',
      date: date ?? DateTime.now().toIso8601String(),
      categoryId: categoryId ?? 'test-category-1',
      tagIds: tagIds ?? ['tag1', 'tag2'],
      location: location ?? '北京市朝阳区',
      weather: weather ?? '晴',
      temperature: temperature ?? '25°C',
      deltaContent: deltaContent,
      source: '测试来源',
      sourceAuthor: '测试作者',
      sourceWork: '测试作品',
      aiAnalysis: '这是一个积极正面的测试内容',
      sentiment: 'positive',
      keywords: ['测试', '笔记', '内容'],
      summary: '测试笔记摘要',
      colorHex: '#FF5722',
      editSource: 'manual',
      dayPeriod: 'morning',
    );
  }

  /// Test categories data
  static NoteCategory createTestCategory({
    String? id,
    String? name,
    String? iconName,
    bool? isDefault,
  }) {
    return NoteCategory(
      id: id ?? 'test-category-1',
      name: name ?? '测试分类',
      iconName: iconName ?? 'folder',
      isDefault: isDefault ?? false,
    );
  }

  /// Test AI analysis data
  static AIAnalysis createTestAIAnalysis({
    String? id,
    String? quoteId,
    String? analysisType,
    String? content,
  }) {
    return AIAnalysis(
      id: id ?? 'test-analysis-1',
      quoteId: quoteId ?? 'test-quote-1',
      analysisType: analysisType ?? 'sentiment',
      content: content ?? '这是一个积极正面的分析结果',
      createdAt: DateTime.now().toIso8601String(),
      metadata: {
        'confidence': 0.95,
        'model': 'gpt-3.5-turbo',
      },
    );
  }

  /// Test weather data
  static WeatherData createTestWeatherData({
    String? key,
    String? description,
    double? temperature,
    String? iconCode,
  }) {
    return WeatherData(
      key: key ?? 'sunny',
      description: description ?? '晴天',
      temperature: temperature ?? 25.0,
      temperatureText: temperature != null ? '${temperature}°C' : '25°C',
      iconCode: iconCode ?? 'sunny',
    );
  }

  /// Create multiple test quotes
  static List<Quote> createTestQuoteList(int count) {
    return List.generate(count, (index) => createTestQuote(
      id: 'test-quote-${index + 1}',
      content: '测试笔记内容 ${index + 1}',
      date: DateTime.now().subtract(Duration(days: index)).toIso8601String(),
    ));
  }

  /// Create multiple test categories
  static List<NoteCategory> createTestCategoryList() {
    return [
      createTestCategory(id: 'cat-1', name: '工作', iconName: 'work'),
      createTestCategory(id: 'cat-2', name: '生活', iconName: 'home'),
      createTestCategory(id: 'cat-3', name: '学习', iconName: 'school'),
      createTestCategory(id: 'cat-4', name: '思考', iconName: 'lightbulb'),
    ];
  }

  /// Sample JSON data for testing
  static Map<String, dynamic> sampleQuoteJson = {
    'id': 'test-quote-json',
    'content': 'JSON测试内容',
    'date': '2024-01-01T12:00:00.000Z',
    'category_id': 'test-category',
    'tag_ids': 'tag1,tag2,tag3',
    'source': 'JSON测试来源',
    'source_author': 'JSON测试作者',
    'source_work': 'JSON测试作品',
    'location': 'JSON测试位置',
    'weather': 'JSON测试天气',
    'temperature': '20°C',
    'color_hex': '#2196F3',
    'edit_source': 'manual',
    'delta_content': '{"ops":[{"insert":"JSON测试富文本\\n"}]}',
    'day_period': 'afternoon',
    'ai_analysis': 'JSON测试AI分析',
    'sentiment': 'neutral',
    'keywords': 'JSON,测试,关键词',
    'summary': 'JSON测试摘要',
  };

  /// Sample backup data for testing
  static Map<String, dynamic> sampleBackupData = {
    'app_info': {
      'name': 'ThoughtEcho',
      'version': '1.0.0',
      'export_time': '2024-01-01T12:00:00.000Z',
    },
    'quotes': [sampleQuoteJson],
    'categories': [
      {
        'id': 'test-category',
        'name': '测试分类',
        'icon_name': 'folder',
        'is_default': false,
      }
    ],
  };

  /// Common test constants
  static const String testApiKey = 'sk-test1234567890abcdef';
  static const String testProviderUrl = 'https://api.test.com/v1/chat/completions';
  static const String testErrorMessage = '测试错误消息';
  static const Duration testTimeout = Duration(seconds: 5);
}