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

part 'ai_report/report_data_loading.dart';
part 'ai_report/report_time_selector.dart';
part 'ai_report/report_overview.dart';
part 'ai_report/report_stats.dart';
part 'ai_report/report_featured_cards.dart';
part 'ai_report/report_card_actions.dart';

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

  /// 获取活跃天数
  int _getActiveDays() {
    final dates = _periodQuotes.map((quote) {
      final date = DateTime.parse(quote.date);
      return DateTime(date.year, date.month, date.day);
    }).toSet();
    return dates.length;
  }

  @override
  Widget build(BuildContext context) => _buildReportPage(context);
}
