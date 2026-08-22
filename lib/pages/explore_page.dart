import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/weather_data.dart';
import '../models/thoughter_entry.dart';
import '../models/chat_session.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/settings_service.dart';
import '../services/smart_push_service.dart';
import '../services/chat_session_service.dart';
import '../services/insight_history_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';
import '../utils/icon_utils.dart';
import '../utils/ai_prompt_manager.dart';
import '../utils/ai_request_helper.dart';
import '../utils/report_period_utils.dart';
import '../utils/string_utils.dart';
import '../constants/app_constants.dart'; // 导入应用常量
import '../theme/app_semantic_colors.dart';
import '../theme/theme_style.dart';
import '../gen_l10n/app_localizations.dart';
import '../widgets/ai/experimental_badge.dart';
import 'thoughter_page.dart';
import 'thoughter/session_history_page.dart';

part 'explore/explore_data_loading.dart';
part 'explore/explore_time_selector.dart';
part 'explore/explore_overview.dart';
part 'explore/explore_stats.dart';
part 'explore/explore_thoughter_entry.dart';

const String _kPickDateAction = '__pick_date__';

/// 探索页：底部导航第三个 tab，聚合周期洞察与 Thoughter 入口。
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  // 时间范围选择
  String _selectedPeriod = 'week'; // week, month, year
  DateTime _selectedDate = DateTime.now();

  // 数据状态
  List<Quote> _periodQuotes = [];
  bool _isLoadingData = false;

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
  Object? _mostTopTagIcon; // 标签图标（IconData 或 emoji 字符串）

  String _insightText = '';
  bool _insightLoading = false;
  StreamSubscription<String>? _insightSub;

  // 当前洞察对应的数据签名，用于避免同一份数据反复重生成
  String? _insightSignature;

  // 最近的 Thoughter 会话。探索页入口每次都开新会话（只有笔记入口会恢复），
  // 所以这里把最近几条列出来，让对话有连续性而不是每次白纸一张。
  List<ChatSession> _recentSessions = const [];
  Map<String, ChatSessionOverview> _recentSessionOverviews = const {};
  static const int _recentSessionLimit = 2;

  // 流式洞察的节流缓冲：避免每个 chunk 都 setState 触发整页重排
  String _insightPending = '';
  Timer? _insightFlushTimer;
  static const Duration _insightFlushInterval = Duration(milliseconds: 120);

  // 新增：控制动画是否应该执行的标志
  bool _shouldAnimateOverview = true;
  String _dataKey = ''; // 用于跟踪数据版本

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  DatabaseService? _databaseService;

  // 并发/重复加载防护：数据库在启动与同步期间会连续 notifyListeners 多次，
  // 若每次都重新拉数据并把整页切回 loading，页面就会来回闪。
  int _loadToken = 0;
  bool _hasLoadedOnce = false;
  Timer? _reloadDebounce;
  static const Duration _reloadDebounceInterval = Duration(milliseconds: 300);

  void _onDatabaseChanged() {
    if (!mounted) return;
    // 合并短时间内的多次数据库通知，并且静默刷新（不把已有内容换成整页转圈）
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(_reloadDebounceInterval, () {
      if (!mounted) return;
      _loadPeriodData(showLoading: false);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPeriodData();
    _loadRecentSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _databaseService = context.read<DatabaseService>();
        _databaseService?.addListener(_onDatabaseChanged);
      }
    });
  }

  @override
  void dispose() {
    _databaseService?.removeListener(_onDatabaseChanged);
    _reloadDebounce?.cancel();
    _insightFlushTimer?.cancel();
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
  Widget build(BuildContext context) => _buildExplorePage(context);
}
