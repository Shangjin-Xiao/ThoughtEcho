import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/ai_card_prompts.dart';

void main() {
  group('AI卡片提示词测试', () {
    const testContent = '今天学习了Flutter的状态管理，发现Provider模式非常实用，可以有效地管理应用状态。';
    const testAuthor = '张三';
    const testDate = '2024年1月15日';

    test('智能内容相关SVG卡片生成提示词', () {
      final prompt = AICardPrompts.randomStylePosterPrompt(content: testContent);

      expect(prompt, isNotNull);
      expect(prompt, contains(testContent));
      expect(prompt, contains('根据文本内容创造相关的视觉元素'));
      expect(prompt, contains('学习内容：书本、笔、灯泡、大脑、齿轮等'));
      expect(prompt, contains('viewBox="0 0 400 600"'));
      expect(prompt, contains('xmlns="http://www.w3.org/2000/svg"'));
    });

    test('智能内容相关卡片生成提示词（增强版）', () {
      final prompt = AICardPrompts.intelligentCardPrompt(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(prompt, isNotNull);
      expect(prompt, contains(testContent));
      expect(prompt, contains(testAuthor));
      expect(prompt, contains(testDate));
      expect(prompt, contains('内容分析和视觉元素匹配'));
      expect(prompt, contains('学习/知识类内容'));
      expect(prompt, contains('工作/职场类内容'));
      expect(prompt, contains('情感/心情类内容'));
    });

    test('内容相关视觉元素增强提示词', () {
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: testContent);

      expect(prompt, isNotNull);
      expect(prompt, contains(testContent));
      expect(prompt, contains('内容主题识别'));
      expect(prompt, contains('相关图标选择'));
      expect(prompt, contains('装饰元素设计'));
      expect(prompt, contains('色彩情感匹配'));
      expect(prompt, contains('布局设计'));
    });

    test('学习内容的视觉元素建议', () {
      const learningContent = '今天学习了机器学习的基础概念，包括监督学习和无监督学习的区别。';
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: learningContent);

      expect(prompt, contains('学习：书本、笔记本、灯泡、大脑、学位帽'));
      expect(prompt, contains('蓝色系（#3B82F6, #1E40AF, #6366F1）'));
      expect(prompt, contains('相关图标选择'));
    });

    test('工作内容的视觉元素建议', () {
      const workContent = '完成了项目的第一阶段开发，团队协作效率很高，按时交付了所有功能模块。';
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: workContent);

      expect(prompt, contains('工作：电脑、图表、目标、时钟、文件夹'));
      expect(prompt, contains('灰蓝系（#475569, #64748B, #334155）'));
      expect(prompt, contains('装饰元素设计'));
    });

    test('情感内容的视觉元素建议', () {
      const emotionalContent = '今天心情特别好，阳光明媚，和朋友一起度过了愉快的下午时光。';
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: emotionalContent);

      expect(prompt, contains('情感：心形、花朵、星星、彩虹、太阳'));
      expect(prompt, contains('粉色系（#F472B6, #EC4899, #BE185D）'));
      expect(prompt, contains('色彩情感匹配'));
    });

    test('技术内容的视觉元素建议', () {
      const techContent = '实现了一个基于React的前端架构，使用了最新的Hooks API和Context进行状态管理。';
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: techContent);

      expect(prompt, contains('技术：齿轮、电路、网络、代码符号、芯片'));
      expect(prompt, contains('青色系（#06B6D4, #0891B2, #0E7490）'));
      expect(prompt, contains('布局设计'));
    });

    test('自然内容的视觉元素建议', () {
      const natureContent = '春天来了，公园里的樱花盛开，鸟儿在枝头歌唱，一切都充满了生机。';
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: natureContent);

      expect(prompt, contains('自然：树叶、山峰、水滴、云朵、动物'));
      expect(prompt, contains('绿色系（#10B981, #059669, #047857）'));
      expect(prompt, contains('自然元素：叶子、花瓣、星点、光晕'));
    });

    test('哲学内容的视觉元素建议', () {
      const philosophicalContent = '人生的意义在于不断地思考和探索，每一次的反思都让我们更接近真理。';
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: philosophicalContent);

      expect(prompt, contains('艺术：画笔、调色板、音符、戏剧面具、相机'));
      expect(prompt, contains('学习/知识：蓝色系（#3B82F6, #1E40AF, #6366F1）'));
      expect(prompt, contains('抽象图案：渐变形状、纹理、图案'));
    });

    test('提示词包含必要的技术规格', () {
      final prompt = AICardPrompts.intelligentCardPrompt(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(prompt, contains('viewBox="0 0 400 600"'));
      expect(prompt, contains('xmlns="http://www.w3.org/2000/svg"'));
      expect(prompt, contains('SVG元素总数控制在60个以内'));
      expect(prompt, contains('system-ui, Arial, sans-serif'));
      expect(prompt, contains('只输出完整的SVG代码'));
    });

    test('提示词强调视觉元素的重要性', () {
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: testContent);

      expect(prompt, contains('视觉元素创作要求'));
      expect(prompt, contains('确保视觉元素与内容高度相关'));
      expect(prompt, contains('相关图标选择'));
      expect(prompt, contains('装饰元素设计'));
    });

    test('提示词包含具体的实现指南', () {
      final prompt = AICardPrompts.intelligentCardPrompt(
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(prompt, contains('背景设计'));
      expect(prompt, contains('主要图标'));
      expect(prompt, contains('装饰元素'));
      expect(prompt, contains('文字排版'));
      expect(prompt, contains('整体平衡'));
    });

    test('提示词包含详细的色彩指导', () {
      final prompt = AICardPrompts.contentAwareVisualPrompt(content: testContent);

      expect(prompt, contains('#3B82F6')); // 蓝色
      expect(prompt, contains('#10B981')); // 绿色
      expect(prompt, contains('#F59E0B')); // 橙色
      expect(prompt, contains('#EC4899')); // 粉色
      expect(prompt, contains('#06B6D4')); // 青色
    });
  });
}
