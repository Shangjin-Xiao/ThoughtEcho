import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/card_templates.dart';
import 'package:thoughtecho/models/generated_card.dart';

void main() {
  group('现代化SVG卡片模板测试', () {
    const testContent =
        '这是一段测试内容，用来验证SVG卡片模板的生成效果。内容包含中文字符和标点符号，以确保模板能够正确处理各种文本。';
    const testAuthor = '测试作者';
    const testDate = '2024年1月15日';

    test('知识卡片模板生成', () {
      final svg = CardTemplates.knowledgeTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('viewBox="0 0 400 600"'));
      expect(svg, contains('modernKnowledgeBg'));
      expect(svg, contains(testAuthor));
      expect(svg, contains(testDate));
      expect(svg, contains('ThoughtEcho'));
    });

    test('引用卡片模板生成', () {
      final svg = CardTemplates.quoteTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('modernQuoteBg'));
      expect(svg, contains(testAuthor));
      expect(svg, contains(testDate));
    });

    test('哲学思考卡片模板生成', () {
      final svg = CardTemplates.philosophicalTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('modernPhiloBg'));
      expect(svg, contains('思考者：$testAuthor'));
      expect(svg, contains(testDate));
    });

    test('简约卡片模板生成', () {
      final svg = CardTemplates.minimalistTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('minimalistBg'));
      expect(svg, contains(testAuthor));
      expect(svg, contains(testDate));
    });

    test('根据类型获取模板', () {
      // 测试知识卡片
      final knowledgeSvg = CardTemplates.getTemplateByType(
        type: CardType.knowledge,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(knowledgeSvg, contains('modernKnowledgeBg'));

      // 测试引用卡片
      final quoteSvg = CardTemplates.getTemplateByType(
        type: CardType.quote,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(quoteSvg, contains('modernQuoteBg'));

      // 测试哲学卡片
      final philoSvg = CardTemplates.getTemplateByType(
        type: CardType.philosophical,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(philoSvg, contains('modernPhiloBg'));

      // 测试简约卡片
      final minimalistSvg = CardTemplates.getTemplateByType(
        type: CardType.minimalist,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(minimalistSvg, contains('minimalistBg'));
    });

    test('长文本处理', () {
      const longContent = '''
这是一段非常长的测试内容，用来验证模板对长文本的处理能力。
内容包含多行文字，以及各种标点符号和特殊字符。
模板应该能够智能地截断文本，并保持良好的显示效果。
这段文本故意写得很长，以测试模板的文本处理逻辑。
''';

      final svg = CardTemplates.knowledgeTemplate(
        content: longContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      // 验证文本被正确处理（不会过长）
      expect(svg.length, lessThan(10000)); // 合理的SVG长度限制
    });

    test('无作者信息处理', () {
      final svg = CardTemplates.knowledgeTemplate(
        content: testContent,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains(testDate));
      // 不应该包含空的作者信息
      expect(svg, isNot(contains('作者：null')));
    });

    test('SVG结构验证', () {
      final svg = CardTemplates.knowledgeTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      // 验证基本SVG结构
      expect(svg, contains('<defs>'));
      expect(svg, contains('</defs>'));
      expect(svg, contains('<linearGradient'));
      expect(svg, contains('<rect'));
      expect(svg, contains('<text'));
      expect(svg, contains('filter="url(#shadow)"'));

      // 验证现代化设计元素
      expect(svg, contains('system-ui'));
      expect(svg, contains('font-weight'));
      expect(svg, contains('rx="')); // 圆角
    });

    test('颜色和样式验证', () {
      final svg = CardTemplates.knowledgeTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      // 验证现代化配色
      expect(svg, contains('#4f46e5')); // 现代蓝色
      expect(svg, contains('#7c3aed')); // 现代紫色
      expect(svg, contains('#db2777')); // 现代粉色
      expect(svg, contains('stop-opacity'));
      expect(svg, contains('fill-opacity'));
    });
  });
}
