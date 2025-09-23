// ignore_for_file: avoid_print
import 'dart:math' as math;

class AIPromptManager {
  /// 本地生成报告洞察（不开启AI时使用）。
  /// 会根据缺失项替换为中性描述，确保总长适中（约40-60字）。
  String formatLocalReportInsight({
    required String periodLabel,
    String? mostTimePeriod,
    String? mostWeather,
    String? topTag,
    required int activeDays,
    required int noteCount,
    required int totalWordCount,
  }) {
    final time = mostTimePeriod ?? '本期时段分布较均衡';
    final weather = mostWeather ?? '天气因素不明显';
    final tag =
        (topTag != null && topTag.trim().isNotEmpty) ? '#$topTag' : '主题尚未收敛';

    // 3种风格模板（除了简约数据型和极简禅意型），随机挑选
    final rng = math.Random();
    final styleIndex = rng.nextInt(3);

    switch (styleIndex) {
      case 0: // 温暖陪伴型
        return _generateWarmCompanionInsight(periodLabel, time, weather, tag,
            activeDays, noteCount, totalWordCount);
      case 1: // 诗意文艺型
        return _generatePoeticInsight(periodLabel, time, weather, tag,
            activeDays, noteCount, totalWordCount);
      case 2: // 成长导师型
        return _generateGrowthMentorInsight(periodLabel, time, weather, tag,
            activeDays, noteCount, totalWordCount);
      default:
        return _generateWarmCompanionInsight(periodLabel, time, weather, tag,
            activeDays, noteCount, totalWordCount);
    }
  }

  /// 温暖陪伴型洞察
  String _generateWarmCompanionInsight(
      String periodLabel,
      String time,
      String weather,
      String tag,
      int activeDays,
      int noteCount,
      int totalWordCount) {
    final templates = [
      '这$periodLabel你坚持了$activeDays天记录，共写下$noteCount篇温暖的文字。看起来你更喜欢在$time书写，$weather是你的创作伙伴，$tag充满了你的思绪。',
      '一个$periodLabel来，你用$activeDays天时光记录了生活的点滴。$time的时候，你写得最多，$weather见证着$tag的绽放。',
      '你在这$periodLabel里坚持了$activeDays天，留下$noteCount篇共$totalWordCount字的珍贵记忆。$time是你最爱的创作时光，$tag在你心中流淌。',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }

  /// 诗意文艺型洞察
  String _generatePoeticInsight(String periodLabel, String time, String weather,
      String tag, int activeDays, int noteCount, int totalWordCount) {
    final templates = [
      '时光如水，你用$activeDays个日夜编织了$noteCount个故事片段。$time是你的缪斯时刻，$weather见证着$tag的绽放。',
      '一$periodLabel光阴里，你在$activeDays个日子种下文字的种子。$time最懂你的心思，$tag在笔尖流淌。',
      '岁月不居，时节如流。这$periodLabel你以$activeDays日为纸，写下$noteCount篇心语。$time时分，$tag与$weather共舞。',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }

  /// 成长导师型洞察
  String _generateGrowthMentorInsight(
      String periodLabel,
      String time,
      String weather,
      String tag,
      int activeDays,
      int noteCount,
      int totalWordCount) {
    final templates = [
      '本$periodLabel你保持了$activeDays天的记录习惯，积累了$totalWordCount字的思考财富。$time的安静最适合你深度思考，$tag值得进一步探索。',
      '这一$periodLabel你在思考的路上走了$activeDays天，留下了$noteCount篇成长足迹。$time激发你的灵感，$tag或许是下一个突破点。',
      '你用$activeDays天的坚持证明了成长的决心，$noteCount篇记录见证着进步。$time是你的黄金思考时段，$tag展现了你的关注焦点。',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }
}

void main() {
  final manager = AIPromptManager();

  // 测试正常情况
  print('=== 测试正常情况 ===');
  final result1 = manager.formatLocalReportInsight(
    periodLabel: '本周',
    mostTimePeriod: '上午',
    mostWeather: '晴天',
    topTag: '生活',
    activeDays: 5,
    noteCount: 10,
    totalWordCount: 500,
  );
  print('结果1: $result1');
  print('长度: ${result1.length}');
  print('是否为空: ${result1.isEmpty}');

  // 测试空值情况
  print('\n=== 测试空值情况 ===');
  final result2 = manager.formatLocalReportInsight(
    periodLabel: '本月',
    mostTimePeriod: null,
    mostWeather: null,
    topTag: null,
    activeDays: 15,
    noteCount: 25,
    totalWordCount: 1200,
  );
  print('结果2: $result2');
  print('长度: ${result2.length}');
  print('是否为空: ${result2.isEmpty}');

  // 测试边界情况
  print('\n=== 测试边界情况 ===');
  final result3 = manager.formatLocalReportInsight(
    periodLabel: '本年',
    mostTimePeriod: '',
    mostWeather: '',
    topTag: '',
    activeDays: 0,
    noteCount: 0,
    totalWordCount: 0,
  );
  print('结果3: $result3');
  print('长度: ${result3.length}');
  print('是否为空: ${result3.isEmpty}');
}
