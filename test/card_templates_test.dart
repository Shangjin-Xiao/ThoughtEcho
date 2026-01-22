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
      expect(svg, matches(RegExp(r'viewBox="0 0 400\.?0? 600\.?0?"')));
      expect(svg, contains('auroraBlur'));
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
      expect(svg, contains('quoteBg'));
      expect(svg, contains(testAuthor));
      expect(svg, contains(testDate));
    });

    test('引用模板应自动多行换行', () {
      const longQuoteContent =
          '这是一段非常长的引用内容，用来测试在没有手动换行的情况下，系统是否能够自动将文本拆分成多行显示，从而避免只显示两行就出现省略号的问题。我们希望这个逻辑能够智能地利用粉色卡片中留白充足的版面，让长笔记按照中文和英文混排的规则自然地折行，直到达到可用空间上限。';

      final svg = CardTemplates.quoteTemplate(
        content: longQuoteContent,
        author: testAuthor,
        date: testDate,
      );

      final italicLineCount =
          RegExp('font-style="italic"').allMatches(svg).length;
      expect(italicLineCount, greaterThanOrEqualTo(4));
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
      expect(svg, contains('philoBg'));
      expect(svg, contains(testAuthor));
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

    test('自然卡片模板生成', () {
      final svg = CardTemplates.natureTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('natureBg'));
      expect(svg, contains(testAuthor));
      expect(svg, contains(testDate));
    });

    test('复古卡片模板生成', () {
      final svg = CardTemplates.retroTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, isNotNull);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('noise'));
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
      expect(knowledgeSvg, contains('auroraBlur'));

      // 测试引用卡片
      final quoteSvg = CardTemplates.getTemplateByType(
        type: CardType.quote,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(quoteSvg, contains('quoteBg'));

      // 测试哲学卡片
      final philoSvg = CardTemplates.getTemplateByType(
        type: CardType.philosophical,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(philoSvg, contains('philoBg')); // 注意大小写变化

      // 测试简约卡片
      final minimalistSvg = CardTemplates.getTemplateByType(
        type: CardType.minimalist,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(minimalistSvg, contains('minimalistBg'));

      // 测试自然卡片
      final natureSvg = CardTemplates.getTemplateByType(
        type: CardType.nature,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(natureSvg, contains('natureBg'));

      // 测试复古卡片
      final retroSvg = CardTemplates.getTemplateByType(
        type: CardType.retro,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(retroSvg, contains('noise'));

      // 测试正念模板
      final mindfulSvg = CardTemplates.getTemplateByType(
        type: CardType.mindful,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(mindfulSvg, contains('paperNoise'));

      // 测试霓虹赛博模板
      final neonCyberSvg = CardTemplates.getTemplateByType(
        type: CardType.neonCyber,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );
      expect(neonCyberSvg, contains('cyberGrid'));
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
      // 验证阴影滤镜 (新命名为 cardShadow)
      expect(svg, contains('filter='));

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

      // 验证现代化配色 (更新后的颜色)
      expect(svg, contains('#7c3aed')); // Violet
      expect(svg, contains('#0891b2')); // Cyan
      expect(svg, contains('#db2777')); // Pink
      expect(svg, contains('stop-opacity'));
      expect(svg, contains('fill-opacity'));
    });

    test('元数据与地点/天气渲染', () {
      final svg = CardTemplates.knowledgeTemplate(
        content: testContent,
        author: testAuthor,
        date: testDate,
        location: '北京',
        weather: '多云',
        temperature: '28℃',
      );
      expect(svg, contains('北京'));
      expect(svg, contains('多云'));
      expect(svg, contains('28℃'));
    });

    test('特殊字符应正确转义', () {
      const contentWithSpecialChars = '这是<特殊>字符&测试"内容"';

      final svg = CardTemplates.quoteTemplate(
        content: contentWithSpecialChars,
        date: testDate,
      );

      // 验证特殊字符被转义
      expect(svg, contains('&lt;'));
      expect(svg, contains('&gt;'));
      expect(svg, contains('&amp;'));
    });
  });
}
