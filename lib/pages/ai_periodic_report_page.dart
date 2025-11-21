import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/svg_to_image_service.dart';
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../models/weather_data.dart';
import '../services/database_service.dart';
import '../services/ai_card_generation_service.dart';
import '../services/ai_service.dart';
import '../services/settings_service.dart';
import '../services/insight_history_service.dart';
import '../services/weather_service.dart';
import '../widgets/svg_card_widget.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';
import '../utils/icon_utils.dart';
import '../constants/app_constants.dart'; // 导入应用常量

/// AI周期报告页面
class AIPeriodicReportPage extends StatefulWidget {
  const AIPeriodicReportPage({super.key});

  @override
  State<AIPeriodicReportPage> createState() => _AIPeriodicReportPageState();
}

class _AIPeriodicReportPageState extends State<AIPeriodicReportPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // 折叠状态
  bool _isTimeSelectorCollapsed = false;

  // 时间范围选择
  String _selectedPeriod = 'week'; // week, month, year
  DateTime _selectedDate = DateTime.now();

  // 数据状态
  List<Quote> _periodQuotes = [];
  List<GeneratedCard> _featuredCards = [];
  bool _isLoadingData = false;
  bool _isGeneratingCards = false;
  int? _selectedCardIndex;

  // 新增：周期"最多"统计与洞察
  String? _mostDayPeriod; // 晨曦/午后/黄昏/夜晚
  String? _mostWeather; // 晴/雨/多云
  String? _mostTopTag; // 标签名
  int _totalWordCount = 0;
  String? _notesPreview;

  // 新增：用于显示的中文文本和图标
  String? _mostDayPeriodDisplay; // 时段的中文显示
  IconData? _mostDayPeriodIcon; // 时段图标
  String? _mostWeatherDisplay; // 天气的中文显示
  IconData? _mostWeatherIcon; // 天气图标
  dynamic _mostTopTagIcon; // 标签图标（可能是IconData或emoji字符串）

  String _insightText = '';
  bool _insightLoading = false;
  StreamSubscription<String>? _insightSub;

  // 新增：流式显示动画控制器
  AnimationController? _animatedTextController;

  // 新增：控制动画是否应该执行的标志
  bool _shouldAnimateOverview = true;
  bool _shouldAnimateCards = true;
  String _dataKey = ''; // 用于跟踪数据版本

  // 服务
  AICardGenerationService? _aiCardService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    // 初始化流式文本动画控制器
    _animatedTextController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _loadPeriodData();
  }

  void _onTabChanged() {
    setState(() {
      if (_tabController.indexIsChanging) {
        // 切换tab时清除选中状态，并禁用动画（因为只是视图切换，数据没变）
        _selectedCardIndex = null;
        // Tab切换时不播放动画，保持即时响应
        _shouldAnimateOverview = false;
        _shouldAnimateCards = false;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 初始化AI卡片生成服务
    if (_aiCardService == null) {
      final aiService = context.read<AIService>();
      final settingsService = context.read<SettingsService>();
      _aiCardService = AICardGenerationService(aiService, settingsService);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _insightSub?.cancel();
    _animatedTextController?.dispose();
    super.dispose();
  }

  /// 加载周期数据
  Future<void> _loadPeriodData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      final databaseService = context.read<DatabaseService>();
      final quotes = await databaseService.getUserQuotes();

      // 根据选择的时间范围筛选笔记
      final filteredQuotes = _filterQuotesByPeriod(quotes);

      // 更新数据版本key，触发动画
      final newDataKey = '${_selectedPeriod}_${_selectedDate.millisecondsSinceEpoch}';
      final dataChanged = newDataKey != _dataKey;

      setState(() {
        _periodQuotes = filteredQuotes;
        _isLoadingData = false;
        _dataKey = newDataKey;
        // 只在数据真正变化时才播放动画
        _shouldAnimateOverview = dataChanged;
        _shouldAnimateCards = dataChanged;
      });

      // 计算“最多”指标并触发洞察
      await _computeExtrasAndInsight();
    } catch (e) {
      setState(() {
        _isLoadingData = false;
      });
      AppLogger.e('加载周期数据失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
            content: Text('加载数据失败: $e'),
            duration: AppConstants.snackBarDurationError));
      }
    }
  }

  Future<void> _computeExtrasAndInsight() async {
    // 计算总字数
    final totalWords =
        _periodQuotes.fold<int>(0, (sum, q) => sum + q.content.length);

    // 最常见时间段
    final Map<String, int> periodCounts = {};
    for (final q in _periodQuotes) {
      final p = q.dayPeriod?.trim();
      if (p != null && p.isNotEmpty) {
        periodCounts[p] = (periodCounts[p] ?? 0) + 1;
      }
    }
    final mostPeriod = periodCounts.entries.isNotEmpty
        ? periodCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key
        : null;

    // 最常见天气 - 按分类统计（小雨、大雨、雷雨归为"雨"类）
    final Map<String, int> weatherCategoryCounts = {};
    for (final q in _periodQuotes) {
      final w = q.weather?.trim();
      if (w != null && w.isNotEmpty) {
        // 先尝试通过key获取分类，如果失败则直接用原值
        String? category = WeatherService.getFilterCategoryByWeatherKey(w);
        if (category == null) {
          // 如果是中文描述，尝试反查key再获取分类
          final key = WeatherCodeMapper.getKeyByDescription(w);
          if (key != null) {
            category = WeatherService.getFilterCategoryByWeatherKey(key);
          }
        }
        final finalCategory = category ?? w; // 如果找不到分类就用原值
        weatherCategoryCounts[finalCategory] =
            (weatherCategoryCounts[finalCategory] ?? 0) + 1;
      }
    }
    final mostWeather = weatherCategoryCounts.entries.isNotEmpty
        ? weatherCategoryCounts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key
        : null;

    // 最常用标签（根据tagIds统计，然后映射为名称）
    String? topTagName;
    String? topTagId;
    dynamic topTagIcon;
    try {
      final Map<String, int> tagCounts = {};
      for (final q in _periodQuotes) {
        for (final tagId in q.tagIds) {
          tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
        }
      }
      if (tagCounts.isNotEmpty) {
        topTagId =
            tagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        final db = context.read<DatabaseService>();
        final cats = await db.getCategories();
        final category =
            cats.firstWhere((c) => c.id == topTagId, orElse: () => cats.first);
        topTagName = category.name;
        topTagIcon = IconUtils.getDisplayIcon(category.iconName);
      }
    } catch (_) {
      // 如解析失败，保持null
    }

    // 笔记片段预览（最多5条，每条截断80字）
    final samples = _periodQuotes.take(5).map((q) {
      var t = q.content.trim().replaceAll('\n', ' ');
      if (t.length > 80) t = '${t.substring(0, 80)}…';
      return '- $t';
    }).join('\n');

    // 处理时段显示：转换为中文标签
    String? dayPeriodDisplay;
    IconData? dayPeriodIcon;
    if (mostPeriod != null) {
      dayPeriodDisplay = TimeUtils.getDayPeriodLabel(mostPeriod);
      dayPeriodIcon = TimeUtils.getDayPeriodIcon(dayPeriodDisplay);
    }

    // 处理天气显示：转换为中文
    String? weatherDisplay;
    IconData? weatherIcon;
    if (mostWeather != null) {
      // 如果是筛选分类key，直接使用分类标签
      if (WeatherService.filterCategoryToLabel.containsKey(mostWeather)) {
        weatherDisplay = WeatherService.filterCategoryToLabel[mostWeather];
        weatherIcon = WeatherService.getFilterCategoryIcon(mostWeather);
      } else {
        // 否则按原逻辑处理
        weatherDisplay = WeatherCodeMapper.getDescription(mostWeather);
        weatherIcon = WeatherCodeMapper.getIcon(mostWeather);

        // 如果返回的是"未知"，说明mostWeather可能已经是中文描述
        if (weatherDisplay == '未知') {
          weatherDisplay = mostWeather;
          // 反向匹配：根据中文描述找到key以获取更准确的图标
          final key = WeatherCodeMapper.getKeyByDescription(mostWeather);
          weatherIcon =
              key != null ? WeatherCodeMapper.getIcon(key) : Icons.cloud_queue;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _totalWordCount = totalWords;
      _mostDayPeriod = mostPeriod;
      _mostWeather = mostWeather;
      _mostTopTag = topTagName;
      _notesPreview = samples.isEmpty ? null : samples;

      // 设置显示用的中文文本和图标
      _mostDayPeriodDisplay = dayPeriodDisplay;
      _mostDayPeriodIcon = dayPeriodIcon;
      _mostWeatherDisplay = weatherDisplay;
      _mostWeatherIcon = weatherIcon;
      _mostTopTagIcon = topTagIcon;
    });

    _maybeStartInsight();
  }

  void _maybeStartInsight() {
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final useAI = settings.reportInsightsUseAI;
    final periodLabel = '本${_getPeriodName()}';
    final activeDays = _getActiveDays();
    final noteCount = _periodQuotes.length;

    _insightSub?.cancel();
    if (useAI) {
      setState(() {
        _insightText = '';
        _insightLoading = true;
      });
      final ai = context.read<AIService>();

      // 准备完整的笔记内容用于AI分析
      final fullNotesContent = _periodQuotes.map((quote) {
        final date = DateTime.parse(quote.date);
        final dateStr = '${date.month}月${date.day}日';
        var content = quote.content.trim();

        // 添加位置信息
        if (quote.location != null && quote.location!.isNotEmpty) {
          content = '【$dateStr·${quote.location}】$content';
        } else {
          content = '【$dateStr】$content';
        }

        // 添加天气信息
        if (quote.weather != null && quote.weather!.isNotEmpty) {
          final w = quote.weather!.trim();
          // 优先把英文key映射为中文描述
          final wDesc = WeatherCodeMapper.getDescription(w);
          final display = wDesc == '未知' ? w : wDesc;
          content += ' （天气：$display）';
        }

        return content;
      }).join('\n\n');

      _insightSub = ai
          .streamReportInsight(
        periodLabel: periodLabel,
        mostTimePeriod: _mostDayPeriodDisplay ?? _mostDayPeriod,
        mostWeather: _mostWeatherDisplay ?? _mostWeather,
        topTag: _mostTopTag,
        activeDays: activeDays,
        noteCount: noteCount,
        totalWordCount: _totalWordCount,
        notesPreview: _notesPreview,
        fullNotesContent: fullNotesContent, // 传递完整内容
      )
          .listen(
        (chunk) {
          if (!mounted) return;
          setState(() {
            _insightText += chunk;
          });

          // 触发文字动画，让新内容渐进显示
          _animatedTextController?.reset();
          _animatedTextController?.forward();
        },
        onError: (_) {
          if (!mounted) return;
          final local = context.read<AIService>().buildLocalReportInsight(
                periodLabel: periodLabel,
                mostTimePeriod: _mostDayPeriodDisplay ?? _mostDayPeriod,
                mostWeather: _mostWeatherDisplay ?? _mostWeather,
                topTag: _mostTopTag,
                activeDays: activeDays,
                noteCount: noteCount,
                totalWordCount: _totalWordCount,
              );
          setState(() {
            _insightText = local;
            _insightLoading = false;
          });

          // 本地洞察也需要动画
          _animatedTextController?.reset();
          _animatedTextController?.forward();
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _insightLoading = false;
          });

          // 保存洞察到历史记录
          if (_insightText.isNotEmpty) {
            _saveInsightToHistory();
          }
        },
      );
    } else {
      // 调试：记录本地生成洞察的参数
      AppLogger.d(
          '开始本地生成洞察 - useAI: $useAI, periodLabel: $periodLabel, activeDays: $activeDays, noteCount: $noteCount, totalWordCount: $_totalWordCount');
      AppLogger.d(
          '本地生成洞察参数 - mostTimePeriod: ${_mostDayPeriodDisplay ?? _mostDayPeriod}, mostWeather: ${_mostWeatherDisplay ?? _mostWeather}, topTag: $_mostTopTag');

      final local = context.read<AIService>().buildLocalReportInsight(
            periodLabel: periodLabel,
            mostTimePeriod: _mostDayPeriodDisplay ?? _mostDayPeriod,
            mostWeather: _mostWeatherDisplay ?? _mostWeather,
            topTag: _mostTopTag,
            activeDays: activeDays,
            noteCount: noteCount,
            totalWordCount: _totalWordCount,
          );

      // 调试：记录本地生成的结果
      AppLogger.d(
          '本地生成洞察结果 - 长度: ${local.length}, 内容: ${local.isNotEmpty ? local.substring(0, local.length > 50 ? 50 : local.length) : "空字符串"}');

      setState(() {
        _insightText = local;
        _insightLoading = false;
      });

      // 本地洞察也需要动画
      _animatedTextController?.reset();
      _animatedTextController?.forward();

      // 保存洞察到历史记录
      if (_insightText.isNotEmpty) {
        _saveInsightToHistory();
      }
    }
  }

  /// 根据时间范围筛选笔记
  List<Quote> _filterQuotesByPeriod(List<Quote> quotes) {
    final now = _selectedDate;
    DateTime startDate;
    DateTime endDate;

    switch (_selectedPeriod) {
      case 'week':
        // 本周（周一到周日）
        final weekday = now.weekday;
        startDate = now.subtract(Duration(days: weekday - 1));
        endDate = startDate.add(const Duration(days: 6));
        break;
      case 'month':
        // 本月
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case 'year':
        // 本年
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        break;
      default:
        return quotes;
    }

    return quotes.where((quote) {
      final quoteDate = DateTime.parse(quote.date);
      return quoteDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
          quoteDate.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();
  }

  /// 保存洞察到历史记录
  Future<void> _saveInsightToHistory() async {
    try {
      final insightService = context.read<InsightHistoryService>();

      // 获取当前周期的标签
      String periodLabel = '';
      switch (_selectedPeriod) {
        case 'week':
          periodLabel = '本周';
          break;
        case 'month':
          periodLabel = '本月';
          break;
        case 'year':
          periodLabel = '${_selectedDate.year}年';
          break;
        default:
          periodLabel = _selectedPeriod;
      }

      await insightService.addInsight(
        insight: _insightText,
        periodType: _selectedPeriod,
        periodLabel: periodLabel,
        isAiGenerated: true,
      );

      logDebug(
          '已保存洞察到历史记录: ${_insightText.substring(0, _insightText.length > 50 ? 50 : _insightText.length)}...',
          source: 'AIPeriodicReportPage');
    } catch (e) {
      logError('保存洞察到历史记录失败: $e', error: e, source: 'AIPeriodicReportPage');
    }
  }

  /// 生成精选卡片
  Future<void> _generateFeaturedCards() async {
    if (_aiCardService == null || _periodQuotes.isEmpty || _isGeneratingCards) {
      return;
    }

    setState(() {
      _isGeneratingCards = true;
    });

    try {
      // 选择最有代表性的笔记（最多6张卡片）
      final selectedQuotes = _selectRepresentativeQuotes(_periodQuotes);

      final cards = await _aiCardService!.generateFeaturedCards(
        selectedQuotes,
        maxCards: 6,
      );

      setState(() {
        _featuredCards = cards;
        _isGeneratingCards = false;
      });
    } catch (e) {
      setState(() {
        _isGeneratingCards = false;
      });
      AppLogger.e('生成精选卡片失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('生成卡片失败: $e'),
              duration: AppConstants.snackBarDurationError),
        );
      }
    }
  }

  /// 选择有代表性的笔记
  List<Quote> _selectRepresentativeQuotes(List<Quote> quotes) {
    // 按内容长度和多样性选择
    final sortedQuotes = List<Quote>.from(quotes);

    // 优先选择内容丰富的笔记
    sortedQuotes.sort((a, b) => b.content.length.compareTo(a.content.length));

    // 选择前6条，确保多样性
    final selected = <Quote>[];
    final usedKeywords = <String>{};

    for (final quote in sortedQuotes) {
      if (selected.length >= 6) break;

      // 简单的关键词去重逻辑
      final words = quote.content.toLowerCase().split(' ');
      final hasNewKeyword = words.any(
        (word) => word.length > 3 && !usedKeywords.contains(word),
      );

      if (hasNewKeyword || selected.isEmpty) {
        selected.add(quote);
        usedKeywords.addAll(words.where((word) => word.length > 3));
      }
    }

    return selected;
  }

  String _getPeriodName() {
    switch (_selectedPeriod) {
      case 'week':
        return '周';
      case 'month':
        return '月';
      case 'year':
        return '年';
      default:
        return '期间';
    }
  }

  String _getDateRangeText() {
    final now = _selectedDate;
    switch (_selectedPeriod) {
      case 'week':
        final weekday = now.weekday;
        final startDate = now.subtract(Duration(days: weekday - 1));
        final endDate = startDate.add(const Duration(days: 6));
        return '${startDate.month}月${startDate.day}日 - ${endDate.month}月${endDate.day}日';
      case 'month':
        return '${now.year}年${now.month}月';
      case 'year':
        return '${now.year}年';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 现代化标签栏
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildTabItem(0, '数据概览', Icons.analytics_outlined),
              _buildTabItem(1, '精选卡片', Icons.auto_awesome_outlined),
            ],
          ),
        ),
        // 可折叠的时间选择器
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: _isTimeSelectorCollapsed ? 60 : null,
          child: _buildTimeSelector(),
        ),
        // 内容区域
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                // 向上滚动时折叠
                if (notification.scrollDelta! > 10 &&
                    !_isTimeSelectorCollapsed) {
                  setState(() {
                    _isTimeSelectorCollapsed = true;
                  });
                }
                // 向下滚动时展开
                else if (notification.scrollDelta! < -10 &&
                    _isTimeSelectorCollapsed) {
                  setState(() {
                    _isTimeSelectorCollapsed = false;
                  });
                }
              }
              return false;
            },
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDataOverview(),
                _buildFeaturedCards(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建标签项
  Widget _buildTabItem(int index, String title, IconData icon) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建时间选择器
  Widget _buildTimeSelector() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isTimeSelectorCollapsed = !_isTimeSelectorCollapsed;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState: _isTimeSelectorCollapsed
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: _buildCollapsedTimeSelector(),
          secondChild: _buildExpandedTimeSelector(),
        ),
      ),
    );
  }

  /// 构建折叠状态的时间选择器
  Widget _buildCollapsedTimeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.date_range,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '${_getPeriodName()} - ${_getDateRangeText()}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const Spacer(),
          Icon(
            Icons.expand_more,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// 构建展开状态的时间选择器
  Widget _buildExpandedTimeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '时间范围',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  onPressed: () => _selectDate(),
                  icon: Icon(
                    Icons.calendar_today,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  tooltip: '选择具体日期',
                  iconSize: 20,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_less,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'week',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.view_week, size: 16),
                    SizedBox(width: 4),
                    Text('本周'),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'month',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_view_month, size: 16),
                    SizedBox(width: 4),
                    Text('本月'),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'year',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.today, size: 16),
                    SizedBox(width: 4),
                    Text('本年'),
                  ],
                ),
              ),
            ],
            selected: {_selectedPeriod},
            onSelectionChanged: (Set<String> selection) {
              setState(() {
                _selectedPeriod = selection.first;
                // 切换时间范围时，重置生成的内容
                _featuredCards = [];
                _selectedCardIndex = null;
              });
              _loadPeriodData();
            },
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// 选择日期
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        // 切换日期时，重置生成的内容
        _featuredCards = [];
        _selectedCardIndex = null;
      });
      _loadPeriodData();
    }
  }

  /// 构建数据概览
  Widget _buildDataOverview() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalNotes = _periodQuotes.length;
    final totalWords = _periodQuotes.fold<int>(
      0,
      (sum, quote) => sum + quote.content.length,
    );
    final avgWords = totalNotes > 0 ? (totalWords / totalNotes).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题优化：添加图标和更好的视觉层次
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据概览',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    Text(
                      _getDateRangeText(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 统计卡片网格 - 根据标志决定是否播放动画
          TweenAnimationBuilder<double>(
            key: ValueKey('stats1_$_dataKey'), // 添加key确保动画只在数据变化时触发
            duration: _shouldAnimateOverview 
                ? const Duration(milliseconds: 600)
                : Duration.zero, // 不动画时立即显示
            tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Row(
                    children: [
                      Expanded(
                          child: _buildStatCard('笔记数量', '$totalNotes', '条',
                              Icons.note_alt_outlined)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildStatCard(
                              '总字数', '$totalWords', '字', Icons.text_fields)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            key: ValueKey('stats2_$_dataKey'),
            duration: _shouldAnimateOverview
                ? const Duration(milliseconds: 800)
                : Duration.zero,
            tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Row(
                    children: [
                      Expanded(
                          child: _buildStatCard('平均字数', '$avgWords', '字/条',
                              Icons.calculate_outlined)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard('活跃天数', '${_getActiveDays()}',
                            '天', Icons.calendar_today_outlined),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // 新增：三个"最多"指标 - 根据标志决定是否播放动画
          TweenAnimationBuilder<double>(
            key: ValueKey('stats3_$_dataKey'),
            duration: _shouldAnimateOverview
                ? const Duration(milliseconds: 1000)
                : Duration.zero,
            tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCardWithCustomIcon(
                            '常见时段',
                            _mostDayPeriodDisplay ?? '暂无',
                            '',
                            _mostDayPeriodIcon ?? Icons.timelapse),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCardWithCustomIcon(
                            '常见天气',
                            _mostWeatherDisplay ?? '暂无',
                            '',
                            _mostWeatherIcon ?? Icons.cloud_queue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCardWithTagIcon(
                            '常用标签', _mostTopTag ?? '暂无', ''),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // 洞察小灯泡（移到常用标签下面）
          _buildInsightBulbBar(),
          const SizedBox(height: 24),

          // 本周期收藏最多（放在洞察下面，最近笔记上面）- 根据标志决定是否播放动画
          if (_periodQuotes.isNotEmpty) ...[
            TweenAnimationBuilder<double>(
              key: ValueKey('favorites_$_dataKey'),
              duration: _shouldAnimateOverview
                  ? const Duration(milliseconds: 800)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: _buildPeriodTopFavoritesSection(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // 最近笔记部分 - 根据标志决定是否播放动画
          if (_periodQuotes.isNotEmpty) ...[
            TweenAnimationBuilder<double>(
              key: ValueKey('recent_$_dataKey'),
              duration: _shouldAnimateOverview
                  ? const Duration(milliseconds: 1000)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '最近笔记',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._periodQuotes.take(3).map(
                              (quote) => TweenAnimationBuilder<double>(
                                duration: Duration(
                                    milliseconds: 600 +
                                        (_periodQuotes.indexOf(quote) * 200)),
                                tween: Tween(begin: 0.0, end: 1.0),
                                builder: (context, animValue, child) {
                                  return Transform.translate(
                                    offset: Offset(0, 15 * (1 - animValue)),
                                    child: Opacity(
                                      opacity: animValue,
                                      child: _buildQuotePreview(quote),
                                    ),
                                  );
                                },
                              ),
                            ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ] else ...[
            // 空状态优化
            _buildEmptyState(),
          ],
        ],
      ),
    );
  }

  // 构建“本周期收藏最多”的展示区域
  Widget _buildPeriodTopFavoritesSection() {
    // 过滤出有心形点击的笔记，并按次数排序
    final List<Quote> favorited = _periodQuotes
        .where((q) => q.favoriteCount > 0)
        .toList()
      ..sort((a, b) => b.favoriteCount.compareTo(a.favoriteCount));

    if (favorited.isEmpty) {
      // 若本周期没有心形点击，显示一个轻量提示
      return TweenAnimationBuilder<double>(
        key: ValueKey('favorites_empty_$_dataKey'),
        duration: _shouldAnimateOverview
            ? const Duration(milliseconds: 600)
            : Duration.zero,
        tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Opacity(
              opacity: value,
              child: Row(
                children: [
                  Icon(
                    Icons.favorite_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本周期暂无喜爱记录，去给喜欢的笔记点个心吧！',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          key: ValueKey('favorites_title_$_dataKey'),
          duration: _shouldAnimateOverview
              ? const Duration(milliseconds: 500)
              : Duration.zero,
          tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      size: 20,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '本周期收藏最多',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        ...favorited.take(3).map(
              (q) => TweenAnimationBuilder<double>(
                key: ValueKey('favorite_${q.id}_$_dataKey'),
                duration: _shouldAnimateOverview
                    ? Duration(milliseconds: 600 + (favorited.indexOf(q) * 150))
                    : Duration.zero,
                tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, 15 * (1 - value)),
                    child: Opacity(
                      opacity: value,
                      child: _buildFavoritePreviewChip(q),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }

  // 一个紧凑的收藏预览块 - 优化视觉效果
  Widget _buildFavoritePreviewChip(Quote quote) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.lightImpact();
            // 可以添加跳转到笔记详情的逻辑
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade100, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 800),
                  tween: Tween(begin: 0.8, end: 1.0),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.shade200,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.favorite,
                                color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              '${quote.favoriteCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    quote.content.length > 80
                        ? '${quote.content.substring(0, 80)}...'
                        : quote.content,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 洞察小灯泡组件 - 支持流式显示
  Widget _buildInsightBulbBar() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1500),
                tween: Tween(begin: 0.8, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: _insightLoading ? value : 1.0,
                    child: Icon(
                      Icons.lightbulb,
                      color: _insightLoading
                          ? Colors.amber.withValues(alpha: value)
                          : Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.3),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _insightLoading
                    ? Column(
                        key: const ValueKey('loading'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '正在生成本${_getPeriodName()}洞察…',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 2000),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              return LinearProgressIndicator(
                                value: _insightLoading ? null : 1.0,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              );
                            },
                          ),
                        ],
                      )
                    : Container(
                        key: ValueKey('content-${_insightText.length}'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: _insightText.isEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '暂无洞察',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              height: 1.4,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              : AnimatedBuilder(
                                  animation: _animatedTextController!,
                                  builder: (context, child) {
                                    final animatedText = _insightText.substring(
                                        0,
                                        (_insightText.length *
                                                _animatedTextController!.value)
                                            .round());
                                    return Text(
                                      animatedText,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(height: 1.5),
                                    );
                                  },
                                ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatCard(String title, String value, String unit,
      [IconData? icon]) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建带自定义图标的统计卡片
  Widget _buildStatCardWithCustomIcon(
      String title, String value, String unit, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建带标签图标的统计卡片
  Widget _buildStatCardWithTagIcon(String title, String value, String unit) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 显示标签图标
                if (_mostTopTagIcon != null) ...[
                  if (_mostTopTagIcon is IconData)
                    Icon(
                      _mostTopTagIcon as IconData,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  else
                    Text(
                      _mostTopTagIcon.toString(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  const SizedBox(width: 6),
                ] else ...[
                  Icon(
                    Icons.local_offer_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey('empty1_$_dataKey'),
              duration: _shouldAnimateOverview
                  ? const Duration(milliseconds: 800)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Icon(
                      Icons.note_add_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              key: ValueKey('empty2_$_dataKey'),
              duration: _shouldAnimateOverview
                  ? const Duration(milliseconds: 600)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Text(
                      '本${_getPeriodName()}暂无笔记',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              key: ValueKey('empty3_$_dataKey'),
              duration: _shouldAnimateOverview
                  ? const Duration(milliseconds: 400)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateOverview ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Text(
                      '开始记录您的思考吧',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 获取活跃天数
  int _getActiveDays() {
    final dates = _periodQuotes.map((quote) {
      final date = DateTime.parse(quote.date);
      return DateTime(date.year, date.month, date.day);
    }).toSet();
    return dates.length;
  }

  /// 构建笔记预览 - 优化交互效果
  Widget _buildQuotePreview(Quote quote) {
    final date = DateTime.parse(quote.date);
    final formattedDate =
        '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // 添加点击反馈
            HapticFeedback.lightImpact();
            // 可以添加跳转到笔记详情的逻辑
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.content.length > 120
                      ? '${quote.content.substring(0, 120)}...'
                      : quote.content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${quote.content.length} 字',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建精选卡片
  Widget _buildFeaturedCards() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_periodQuotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey('cards_empty1_$_dataKey'),
              duration: _shouldAnimateCards
                  ? const Duration(milliseconds: 800)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateCards ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Icon(
                      Icons.note_alt_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              key: ValueKey('cards_empty2_$_dataKey'),
              duration: _shouldAnimateCards
                  ? const Duration(milliseconds: 600)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateCards ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Text(
                      '本${_getPeriodName()}暂无笔记记录',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '精选卡片',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_featuredCards.isNotEmpty)
                      Row(
                        children: [
                          Text(
                            '共 ${_featuredCards.length} 张卡片',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          if (_selectedCardIndex != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '已选中第${_selectedCardIndex! + 1}张',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              if (_isGeneratingCards)
                Container(
                  padding: const EdgeInsets.all(8),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_featuredCards.isEmpty)
                FilledButton.icon(
                  onPressed: _generateFeaturedCards,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('生成卡片'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                )
              else if (_featuredCards.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _featuredCards = [];
                    });
                    _generateFeaturedCards();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新生成'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _featuredCards.isEmpty
              ? _buildFeaturedCardsEmptyState()
              : _buildFeaturedCardsGrid(),
        ),
      ],
    );
  }

  /// 构建精选卡片空状态
  Widget _buildFeaturedCardsEmptyState() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _aiCardService?.isEnabled == true
                      ? Icons.auto_awesome_outlined
                      : Icons.settings_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _featuredCards.isEmpty ? '暂无精选卡片' : '精选卡片',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '可根据笔记内容生成精美分享卡片：开启AI=智能设计，关闭AI=使用内置模板',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 显示生成卡片按钮（无论AI开关，都会在服务内降级到模板）
              FilledButton.icon(
                onPressed:
                    _periodQuotes.isNotEmpty ? _generateFeaturedCards : null,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('生成卡片'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建精选卡片网格
  Widget _buildFeaturedCardsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _featuredCards.length,
      itemBuilder: (context, index) {
        final card = _featuredCards[index];
        final isSelected = _selectedCardIndex == index;

        return AnimatedContainer(
          duration: Duration(milliseconds: 200 + (index * 50)),
          curve: Curves.easeOutCubic,
          child: Hero(
            tag: 'card_${card.id}_$index',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showCardDetail(card),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.1),
                        blurRadius: isSelected ? 12 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: GeneratedCardWidget(
                    card: card,
                    showActions: false,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 显示卡片详情
  void _showCardDetail(GeneratedCard card) {
    // 添加触觉反馈
    HapticFeedback.lightImpact();

    // 设置选中状态
    final cardIndex = _featuredCards.indexOf(card);
    setState(() {
      _selectedCardIndex = cardIndex;
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => CardPreviewDialog(
        card: card,
        onShare: () => _shareCard(card),
        onSave: () => _saveCard(card),
      ),
    ).then((_) {
      // 对话框关闭后清除选中状态
      setState(() {
        _selectedCardIndex = null;
      });
    });
  }

  /// 分享卡片
  void _shareCard(GeneratedCard card) async {
    Navigator.of(context).pop(); // 关闭对话框

    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('正在生成分享图片...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 生成高质量图片
      final imageBytes = await card.toImageBytes(
        width: 800,
        height: 1200,
        context: context,
        scaleFactor: 2.0,
        renderMode: ExportRenderMode.contain,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName =
          '心迹_Report_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // 分享文件
      await SharePlus.instance.share(
        ShareParams(
          text:
              '来自心迹周期报告的精美卡片\n\n"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
          files: [XFile(file.path)],
        ),
      );

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('卡片分享成功'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('分享失败: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 保存卡片
  void _saveCard(GeneratedCard card) async {
    // 关键修复：在关闭对话框之前，先获取外层scaffold的context
    final scaffoldContext = context;

    Navigator.of(context).pop(); // 关闭对话框

    if (_aiCardService == null) return;

    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('正在保存卡片到相册...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 保存高质量图片，使用外层scaffold的context
      final filePath = await _aiCardService!.saveCardAsImage(
        card,
        width: 800,
        height: 1200,
        customName: '心迹_Report_Card_${DateTime.now().millisecondsSinceEpoch}',
        context: scaffoldContext,
      );

      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).hideCurrentSnackBar();
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('卡片已保存到相册: $filePath')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).hideCurrentSnackBar();
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('保存失败: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
