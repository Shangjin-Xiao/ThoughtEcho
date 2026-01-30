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
import '../gen_l10n/app_localizations.dart';

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
  bool _isLoadingMoreCards = false; // 加载更多卡片中
  int? _selectedCardIndex;

  // 分页加载状态
  List<Quote> _pendingQuotesForCards = []; // 待生成卡片的笔记队列
  static const int _cardsPerBatch = 6; // 每批生成卡片数

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
    super.dispose();
  }

  /// 加载周期数据
  Future<void> _loadPeriodData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      final databaseService = context.read<DatabaseService>();
      // 获取所有笔记（排除隐藏笔记，隐藏笔记不参与AI分析统计）
      final quotes = await databaseService.getAllQuotes();

      // 调试：打印获取到的所有笔记数量
      AppLogger.d('getAllQuotes returned notes count: ${quotes.length}');
      // 打印每条笔记的日期（前10条）
      for (var i = 0; i < quotes.length && i < 10; i++) {
        AppLogger.d('  Raw note[$i]: date=${quotes[i].date}');
      }

      // 根据选择的时间范围筛选笔记
      final filteredQuotes = _filterQuotesByPeriod(quotes);

      // 更新数据版本key，触发动画
      final newDataKey =
          '${_selectedPeriod}_${_selectedDate.millisecondsSinceEpoch}';
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
      AppLogger.e('Failed to load period data', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.loadDataFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  Future<void> _computeExtrasAndInsight() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    // 计算总字数
    final totalWords = _periodQuotes.fold<int>(
      0,
      (sum, q) => sum + q.content.length,
    );

    // 生成数据签名 (用于判断数据是否发生变化)
    // 签名组成: 周期类型_开始日期_结束日期_笔记数量_总字数
    final rangeText = _getDateRangeText(l10n);
    final dataSignature =
        '${_selectedPeriod}_${rangeText}_${_periodQuotes.length}_$totalWords';

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
        final category = cats.firstWhere(
          (c) => c.id == topTagId,
          orElse: () => cats.first,
        );
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

    if (!mounted) return;

    // 处理时段显示：转换为本地化标签
    String? dayPeriodDisplay;
    IconData? dayPeriodIcon;
    if (mostPeriod != null) {
      dayPeriodDisplay = TimeUtils.getLocalizedDayPeriodLabel(
        context,
        mostPeriod,
      );
      dayPeriodIcon = TimeUtils.getDayPeriodIconByKey(mostPeriod);
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
        weatherDisplay = WeatherCodeMapper.getLocalizedDescription(
          l10n,
          mostWeather,
        );
        weatherIcon = WeatherCodeMapper.getIcon(mostWeather);

        // 如果返回的是未知描述，说明mostWeather可能已经是描述
        if (weatherDisplay == l10n.weatherUnknown) {
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

      // 设置显示用的文本和图标
      _mostDayPeriodDisplay = dayPeriodDisplay;
      _mostDayPeriodIcon = dayPeriodIcon;
      _mostWeatherDisplay = weatherDisplay;
      _mostWeatherIcon = weatherIcon;
      _mostTopTagIcon = topTagIcon;
    });

    _maybeStartInsight(dataSignature);
  }

  void _maybeStartInsight(String dataSignature) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final settings = context.read<SettingsService>();
    final useAI = settings.reportInsightsUseAI;
    final periodLabel = l10n.thisPeriod(_getPeriodName(l10n));
    final activeDays = _getActiveDays();
    final noteCount = _periodQuotes.length;

    _insightSub?.cancel();

    // 1. 尝试从历史记录中查找缓存
    final insightService = context.read<InsightHistoryService>();
    final cachedInsight = insightService.getInsightBySignature(dataSignature);

    if (cachedInsight != null) {
      // 如果有缓存，直接使用缓存
      if (mounted) {
        setState(() {
          _insightText = cachedInsight.insight;
          _insightLoading = false;
        });
        AppLogger.d('Using cached insight for signature: $dataSignature');
      }
      return;
    }

    // 如果没有数据，不进行生成
    if (noteCount == 0) {
      if (mounted) {
        setState(() {
          _insightText = '';
          _insightLoading = false;
        });
      }
      return;
    }

    if (useAI) {
      setState(() {
        _insightText = '';
        _insightLoading = true;
      });
      final ai = context.read<AIService>();

      // 获取历史洞察上下文
      final previousInsights =
          insightService.getPreviousInsightsContext();

      // 准备完整的笔记内容用于AI分析
      final fullNotesContent = _periodQuotes.map((quote) {
        final date = DateTime.parse(quote.date);
        final dateStr = l10n.formattedDate(date.month, date.day);
        var content = quote.content.trim();

        // 添加位置信息
        if (quote.location != null && quote.location!.isNotEmpty) {
          content = l10n.noteMetaWithLocation(
            dateStr,
            quote.location!,
            content,
          );
        } else {
          content = l10n.noteMeta(dateStr, content);
        }

        // 添加天气信息
        if (quote.weather != null && quote.weather!.isNotEmpty) {
          final w = quote.weather!.trim();
          // 优先把英文key映射为国际化描述
          final wDesc = WeatherCodeMapper.getLocalizedDescription(
            l10n,
            w,
          );
          final display = wDesc == l10n.weatherUnknown ? w : wDesc;
          content += l10n.weatherInfo(display);
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
        previousInsights: previousInsights, // 传递历史上下文
      )
          .listen(
        (chunk) {
          if (!mounted) return;
          // 直接更新文本，UI会立即显示新内容（真正的流式显示）
          setState(() {
            _insightText += chunk;
          });
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

          // 本地兜底生成的洞察也保存，但标记为非AI（在save方法里处理）
          // 不过由于saveInsightToHistory目前强制isAiGenerated=true，
          // 这里我们可能不想保存本地兜底的，或者保存但不带signature以避免污染？
          // 暂时策略：出错降级为本地生成后，不保存到带signature的历史，以免下次误用本地版覆盖AI版
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _insightLoading = false;
          });

          // 保存洞察到历史记录
          if (_insightText.isNotEmpty) {
            _saveInsightToHistory(l10n, dataSignature: dataSignature);
          }
        },
      );
    } else {
      // ... (Local generation logic remains mostly the same, but we won't save it with signature)
      // 调试：记录本地生成洞察的参数
      AppLogger.d(
        'Start generating local insight - useAI: $useAI, periodLabel: $periodLabel, activeDays: $activeDays, noteCount: $noteCount, totalWordCount: $_totalWordCount',
      );

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

      // 本地生成的洞察通常不保存到"AI历史"中，或者保存但不用于上下文参考
      // 根据用户需求，这里我们不保存本地生成的洞察到带signature的缓存中，
      // 因为用户明确说 "只有调用ai生成的才保存"
    }
  }

  /// 根据时间范围筛选笔记
  List<Quote> _filterQuotesByPeriod(List<Quote> quotes) {
    // 归一化选中日期为当天开始时间（去除时间分量）
    final now =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
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
        endDate = DateTime(now.year, now.month + 1, 0); // 下个月第0天 = 当月最后一天
        break;
      case 'year':
        // 本年
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        break;
      default:
        return quotes;
    }

    // 调试日志
    AppLogger.d(
        'Filter conditions: period=$_selectedPeriod, selectedDate=$_selectedDate');
    AppLogger.d('Filter range: startDate=$startDate, endDate=$endDate');
    AppLogger.d('Total notes: ${quotes.length}');

    final filtered = quotes.where((quote) {
      final quoteDateTime = DateTime.parse(quote.date);
      // 归一化笔记日期为当天开始时间，只比较日期部分
      final quoteDate =
          DateTime(quoteDateTime.year, quoteDateTime.month, quoteDateTime.day);
      // 使用 >= startDate 且 <= endDate 的逻辑
      final isInRange =
          !quoteDate.isBefore(startDate) && !quoteDate.isAfter(endDate);
      return isInRange;
    }).toList();

    AppLogger.d('Filtered notes count: ${filtered.length}');
    // 打印前5条笔记的日期以便调试
    for (var i = 0; i < filtered.length && i < 5; i++) {
      AppLogger.d('  Note[$i]: ${filtered[i].date}');
    }

    return filtered;
  }

  /// 保存洞察到历史记录
  Future<void> _saveInsightToHistory(AppLocalizations l10n,
      {String? dataSignature}) async {
    try {
      final insightService = context.read<InsightHistoryService>();

      // 获取当前周期的标签
      String periodLabel = '';
      switch (_selectedPeriod) {
        case 'week':
          periodLabel = l10n.thisWeek;
          break;
        case 'month':
          periodLabel = l10n.thisMonth;
          break;
        case 'year':
          periodLabel = l10n.yearOnly(_selectedDate.year);
          break;
        default:
          periodLabel = _selectedPeriod;
      }

      await insightService.addInsight(
        insight: _insightText,
        periodType: _selectedPeriod,
        periodLabel: periodLabel,
        isAiGenerated: true,
        dataSignature: dataSignature, // 传递签名
      );

      logDebug(
        'Saved insight to history: ${_insightText.substring(0, _insightText.length > 50 ? 50 : _insightText.length)}...',
        source: 'AIPeriodicReportPage',
      );
    } catch (e) {
      logError('Failed to save insight to history: $e',
          error: e, source: 'AIPeriodicReportPage');
    }
  }

  /// 生成精选卡片（首次加载）
  Future<void> _generateFeaturedCards() async {
    if (_aiCardService == null || _periodQuotes.isEmpty || _isGeneratingCards) {
      return;
    }

    setState(() {
      _isGeneratingCards = true;
      _featuredCards = []; // 清空现有卡片
    });

    try {
      // 选择所有有代表性的笔记（不限制数量），按多样性排序
      final allSelectedQuotes = _selectRepresentativeQuotes(
        _periodQuotes,
        maxCount: _periodQuotes.length, // 选择所有符合条件的笔记
      );

      // 首批生成 _cardsPerBatch 张
      final firstBatch = allSelectedQuotes.take(_cardsPerBatch).toList();
      _pendingQuotesForCards = allSelectedQuotes.skip(_cardsPerBatch).toList();

      final cards = await _aiCardService!.generateFeaturedCards(
        notes: firstBatch,
        brandName: AppLocalizations.of(context).appTitle,
        maxCards: _cardsPerBatch,
      );

      setState(() {
        _featuredCards = cards;
        _isGeneratingCards = false;
      });
    } catch (e) {
      setState(() {
        _isGeneratingCards = false;
      });
      AppLogger.e('Failed to generate featured cards', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.generateCardFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 加载更多卡片
  Future<void> _loadMoreCards() async {
    if (_aiCardService == null ||
        _pendingQuotesForCards.isEmpty ||
        _isLoadingMoreCards ||
        _isGeneratingCards) {
      return;
    }

    setState(() {
      _isLoadingMoreCards = true;
    });

    try {
      // 取下一批笔记
      final nextBatch = _pendingQuotesForCards.take(_cardsPerBatch).toList();
      _pendingQuotesForCards =
          _pendingQuotesForCards.skip(_cardsPerBatch).toList();

      final newCards = await _aiCardService!.generateFeaturedCards(
        notes: nextBatch,
        brandName: AppLocalizations.of(context).appTitle,
        maxCards: _cardsPerBatch,
      );

      setState(() {
        _featuredCards.addAll(newCards);
        _isLoadingMoreCards = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMoreCards = false;
      });
      AppLogger.e('Failed to load more cards', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.generateCardFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 是否还有更多卡片可加载
  bool get _hasMoreCards => _pendingQuotesForCards.isNotEmpty;

  /// 选择有代表性的笔记
  /// [maxCount] 根据周期类型动态调整（周=6，月=12，年=18）
  List<Quote> _selectRepresentativeQuotes(List<Quote> quotes,
      {int maxCount = 6}) {
    // 按内容长度和多样性选择
    final sortedQuotes = List<Quote>.from(quotes);

    // 优先选择内容丰富的笔记
    sortedQuotes.sort((a, b) => b.content.length.compareTo(a.content.length));

    // 选择指定数量的笔记，确保多样性
    final selected = <Quote>[];
    final usedKeywords = <String>{};

    for (final quote in sortedQuotes) {
      if (selected.length >= maxCount) break;

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

  String _getPeriodName(AppLocalizations l10n) {
    switch (_selectedPeriod) {
      case 'week':
        return l10n.periodWeek;
      case 'month':
        return l10n.periodMonth;
      case 'year':
        return l10n.periodYear;
      default:
        return l10n.periodDuring;
    }
  }

  String _getDateRangeText(AppLocalizations l10n) {
    final now = _selectedDate;
    switch (_selectedPeriod) {
      case 'week':
        final weekday = now.weekday;
        final startDate = now.subtract(Duration(days: weekday - 1));
        final endDate = startDate.add(const Duration(days: 6));
        return l10n.dateRange(
          l10n.formattedDate(startDate.month, startDate.day),
          l10n.formattedDate(endDate.month, endDate.day),
        );
      case 'month':
        return l10n.yearMonth(now.year, now.month);
      case 'year':
        return l10n.yearOnly(now.year);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              _buildTabItem(0, l10n.dataOverview, Icons.analytics_outlined),
              _buildTabItem(1, l10n.featuredCards, Icons.auto_awesome_outlined),
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
              children: [_buildDataOverview(), _buildFeaturedCards()],
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
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3),
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
    final l10n = AppLocalizations.of(context);
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
            '${_getPeriodName(l10n)} - ${_getDateRangeText(l10n)}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
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
    final l10n = AppLocalizations.of(context);
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
                l10n.timeRange,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
                  tooltip: l10n.selectDate,
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
            segments: [
              ButtonSegment(
                value: 'week',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.view_week, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        l10n.thisWeek,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'month',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_view_month, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        l10n.thisMonth,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ButtonSegment(
                value: 'year',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.today, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        l10n.thisYear,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                _pendingQuotesForCards = [];
                _selectedCardIndex = null;
              });
              _loadPeriodData();
            },
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        _pendingQuotesForCards = [];
        _selectedCardIndex = null;
      });
      _loadPeriodData();
    }
  }

  /// 构建数据概览
  Widget _buildDataOverview() {
    final l10n = AppLocalizations.of(context);
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
                      l10n.dataOverview,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _getDateRangeText(l10n),
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
                        child: _buildStatCard(
                          l10n.noteCount,
                          '$totalNotes',
                          l10n.notesUnitPlain,
                          Icons.note_alt_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          l10n.totalWordCount,
                          '$totalWords',
                          l10n.wordsUnitPlain,
                          Icons.text_fields,
                        ),
                      ),
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
                        child: _buildStatCard(
                          l10n.avgWords,
                          '$avgWords',
                          l10n.wordsPerNote,
                          Icons.calculate_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          l10n.activeDays,
                          '${_getActiveDays()}',
                          l10n.daysUnitPlain,
                          Icons.calendar_today_outlined,
                        ),
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
                          l10n.commonPeriod,
                          _mostDayPeriodDisplay ?? l10n.noDataYet,
                          '',
                          _mostDayPeriodIcon ?? Icons.timelapse,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCardWithCustomIcon(
                          l10n.commonWeather,
                          _mostWeatherDisplay ?? l10n.noDataYet,
                          '',
                          _mostWeatherIcon ?? Icons.cloud_queue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCardWithTagIcon(
                          l10n.commonTag,
                          _mostTopTag ?? l10n.noDataYet,
                          '',
                        ),
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
                              l10n.recentNotes,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._periodQuotes.take(3).map(
                              (quote) => TweenAnimationBuilder<double>(
                                duration: Duration(
                                  milliseconds: 600 +
                                      (_periodQuotes.indexOf(quote) * 200),
                                ),
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
    final l10n = AppLocalizations.of(context);
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
                      l10n.noFavoritesInPeriod,
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
                    Icon(Icons.favorite, size: 20, color: Colors.red.shade400),
                    const SizedBox(width: 8),
                    Text(
                      l10n.mostFavoritedInPeriod,
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
                tween: Tween(
                  begin: _shouldAnimateOverview ? 0.0 : 1.0,
                  end: 1.0,
                ),
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
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                            const Icon(
                              Icons.favorite,
                              color: Colors.white,
                              size: 12,
                            ),
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

  // 洞察小灯泡组件 - 真正的流式显示（AI生成一个字就立即显示）
  Widget _buildInsightBulbBar() {
    final l10n = AppLocalizations.of(context);
    // 判断是否正在等待首个响应（加载中但还没有文本）
    final isWaitingFirstResponse = _insightLoading && _insightText.isEmpty;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 灯泡图标：流式接收中闪烁，完成后稳定
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 等待首个响应时显示加载提示
                  if (isWaitingFirstResponse) ...[
                    Text(
                      l10n.generatingInsightsForPeriod(_getPeriodName(l10n)),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ]
                  // 有文本时直接显示（流式接收中或已完成）
                  else if (_insightText.isNotEmpty)
                    // 直接显示实时文本，不使用打字机动画，流式接收时也不显示加载指示器
                    Text(
                      _insightText,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.5),
                    )
                  // 没有洞察内容且加载完成时显示空状态
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.noInsights,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                          ),
                        ],
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

  /// 构建统计卡片
  Widget _buildStatCard(
    String title,
    String value,
    String unit, [
    IconData? icon,
  ]) {
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
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                      maxLines: 1,
                    ),
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建带自定义图标的统计卡片
  Widget _buildStatCardWithCustomIcon(
    String title,
    String value,
    String unit,
    IconData icon,
  ) {
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
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                      maxLines: 1,
                    ),
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
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
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                      maxLines: 1,
                    ),
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
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
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                      l10n.noNotesInPeriodForPeriod(_getPeriodName(l10n)),
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
                      l10n.startRecordingThoughts,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(
                              context,
                            )
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
    final l10n = AppLocalizations.of(context);
    final date = DateTime.parse(quote.date);
    final formattedDate =
        '${l10n.formattedDate(date.month, date.day)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

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
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
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
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${quote.content.length} 字',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
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
    final l10n = AppLocalizations.of(context);
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
                      l10n.noNotesInPeriodForPeriod(_getPeriodName(l10n)),
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
                      l10n.featuredCards,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_featuredCards.isNotEmpty)
                      Row(
                        children: [
                          Text(
                            l10n.totalCards(_featuredCards.length),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (_selectedCardIndex != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                l10n.cardSelected(_selectedCardIndex! + 1),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
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
                  label: Text(l10n.generateCards),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                )
              else if (_featuredCards.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _featuredCards = [];
                      _pendingQuotesForCards = [];
                    });
                    _generateFeaturedCards();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.regenerate),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
    final l10n = AppLocalizations.of(context);
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
                _featuredCards.isEmpty
                    ? l10n.noFeaturedCards
                    : l10n.featuredCards,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.featuredCardGenerationTip,
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
                label: Text(l10n.generateCards),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // 计算总项数：卡片数 + 可能的"加载更多"按钮
    final hasLoadMore = _hasMoreCards && !_isLoadingMoreCards;
    final isLoadingMore = _isLoadingMoreCards;
    final extraItemCount = (hasLoadMore || isLoadingMore) ? 1 : 0;
    final totalItemCount = _featuredCards.length + extraItemCount;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: totalItemCount,
      itemBuilder: (context, index) {
        // 最后一项显示"加载更多"或加载指示器
        if (index >= _featuredCards.length) {
          if (_isLoadingMoreCards) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.generatingCards,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // "加载更多"按钮
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _loadMoreCards,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.loadMoreCards,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.remainingCards(_pendingQuotesForCards.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

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
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.1),
                        blurRadius: isSelected ? 12 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: GeneratedCardWidget(card: card, showActions: false),
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

    Quote? quoteForCard;
    for (final quote in _periodQuotes) {
      if (quote.id == card.noteId) {
        quoteForCard = quote;
        break;
      }
    }

    Future<GeneratedCard> Function()? regenerateCallback;
    if (_aiCardService != null && quoteForCard != null) {
      regenerateCallback = () async {
        final newCard = await _aiCardService!.generateCard(
          note: quoteForCard!,
          isRegeneration: true,
          brandName: AppLocalizations.of(context).appTitle,
        );
        if (mounted) {
          setState(() {
            final index =
                _featuredCards.indexWhere((existing) => existing.id == card.id);
            if (index != -1) {
              _featuredCards[index] = newCard;
            }
          });
        }
        return newCard;
      };
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => CardPreviewDialog(
        card: card,
        onShare: (selected) => _shareCard(selected),
        onSave: (selected) => _saveCard(selected),
        onRegenerate: regenerateCallback,
      ),
    ).then((_) {
      // 对话框关闭后清除选中状态
      setState(() {
        _selectedCardIndex = null;
      });
    });
  }

  /// 分享卡片
  Future<void> _shareCard(GeneratedCard card) async {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop(); // 关闭对话框

    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(l10n.generatingShareImage),
              ],
            ),
            duration: const Duration(seconds: 3),
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
          'ThoughtEcho_Report_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // 分享文件
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${l10n.cardFromReport}\n\n"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
          files: [XFile(file.path)],
        ),
      );

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(l10n.cardSharedSuccessfully),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
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
                Expanded(child: Text(l10n.shareFailed(e.toString()))),
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
  Future<void> _saveCard(GeneratedCard card) async {
    final l10n = AppLocalizations.of(context);
    // 关键修复：在关闭对话框之前，先获取外层scaffold的context
    final scaffoldContext = context;

    Navigator.of(context).pop(); // 关闭对话框

    if (_aiCardService == null) return;

    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(l10n.savingCardToGallery),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 保存高质量图片，使用外层scaffold的context
      final filePath = await _aiCardService!.saveCardAsImage(
        card,
        width: 800,
        height: 1200,
        customName:
            'ThoughtEcho_Report_Card_${DateTime.now().millisecondsSinceEpoch}',
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
                Expanded(child: Text(l10n.cardSavedToGallery(filePath))),
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
                Expanded(child: Text(l10n.saveFailed(e.toString()))),
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
