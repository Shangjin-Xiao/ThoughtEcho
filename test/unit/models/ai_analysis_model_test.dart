import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_analysis_model.dart';

void main() {
  group('AIAnalysis Model Tests', () {
    test('should construct correctly with default values and toJson/copyWith',
        () {
      final analysis = AIAnalysis(
        id: '1',
        title: '分析标题',
        content: '分析内容',
        analysisType: 'comprehensive',
        analysisStyle: 'professional',
        createdAt: '2025-01-01T00:00:00Z',
        relatedQuoteIds: const ['q1', 'q2'],
        quoteCount: 2,
      );

      expect(analysis.id, '1');
      expect(analysis.title, '分析标题');
      expect(analysis.content, '分析内容');
      expect(analysis.relatedQuoteIds, ['q1', 'q2']);
      expect(analysis.quoteCount, 2);

      final json = analysis.toJson();
      expect(json['id'], '1');
      expect(json['title'], '分析标题');
      expect(json['analysis_type'], 'comprehensive');
      expect(json['related_quote_ids'], 'q1,q2');

      final copied = analysis.copyWith(title: '新标题');
      expect(copied.title, '新标题');
      expect(copied.content, '分析内容');
    });

    test('should parse from standard json correctly', () {
      final json = {
        'id': 'analysis_123',
        'title': '测试标题',
        'content': '测试正文',
        'analysis_type': 'emotional',
        'analysis_style': 'friendly',
        'custom_prompt': '自定义提示词',
        'created_at': '2025-03-01T12:00:00.000Z',
        'related_quote_ids': 'id1,id2,id3',
        'quote_count': 3,
      };

      final analysis = AIAnalysis.fromJson(json);
      expect(analysis.id, 'analysis_123');
      expect(analysis.title, '测试标题');
      expect(analysis.content, '测试正文');
      expect(analysis.analysisType, 'emotional');
      expect(analysis.analysisStyle, 'friendly');
      expect(analysis.customPrompt, '自定义提示词');
      expect(analysis.createdAt, '2025-03-01T12:00:00.000Z');
      expect(analysis.relatedQuoteIds, ['id1', 'id2', 'id3']);
      expect(analysis.quoteCount, 3);
    });

    test('should parse camelCase json fields correctly', () {
      final json = {
        'id': 'analysis_456',
        'title': '驼峰标题',
        'content': '驼峰正文',
        'analysisType': 'mindmap',
        'analysisStyle': 'literary',
        'customPrompt': '驼峰提示词',
        'createdAt': '2025-03-02T12:00:00.000Z',
        'relatedQuoteIds': ['idA', 'idB'],
        'quoteCount': '2',
      };

      final analysis = AIAnalysis.fromJson(json);
      expect(analysis.id, 'analysis_456');
      expect(analysis.title, '驼峰标题');
      expect(analysis.analysisType, 'mindmap');
      expect(analysis.analysisStyle, 'literary');
      expect(analysis.customPrompt, '驼峰提示词');
      expect(analysis.createdAt, '2025-03-02T12:00:00.000Z');
      expect(analysis.relatedQuoteIds, ['idA', 'idB']);
      expect(analysis.quoteCount, 2);
    });

    test(
        'should handle null/missing/unexpected-type fields safely without throwing TypeError',
        () {
      final json = <String, dynamic>{
        'id': 789, // int instead of String
        'title': null,
        'content': null,
        'analysis_type': null,
        'analysis_style': null,
        'created_at': null,
        'related_quote_ids': null,
        'quote_count': 'invalid_num',
      };

      final analysis = AIAnalysis.fromJson(json);
      expect(analysis.id, '789');
      expect(analysis.title, '');
      expect(analysis.content, '');
      expect(analysis.analysisType, 'comprehensive');
      expect(analysis.analysisStyle, 'professional');
      expect(analysis.createdAt, isNotEmpty);
      expect(analysis.relatedQuoteIds, null);
      expect(analysis.quoteCount, null);
    });

    test('should reject fractional quoteCount and accept integral doubles', () {
      final jsonFractionalNum = <String, dynamic>{
        'title': '测试',
        'content': '正文',
        'quote_count': 2.9,
      };
      expect(AIAnalysis.fromJson(jsonFractionalNum).quoteCount, isNull);

      final jsonFractionalStr = <String, dynamic>{
        'title': '测试',
        'content': '正文',
        'quote_count': '2.9',
      };
      expect(AIAnalysis.fromJson(jsonFractionalStr).quoteCount, isNull);

      final jsonIntegralDouble = <String, dynamic>{
        'title': '测试',
        'content': '正文',
        'quote_count': 2.0,
      };
      expect(AIAnalysis.fromJson(jsonIntegralDouble).quoteCount, equals(2));

      final jsonSpecialDoubles = <String, dynamic>{
        'title': '测试',
        'content': '正文',
        'quote_count': double.infinity,
      };
      expect(AIAnalysis.fromJson(jsonSpecialDoubles).quoteCount, isNull);
    });

    test('should filter null and empty elements in relatedQuoteIds safely', () {
      final jsonListWithNulls = <String, dynamic>{
        'title': '测试',
        'content': '正文',
        'related_quote_ids': ['idA', null, '   ', 123],
      };
      final analysis = AIAnalysis.fromJson(jsonListWithNulls);
      expect(analysis.relatedQuoteIds, equals(['idA', '123']));

      final jsonStrWithSpaces = <String, dynamic>{
        'title': '测试',
        'content': '正文',
        'related_quote_ids': 'idA,  , idB',
      };
      final analysis2 = AIAnalysis.fromJson(jsonStrWithSpaces);
      expect(analysis2.relatedQuoteIds, equals(['idA', 'idB']));

      final jsonAllEmpty = <String, dynamic>{
        'title': '测试',
        'content': '正文',
        'related_quote_ids': [null, '', '   '],
      };
      expect(AIAnalysis.fromJson(jsonAllEmpty).relatedQuoteIds, isNull);
    });
  });
}
