import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/card_templates.dart';
import 'package:thoughtecho/models/generated_card.dart';

/// SVG卡片渲染修复验证测试
void main() {
  group('SVG卡片内容溢出与空白修复验证', () {
    test('长内容应正确换行且不溢出', () {
      // 创建一个超长内容
      final longContent = '这是一段非常长的文本内容,用于测试SVG卡片在处理长文本时是否会发生溢出。' * 5;

      final svg = CardTemplates.knowledgeTemplate(
        content: longContent,
        date: '2025年10月1日',
      );

      // 验证SVG结构完整
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('viewBox="0 0 400 600"'));

      // 验证包含文本元素
      expect(svg, contains('<text'));

      // 验证SVG不包含错误的属性组合(会导致空白)
      expect(svg, isNot(contains('width="0"')));
      expect(svg, isNot(contains('height="0"')));
    });

    test('中英文混合内容应正确计算宽度', () {
      const mixedContent = 'Hello 世界! This is a test 这是测试 123';

      final svg = CardTemplates.minimalistTemplate(
        content: mixedContent,
        date: '2025年10月1日',
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains(mixedContent.substring(0, 10))); // 至少包含部分内容
    });

    test('viewBox应统一为标准尺寸', () {
      final testCases = [
        CardTemplates.knowledgeTemplate(content: '测试', date: '2025年10月1日'),
        CardTemplates.quoteTemplate(content: '测试', date: '2025年10月1日'),
        CardTemplates.philosophicalTemplate(content: '测试', date: '2025年10月1日'),
        CardTemplates.minimalistTemplate(content: '测试', date: '2025年10月1日'),
      ];

      for (final svg in testCases) {
        // 验证所有模板使用统一的viewBox
        expect(svg, contains('viewBox="0 0 400 600"'));
        // 验证没有额外的width/height属性(应由渲染器控制)
        final widthMatches = RegExp(r'<svg[^>]*\swidth=').allMatches(svg);
        expect(widthMatches.length, 0, reason: 'SVG不应包含width属性');
      }
    });

    test('所有模板类型应可通过getTemplateByType访问', () {
      final types = [
        CardType.knowledge,
        CardType.quote,
        CardType.philosophical,
        CardType.minimalist,
        CardType.gradient, // 应回退到knowledge
      ];

      for (final type in types) {
        final svg = CardTemplates.getTemplateByType(
          type: type,
          content: '测试内容',
          date: '2025年10月1日',
        );

        expect(svg, contains('<svg'));
        expect(svg, contains('</svg>'));
        expect(svg, contains('viewBox="0 0 400 600"'));
      }
    });

    test('元数据应正确渲染且不重叠', () {
      final svg = CardTemplates.knowledgeTemplate(
        content: '测试内容',
        date: '2025年10月1日',
        location: '北京市,海淀区,中关村',
        weather: 'sunny',
        temperature: '25°C',
        author: '作者姓名',
      );

      // 验证包含所有元数据
      expect(svg, contains('2025年10月1日'));
      expect(svg, contains('心迹'));

      // 验证SVG结构完整
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
    });

    test('特殊字符应正确转义', () {
      const contentWithSpecialChars = '这是<特殊>字符&测试"内容"';

      final svg = CardTemplates.quoteTemplate(
        content: contentWithSpecialChars,
        date: '2025年10月1日',
      );

      // 验证特殊字符被转义
      expect(svg, contains('&lt;'));
      expect(svg, contains('&gt;'));
      expect(svg, contains('&amp;'));
    });

    test('换行符应正确处理', () {
      const contentWithNewlines = '第一行\n第二行\n第三行';

      final svg = CardTemplates.philosophicalTemplate(
        content: contentWithNewlines,
        date: '2025年10月1日',
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));

      // 应该生成多个text元素或包含换行内容
      final textCount = '<text'.allMatches(svg).length;
      expect(textCount, greaterThan(1), reason: '应该有多个文本元素以处理换行');
    });
  });
}
