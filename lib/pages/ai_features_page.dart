import 'package:flutter/material.dart';
import 'insights_page.dart';
import 'ai_periodic_report_page.dart';
import 'ai_settings_page.dart';

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
    _tabController.addListener(() {
      setState(() {}); // 重建UI以更新按钮状态
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 极简顶部导航 - 只有文字，无背景
          Container(
            height: 20,
            margin: const EdgeInsets.only(top: 4),
            child: Stack(
              children: [
                // 居中的导航文字
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _tabController.animateTo(0),
                        child: Text(
                          'AI洞察',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _tabController.index == 0 ? FontWeight.w600 : FontWeight.normal,
                            color: _tabController.index == 0 
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 1,
                        height: 12,
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                      ),
                      GestureDetector(
                        onTap: () => _tabController.animateTo(1),
                        child: Text(
                          'AI周期报告',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _tabController.index == 1 ? FontWeight.w600 : FontWeight.normal,
                            color: _tabController.index == 1 
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 右侧设置按钮
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AISettingsPage()),
                      );
                    },
                    child: Icon(
                      Icons.settings,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [InsightsPage(), AIPeriodicReportPage()],
            ),
          ),
        ],
      ),
    );
  }
}

/// AI功能卡片组件
class AIFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color? color;

  const AIFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.primaryColor;

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: cardColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
