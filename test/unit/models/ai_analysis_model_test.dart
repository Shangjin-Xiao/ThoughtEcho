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

    test('should reject negative quoteCount values', () {
      expect(
        AIAnalysis.fromJson({
          'title': 't',
          'content': 'c',
          'quote_count': -1,
        }).quoteCount,
        isNull,
      );

      expect(
        AIAnalysis.fromJson({
          'title': 't',
          'content': 'c',
          'quote_count': -2.0,
        }).quoteCount,
        isNull,
      );

      expect(
        AIAnalysis.fromJson({
          'title': 't',
          'content': 'c',
          'quote_count': '-10',
        }).quoteCount,
        isNull,
      );
    });

    test(
        'should fallback empty string analysisType, analysisStyle, and createdAt',
        () {
      final analysis = AIAnalysis.fromJson({
        'title': 't',
        'content': 'c',
        'analysis_type': '',
        'analysis_style': '',
        'created_at': '',
      });

      expect(analysis.analysisType, equals('comprehensive'));
      expect(analysis.analysisStyle, equals('professional'));
      expect(analysis.createdAt, isNotEmpty);
    });

    test('should format toString() correctly', () {
      final analysis = AIAnalysis(
        id: '123',
        title: '测试标题',
        content: '测试内容',
        analysisType: 'emotional',
        analysisStyle: 'friendly',
        createdAt: '2025-01-01T00:00:00Z',
        quoteCount: 5,
      );

      expect(
        analysis.toString(),
        equals(
          'AIAnalysis{id: 123, title: 测试标题, analysisType: emotional, createdAt: 2025-01-01T00:00:00Z, quoteCount: 5}',
        ),
      );
    });

    test('should copyWith all fields correctly when specified or defaulted',
        () {
      final original = AIAnalysis(
        id: '1',
        title: 'Title 1',
        content: 'Content 1',
        analysisType: 'comprehensive',
        analysisStyle: 'professional',
        customPrompt: 'Prompt 1',
        createdAt: '2025-01-01T00:00:00Z',
        relatedQuoteIds: const ['q1'],
        quoteCount: 1,
      );

      final updated = original.copyWith(
        id: '2',
        title: 'Title 2',
        content: 'Content 2',
        analysisType: 'emotional',
        analysisStyle: 'friendly',
        customPrompt: 'Prompt 2',
        createdAt: '2025-01-02T00:00:00Z',
        relatedQuoteIds: const ['q2', 'q3'],
        quoteCount: 2,
      );

      expect(updated.id, '2');
      expect(updated.title, 'Title 2');
      expect(updated.content, 'Content 2');
      expect(updated.analysisType, 'emotional');
      expect(updated.analysisStyle, 'friendly');
      expect(updated.customPrompt, 'Prompt 2');
      expect(updated.createdAt, '2025-01-02T00:00:00Z');
      expect(updated.relatedQuoteIds, ['q2', 'q3']);
      expect(updated.quoteCount, 2);

      final unchanged = original.copyWith();
      expect(unchanged.id, original.id);
      expect(unchanged.title, original.title);
      expect(unchanged.content, original.content);
      expect(unchanged.analysisType, original.analysisType);
      expect(unchanged.analysisStyle, original.analysisStyle);
      expect(unchanged.customPrompt, original.customPrompt);
      expect(unchanged.createdAt, original.createdAt);
      expect(unchanged.relatedQuoteIds, original.relatedQuoteIds);
      expect(unchanged.quoteCount, original.quoteCount);
    });

    test('should handle unexpected data types in parseRelatedQuoteIds safely',
        () {
      final jsonWithInt = {
        'title': 't',
        'content': 'c',
        'related_quote_ids': 12345,
      };
      expect(AIAnalysis.fromJson(jsonWithInt).relatedQuoteIds, isNull);

      final jsonWithBool = {
        'title': 't',
        'content': 'c',
        'related_quote_ids': true,
      };
      expect(AIAnalysis.fromJson(jsonWithBool).relatedQuoteIds, isNull);

      final jsonWithMap = {
        'title': 't',
        'content': 'c',
        'related_quote_ids': {'key': 'val'},
      };
      expect(AIAnalysis.fromJson(jsonWithMap).relatedQuoteIds, isNull);
    });

    test('should convert to json with null/default fields correctly', () {
      final analysis = AIAnalysis(
        title: '无ID分析',
        content: '无ID内容',
        analysisType: 'comprehensive',
        analysisStyle: 'professional',
        createdAt: '2025-01-01T00:00:00Z',
      );

      final json = analysis.toJson();
      expect(json['id'], isNull);
      expect(json['title'], '无ID分析');
      expect(json['content'], '无ID内容');
      expect(json['analysis_type'], 'comprehensive');
      expect(json['analysis_style'], 'professional');
      expect(json['custom_prompt'], isNull);
      expect(json['created_at'], '2025-01-01T00:00:00Z');
      expect(json['related_quote_ids'], isNull);
      expect(json['quote_count'], isNull);
    });
  });
}
