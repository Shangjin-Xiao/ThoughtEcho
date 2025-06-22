import 'package:flutter/material.dart';
import '../models/quote_model.dart';
import 'annual_report_page.dart';

class AnnualReportDemoPage extends StatelessWidget {
  const AnnualReportDemoPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('年度报告演示')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '年度报告功能演示',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            const Text(
              '这是一个年度报告功能的演示页面\n实际使用时将从数据库读取真实的笔记数据',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => AnnualReportPage(
                          year: 2024,
                          quotes: _generateSampleData(),
                        ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '查看 2024 年度报告',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 16),

            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => AnnualReportPage(
                          year: 2024,
                          quotes: [], // 空数据演示
                        ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '查看空数据状态',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Quote> _generateSampleData() {
    final sampleQuotes = <Quote>[];

    // 生成一些示例数据
    final contents = [
      '今天读了一本好书，受益匪浅。',
      '工作中遇到了一个有趣的技术问题，通过团队合作解决了。',
      '散步时看到夕阳西下，突然想起了童年的回忆。',
      '学习新技能需要耐心和毅力，今天又进步了一点点。',
      '和朋友聊天时发现了新的观点，很有启发。',
      '今天的天气很好，心情也格外舒畅。',
      '看到一篇文章关于时间管理，决定试试新的方法。',
      '项目进展顺利，团队配合得很好。',
      '今天尝试了新的料理，味道还不错。',
      '思考人生意义，觉得当下很珍贵。',
      '完成了一个小目标，给自己点个赞。',
      '读到一句话：行动胜过一切想法。',
      '今天遇到了困难，但最终找到了解决方案。',
      '和家人视频通话，感受到了温暖。',
      '学会了一个新的编程技巧，很实用。',
      '今天的运动让我精神焕发。',
      '看了一部电影，被其中的故事深深打动。',
      '整理房间时发现了很多回忆。',
      '今天的会议很有收获，学到了新知识。',
      '晚上的星空特别美丽，让人心旷神怡。',
    ];

    final tagGroups = [
      ['学习', '成长'],
      ['工作', '技术'],
      ['生活', '感悟'],
      ['阅读', '思考'],
      ['运动', '健康'],
      ['家人', '温暖'],
      ['项目', '团队'],
      ['美食', '尝试'],
      ['电影', '娱乐'],
      ['自然', '美景'],
    ];

    // 生成2024年的数据
    for (int month = 1; month <= 12; month++) {
      // 每个月生成不同数量的笔记
      final notesInMonth = month <= 6 ? month * 2 : (13 - month) * 2;

      for (int i = 0; i < notesInMonth; i++) {
        final day = (i % 28) + 1; // 确保日期有效
        final hour = 8 + (i % 16); // 8-23点
        final minute = i % 60;

        final date = DateTime(2024, month, day, hour, minute);
        final contentIndex = (month * 10 + i) % contents.length;
        final tagGroupIndex = i % tagGroups.length;

        sampleQuotes.add(
          Quote(
            id: 'sample_${month}_$i',
            content: contents[contentIndex],
            date: date.toIso8601String(),
            tagIds: tagGroups[tagGroupIndex],
            categoryId: 'default_category',
          ),
        );
      }
    }

    return sampleQuotes;
  }
}
