import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/quote_model.dart';

class AnnualReportPage extends StatefulWidget {
  final int year;
  final List<Quote> quotes;

  const AnnualReportPage({Key? key, required this.year, required this.quotes})
    : super(key: key);

  @override
  State<AnnualReportPage> createState() => _AnnualReportPageState();
}

class _AnnualReportPageState extends State<AnnualReportPage>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _slideController;
  late PageController _pageController;

  int _currentPage = 0;
  bool _isAnimating = false;

  // 数据统计
  late AnnualStats _stats;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pageController = PageController();

    // 计算年度统计数据
    _calculateStats();

    // 开始动画
    _startAnimations();
  }

  @override
  void dispose() {
    _controller.dispose();
    _slideController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _calculateStats() {
    final yearQuotes =
        widget.quotes.where((quote) {
          final quoteDate = DateTime.parse(quote.date);
          return quoteDate.year == widget.year;
        }).toList();

    _stats = AnnualStats.fromQuotes(yearQuotes, widget.year);
  }

  void _startAnimations() {
    Future.delayed(const Duration(milliseconds: 500), () {
      _controller.forward();
    });
  }

  void _nextPage() {
    if (_currentPage < 6 && !_isAnimating) {
      setState(() {
        _isAnimating = true;
      });

      HapticFeedback.lightImpact();

      _pageController
          .nextPage(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          )
          .then((_) {
            setState(() {
              _isAnimating = false;
            });
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F9FA),
      body: Stack(
        children: [
          // 背景渐变
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors:
                    isDark
                        ? [
                          const Color(0xFF1A1A2E),
                          const Color(0xFF16213E),
                          const Color(0xFF0F0F23),
                        ]
                        : [
                          const Color(0xFFE3F2FD),
                          const Color(0xFFF3E5F5),
                          const Color(0xFFE8F5E8),
                        ],
              ),
            ),
          ),

          // 页面内容
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
              HapticFeedback.selectionClick();
            },
            children: [
              _buildCoverPage(),
              _buildOverviewPage(),
              _buildWritingHabitsPage(),
              _buildTagAnalysisPage(),
              _buildTimelinePage(),
              _buildInsightsPage(),
              _buildEndingPage(),
            ],
          ),

          // 顶部导航
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.white : Colors.black54,
                  ),
                ),
                Text(
                  '${_currentPage + 1} / 7',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                IconButton(
                  onPressed: _shareReport,
                  icon: Icon(
                    Icons.share,
                    color: isDark ? Colors.white : Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          // 底部进度指示器
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(7, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color:
                          _currentPage == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverPage() {
    return GestureDetector(
      onTap: _nextPage,
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 年份标题
            FadeTransition(
              opacity: _controller,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
                  ),
                ),
                child: Text(
                  '${widget.year}',
                  style: const TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    height: 0.9,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 副标题
            FadeTransition(
              opacity: _controller,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
                  ),
                ),
                child: const Text(
                  '你的思想轨迹',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 描述文字
            FadeTransition(
              opacity: _controller,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
                  ),
                ),
                child: Text(
                  'ThoughtEcho Annual Report',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 80),

            // 点击提示
            FadeTransition(
              opacity: _controller,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '点击屏幕开始探索',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewPage() {
    return GestureDetector(
      onTap: _nextPage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '年度概览',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 40),

            // 主要统计卡片
            Expanded(
              child: Column(
                children: [
                  _buildStatCard(
                    icon: Icons.edit_note,
                    title: '总共记录',
                    value: '${_stats.totalNotes}',
                    subtitle: '篇笔记',
                    color: const Color(0xFF6366F1),
                    delay: 0.0,
                  ),

                  const SizedBox(height: 20),

                  _buildStatCard(
                    icon: Icons.sentiment_satisfied_alt,
                    title: '写作天数',
                    value: '${_stats.activeDays}',
                    subtitle: '天',
                    color: const Color(0xFF10B981),
                    delay: 0.1,
                  ),

                  const SizedBox(height: 20),

                  _buildStatCard(
                    icon: Icons.trending_up,
                    title: '最长连续',
                    value: '${_stats.longestStreak}',
                    subtitle: '天',
                    color: const Color(0xFFF59E0B),
                    delay: 0.2,
                  ),

                  const SizedBox(height: 20),

                  _buildStatCard(
                    icon: Icons.local_offer,
                    title: '使用标签',
                    value: '${_stats.totalTags}',
                    subtitle: '个',
                    color: const Color(0xFFEF4444),
                    delay: 0.3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWritingHabitsPage() {
    return GestureDetector(
      onTap: _nextPage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '写作习惯',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 40),

            // 最活跃时间段
            _buildHabitCard(
              title: '最活跃时间',
              content:
                  _stats.mostActiveHour != null
                      ? '${_stats.mostActiveHour}:00 - ${_stats.mostActiveHour! + 1}:00'
                      : '暂无数据',
              icon: Icons.schedule,
              color: const Color(0xFF8B5CF6),
            ),

            const SizedBox(height: 20),

            // 最喜欢的日子
            _buildHabitCard(
              title: '最喜欢的日子',
              content: _stats.mostActiveWeekday ?? '暂无数据',
              icon: Icons.today,
              color: const Color(0xFF06B6D4),
            ),

            const SizedBox(height: 20),

            // 平均字数
            _buildHabitCard(
              title: '平均每篇字数',
              content: '${_stats.averageWordsPerNote.toInt()} 字',
              icon: Icons.text_fields,
              color: const Color(0xFFEC4899),
            ),

            const SizedBox(height: 20),

            // 最长笔记
            _buildHabitCard(
              title: '最长的一篇',
              content: '${_stats.longestNoteWords} 字',
              icon: Icons.article,
              color: const Color(0xFF84CC16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagAnalysisPage() {
    return GestureDetector(
      onTap: _nextPage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '标签分析',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 40),

            if (_stats.topTags.isNotEmpty) ...[
              const Text(
                '最常用的标签',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: ListView.builder(
                  itemCount: _stats.topTags.length.clamp(0, 5),
                  itemBuilder: (context, index) {
                    final tag = _stats.topTags[index];
                    final percentage = (tag.count / _stats.totalNotes * 100);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(
                          AppTheme.cardRadius,
                        ),
                        boxShadow: AppTheme.lightShadow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _getTagColor(index),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tag.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '使用了 ${tag.count} 次 (${percentage.toStringAsFixed(1)}%)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.label_outline,
                      size: 80,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '还没有使用过标签',
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimelinePage() {
    return GestureDetector(
      onTap: _nextPage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '时间轴',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 40),

            Expanded(
              child: ListView.builder(
                itemCount: _stats.monthlyStats.length,
                itemBuilder: (context, index) {
                  final month = _stats.monthlyStats[index];
                  final maxCount = _stats.monthlyStats
                      .map((m) => m.count)
                      .reduce((a, b) => a > b ? a : b);
                  final percentage =
                      maxCount > 0 ? month.count / maxCount : 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      boxShadow: AppTheme.lightShadow,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            '${month.month}月',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: percentage,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${month.count}篇',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsPage() {
    return GestureDetector(
      onTap: _nextPage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '深度洞察',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 40),

            Expanded(
              child: Column(
                children: [
                  _buildInsightCard(
                    icon: Icons.psychology,
                    title: '思考密度',
                    content: _getThinkingDensityText(),
                    color: const Color(0xFF7C3AED),
                  ),

                  const SizedBox(height: 20),

                  _buildInsightCard(
                    icon: Icons.auto_awesome,
                    title: '成长轨迹',
                    content: _getGrowthText(),
                    color: const Color(0xFFF97316),
                  ),

                  const SizedBox(height: 20),

                  _buildInsightCard(
                    icon: Icons.timeline,
                    title: '写作节奏',
                    content: _getWritingRhythmText(),
                    color: const Color(0xFF059669),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndingPage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),

          const SizedBox(height: 32),

          const Text(
            '感谢你的坚持',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            '每一个想法都值得被记录\n每一次记录都是成长的足迹',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
            ),
            child: Text(
              '继续记录 2025',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required double delay,
  }) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(delay, delay + 0.5, curve: Curves.easeOutCubic),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: AppTheme.defaultShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),

            const SizedBox(width: 20),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitCard({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: AppTheme.defaultShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),

              const SizedBox(width: 16),

              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Text(
            content,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTagColor(int index) {
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
    ];
    return colors[index % colors.length];
  }

  String _getThinkingDensityText() {
    if (_stats.averageWordsPerNote > 200) {
      return '你喜欢深度思考，每篇笔记都很详细。这样的习惯帮助你更好地整理思路。';
    } else if (_stats.averageWordsPerNote > 100) {
      return '你的思考简洁而有力，善于抓住要点。这是很好的总结能力。';
    } else {
      return '你习惯记录简短的想法，这样能快速捕捉灵感，是很好的记录习惯。';
    }
  }

  String _getGrowthText() {
    final months = _stats.monthlyStats;
    if (months.length >= 2) {
      final lastMonth = months.last.count;
      final firstMonth = months.first.count;
      if (lastMonth > firstMonth * 1.5) {
        return '你的记录频率越来越高了！从年初到年末，思考和记录的习惯越来越好。';
      } else if (lastMonth < firstMonth * 0.5) {
        return '年初的记录很活跃，也许可以重新找回那时的写作热情。';
      } else {
        return '你保持了稳定的记录节奏，这种坚持很难得！';
      }
    } else {
      return '今年是记录的开始，期待看到更多的思考轨迹。';
    }
  }

  String _getWritingRhythmText() {
    if (_stats.longestStreak >= 7) {
      return '你有很好的写作节奏，最长连续记录了${_stats.longestStreak}天！坚持就是力量。';
    } else if (_stats.longestStreak >= 3) {
      return '你已经建立了不错的记录习惯，继续保持这个节奏。';
    } else {
      return '记录更多是一个习惯，可以尝试每天记录一些小想法。';
    }
  }

  void _shareReport() {
    // TODO: 实现分享功能
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('分享功能即将上线'), duration: Duration(seconds: 2)),
    );
  }
}

class AnnualStats {
  final int year;
  final int totalNotes;
  final int activeDays;
  final int longestStreak;
  final int totalTags;
  final double averageWordsPerNote;
  final int longestNoteWords;
  final int? mostActiveHour;
  final String? mostActiveWeekday;
  final List<TagStat> topTags;
  final List<MonthlyStat> monthlyStats;

  AnnualStats({
    required this.year,
    required this.totalNotes,
    required this.activeDays,
    required this.longestStreak,
    required this.totalTags,
    required this.averageWordsPerNote,
    required this.longestNoteWords,
    this.mostActiveHour,
    this.mostActiveWeekday,
    required this.topTags,
    required this.monthlyStats,
  });

  factory AnnualStats.fromQuotes(List<Quote> quotes, int year) {
    if (quotes.isEmpty) {
      return AnnualStats(
        year: year,
        totalNotes: 0,
        activeDays: 0,
        longestStreak: 0,
        totalTags: 0,
        averageWordsPerNote: 0,
        longestNoteWords: 0,
        topTags: [],
        monthlyStats: [],
      );
    }

    // 计算基本统计
    final totalNotes = quotes.length;
    final totalWords = quotes.fold<int>(
      0,
      (sum, quote) => sum + quote.content.length,
    );
    final averageWordsPerNote = totalWords / totalNotes;
    final longestNoteWords = quotes
        .map((quote) => quote.content.length)
        .reduce((a, b) => a > b ? a : b);

    // 计算活跃天数
    final activeDates =
        quotes.map((quote) {
          final date = DateTime.parse(quote.date);
          return DateTime(date.year, date.month, date.day);
        }).toSet();
    final activeDays = activeDates.length;

    // 计算最长连续天数
    final sortedDates = activeDates.toList()..sort();
    int longestStreak = 0;
    int currentStreak = 1;

    for (int i = 1; i < sortedDates.length; i++) {
      final diff = sortedDates[i].difference(sortedDates[i - 1]).inDays;
      if (diff == 1) {
        currentStreak++;
      } else {
        longestStreak =
            longestStreak > currentStreak ? longestStreak : currentStreak;
        currentStreak = 1;
      }
    }
    longestStreak =
        longestStreak > currentStreak ? longestStreak : currentStreak;

    // 计算标签统计
    final Map<String, int> tagCounts = {};
    for (final quote in quotes) {
      for (final tagId in quote.tagIds) {
        tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
      }
    }

    final topTags =
        tagCounts.entries
            .map((e) => TagStat(name: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    // 计算时间统计
    final hourCounts = <int, int>{};
    final weekdayCounts = <int, int>{};

    for (final quote in quotes) {
      final date = DateTime.parse(quote.date);
      hourCounts[date.hour] = (hourCounts[date.hour] ?? 0) + 1;
      weekdayCounts[date.weekday] = (weekdayCounts[date.weekday] ?? 0) + 1;
    }

    final mostActiveHour =
        hourCounts.entries.isNotEmpty
            ? hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
            : null;

    final weekdayNames = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final mostActiveWeekday =
        weekdayCounts.entries.isNotEmpty
            ? weekdayNames[weekdayCounts.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key]
            : null;

    // 计算月度统计
    final monthlyCounts = <int, int>{};
    for (final quote in quotes) {
      final date = DateTime.parse(quote.date);
      monthlyCounts[date.month] = (monthlyCounts[date.month] ?? 0) + 1;
    }

    final monthlyStats = List.generate(12, (index) {
      final month = index + 1;
      return MonthlyStat(month: month, count: monthlyCounts[month] ?? 0);
    });

    return AnnualStats(
      year: year,
      totalNotes: totalNotes,
      activeDays: activeDays,
      longestStreak: longestStreak,
      totalTags: tagCounts.length,
      averageWordsPerNote: averageWordsPerNote,
      longestNoteWords: longestNoteWords,
      mostActiveHour: mostActiveHour,
      mostActiveWeekday: mostActiveWeekday,
      topTags: topTags,
      monthlyStats: monthlyStats,
    );
  }
}

class TagStat {
  final String name;
  final int count;

  TagStat({required this.name, required this.count});
}

class MonthlyStat {
  final int month;
  final int count;

  MonthlyStat({required this.month, required this.count});
}
