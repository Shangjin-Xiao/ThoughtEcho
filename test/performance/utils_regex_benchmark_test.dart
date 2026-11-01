import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/agent_history_builder.dart';
import 'package:thoughtecho/utils/ai_prompt_manager.dart';
import 'package:thoughtecho/utils/version_utils.dart';
import 'package:thoughtecho/models/chat_message.dart';

void main() {
  test('Utils RegExp benchmark test', () {
    const iterations = 50000;

    // 1. AgentHistoryBuilder benchmark
    final messages = List<ChatMessage>.generate(
      10,
      (index) => ChatMessage(
        id: 'msg_$index',
        role: 'user',
        isUser: true,
        content: 'This is a test message   with   extra    spaces \n\n $index',
        timestamp: DateTime.now(),
      ),
    );

    final historyStopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      AgentHistoryBuilder.build(messages);
    }
    historyStopwatch.stop();
    print(
        'AgentHistoryBuilder.build $iterations times elapsed: ${historyStopwatch.elapsedMilliseconds} ms');

    // 2. compareVersions benchmark
    final versionStopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      compareVersions('v1.2.3+100', '1.2.4-beta');
      compareVersions('2.0.0', 'v2.0.0-rc.1');
    }
    versionStopwatch.stop();
    print(
        'compareVersions $iterations times elapsed: ${versionStopwatch.elapsedMilliseconds} ms');

    // 3. AIPromptManager formatLocalReportInsight benchmark
    final promptManager = AIPromptManager();
    final insightStopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      promptManager.formatLocalReportInsight(
        periodLabel: '本周',
        mostTimePeriod: 'morning',
        mostWeather: 'clear',
        topTag: '## 读书笔记',
        activeDays: 5,
        noteCount: 12,
        totalWordCount: 3500,
        seed: i,
      );
    }
    insightStopwatch.stop();
    print(
        'formatLocalReportInsight $iterations times elapsed: ${insightStopwatch.elapsedMilliseconds} ms');

    // Verify correct logic output
    expect(compareVersions('v1.2.3', '1.2.3'), 0);
    expect(compareVersions('v1.2.4', '1.2.3'), 1);
    expect(compareVersions('1.2.2', 'v1.2.3'), -1);
  });
}
