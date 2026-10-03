import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/ai_card_prompts.dart';

void main() {
  group('AI卡片提示词测试', () {
    const testContent = '今天学习了Flutter的状态管理，发现Provider模式非常实用，可以有效地管理应用状态。';
    const testAuthor = '张三';
    const testDate = '2024年1月15日';

    test('random-style prompt preserves content and SVG safety constraints',
        () {
      final prompt = AICardPrompts.randomStylePosterPrompt(
        content: testContent,
      );

      expect(prompt, contains(testContent));
      expect(prompt, contains('根据文本内容创造相关的视觉元素'));
      expect(prompt, contains('学习内容：书本、笔、灯泡、大脑、齿轮等'));
      expect(prompt, contains('viewBox="0 0 400 600"'));
      expect(prompt, contains('xmlns="http://www.w3.org/2000/svg"'));
      expect(prompt, contains('只输出完整的SVG代码'));
      expect(prompt, contains('SVG必须以<svg>开头，以</svg>结尾'));
    });

    test(
        'intelligent prompt includes supplied metadata and current design rules',
        () {
      final prompt = AICardPrompts.intelligentCardPrompt(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(prompt, contains(testContent));
      expect(prompt, contains(testAuthor));
      expect(prompt, contains(testDate));
      expect(prompt, contains('弥散光感 (Mesh Gradients)'));
      expect(prompt, contains('磨砂玻璃 (Glassmorphism)'));
      expect(prompt, contains('viewBox="0 0 400 600"'));
      expect(prompt, contains('xmlns="http://www.w3.org/2000/svg"'));
      expect(prompt, contains('元素总数控制在 100 个以内'));
      expect(prompt, contains('严禁输出 Markdown 代码块标记'));
      expect(prompt, contains('严禁添加“摘要：”、“内容：”'));
    });

    test('content-aware prompt retains content, metadata, and design guidance',
        () {
      final prompt = AICardPrompts.contentAwareVisualPrompt(
        content: testContent,
        author: testAuthor,
        date: testDate,
        location: '杭州',
        weather: '晴',
        temperature: '25°C',
        dayPeriod: 'morning',
        source: '测试来源',
        brandName: '测试品牌',
      );

      expect(prompt, contains(testContent));
      expect(prompt, contains('作者：$testAuthor'));
      expect(prompt, contains('日期：$testDate'));
      expect(prompt, contains('地点：杭州'));
      expect(prompt, contains('天气：晴 25°C'));
      expect(prompt, contains('时间段：morning'));
      expect(prompt, contains('来源：测试来源'));
      expect(prompt, contains('应用名 "测试品牌"'));
      expect(prompt, contains('主题呼应'));
      expect(prompt, contains('色彩哲学'));
      expect(prompt, contains('视觉层级'));
      expect(prompt, contains('仅输出纯 SVG 源码'));
    });
  });
}
