import 'package:flutter/material.dart';
import 'insights_page.dart';
import 'ai_periodic_report_page.dart';

/// AI功能主页面
class AIFeaturesPage extends StatefulWidget {
  const AIFeaturesPage({super.key});

  @override
  State<AIFeaturesPage> createState() => _AIFeaturesPageState();
}

class _AIFeaturesPageState extends State<AIFeaturesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Column(
        children: [
          // 顶部Tab导航
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'AI洞察'),
                Tab(text: '周期报告'),
              ],
              labelColor: theme.primaryColor,
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: theme.primaryColor,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 14),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerHeight: 0,
            ),
          ),

          // Tab内容区域
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                InsightsPage(),
                AIPeriodicReportPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
