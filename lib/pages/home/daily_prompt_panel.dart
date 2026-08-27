import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/theme_style.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/thoughter_entry.dart';
import '../../models/weather_data.dart' show WeatherCodeMapper;
import '../../services/ai_service.dart';
import '../../services/insight_history_service.dart';
import '../../services/location_service.dart';
import '../../services/settings_service.dart';
import '../../services/weather_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/daily_prompt_generator.dart';
import '../thoughter_page.dart';

/// 面板底部留给 FAB 的净空。
///
/// `centerDocked` 把 FAB 的**中心**对齐到导航栏上缘，也就是只向上探进 body
/// 半颗（56 / 2 = 28）；再留 8 的呼吸位。以前没有这段净空，FAB 就直接压在
/// 「今日思考」上，卡片右半边点不到。
const double _fabClearance = 36.0;

class HomeDailyPromptPanel extends StatefulWidget {
  final double screenWidth;
  final bool isSmallScreen;
  final bool isVerySmallScreen;

  const HomeDailyPromptPanel({
    super.key,
    required this.screenWidth,
    required this.isSmallScreen,
    required this.isVerySmallScreen,
  });

  @override
  State<HomeDailyPromptPanel> createState() => HomeDailyPromptPanelState();
}

class HomeDailyPromptPanelState extends State<HomeDailyPromptPanel> {
  String _accumulatedPromptText = '';
  StreamSubscription<String>? _promptSubscription;
  bool _isGeneratingDailyPrompt = false;

  Future<void> refreshPrompt({bool initialLoad = false}) async {
    if (initialLoad &&
        (_promptSubscription != null || _accumulatedPromptText.isNotEmpty)) {
      logDebug(
        'Daily prompt already loaded or loading, skipping initial fetch.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _accumulatedPromptText = '';
      _isGeneratingDailyPrompt = true;
      _promptSubscription?.cancel();
      _promptSubscription = null;
    });

    try {
      final aiService = context.read<AIService>();
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      final settingsService = context.read<SettingsService>();

      final city = locationService.city;
      // 本地模板按 key 选句子，AI 那条链路要的是人能读的天气名，两者不能混用。
      final weatherKey = weatherService.currentWeather;
      final temperature = weatherService.temperature;
      final aiEnabledForToday = settingsService.todayThoughtsUseAI;

      if (!aiEnabledForToday || !aiService.hasValidApiKey()) {
        _setLocalPrompt(
          city: city,
          weather: weatherKey,
          temperature: temperature,
        );
        return;
      }

      final insightHistoryService = context.read<InsightHistoryService>();
      final recentInsights =
          await insightHistoryService.formatRecentInsightsForDailyPrompt();
      logDebug(
        '获取到 ${recentInsights.length} 条最近的周期洞察',
        source: 'HomeDailyPromptPanel',
      );

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      final promptStream = aiService.streamGenerateDailyPrompt(
        l10n,
        city: city,
        weather: weatherKey == null
            ? null
            : WeatherCodeMapper.getLocalizedDescription(l10n, weatherKey),
        temperature: temperature,
        historicalInsights: recentInsights,
      );

      if (!mounted) return;

      _promptSubscription = promptStream.listen(
        (chunk) {
          if (!mounted) return;
          setState(() {
            _accumulatedPromptText += chunk;
          });
        },
        onError: (error) {
          logDebug('获取每日提示流出错: $error，使用本地生成的提示');
          if (!mounted) return;
          _setLocalPrompt(
            city: city,
            weather: weatherKey,
            temperature: temperature,
          );
        },
        onDone: () {
          if (!mounted) return;
          // 流正常结束但没有任何正文（例如推理模型把预算全花在思考上、
          // 或模型返回空内容）时退回本地提示，避免面板停在"等待"状态。
          if (_accumulatedPromptText.trim().isEmpty) {
            logDebug('每日提示流结束但内容为空，使用本地生成的提示');
            _setLocalPrompt(
              city: city,
              weather: weatherKey,
              temperature: temperature,
            );
            return;
          }
          setState(() {
            _accumulatedPromptText = _accumulatedPromptText.trim();
            _isGeneratingDailyPrompt = false;
          });
        },
        cancelOnError: true,
      );
    } catch (e) {
      logDebug('获取每日提示失败 (setup): $e');
      if (!mounted) return;

      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      _setLocalPrompt(
        city: locationService.city,
        weather: weatherService.currentWeather,
        temperature: weatherService.temperature,
      );
      logDebug('AI提示获取失败，已使用本地生成的提示');
    }
  }

  void _setLocalPrompt({
    String? city,
    String? weather,
    String? temperature,
  }) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final localPrompt = DailyPromptGenerator.generatePromptBasedOnContext(
      l10n,
      city: city,
      weather: weather,
      temperature: temperature,
    );

    setState(() {
      _accumulatedPromptText = localPrompt;
      _isGeneratingDailyPrompt = false;
    });
  }

  static const double _askButtonSize = 32;

  Widget _buildAskThoughterButton(ThemeData theme, AppLocalizations l10n) {
    return SizedBox(
      width: _askButtonSize,
      height: _askButtonSize,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: widget.isVerySmallScreen ? 16 : 18,
        tooltip: l10n.askNote,
        onPressed: _openThoughterWithPrompt,
        icon: Icon(
          Icons.auto_awesome,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  /// 进对话时用的开场白。
  ///
  /// 面板上那句话生成完了就用它；还在流式生成（手上只有半截话）或者压根
  /// 没生成时，用本地模板按当前时段/天气/城市现拼一句——入口任何时候都
  /// 能点，不会因为提示没加载出来就变灰。
  String _openingMessage() {
    final prompt = _accumulatedPromptText.trim();
    if (!_isGeneratingDailyPrompt && prompt.isNotEmpty) return prompt;

    final weatherService = context.read<WeatherService>();
    return DailyPromptGenerator.generatePromptBasedOnContext(
      AppLocalizations.of(context),
      city: context.read<LocationService>().city,
      weather: weatherService.currentWeather,
      temperature: weatherService.temperature,
    );
  }

  /// 带着今天的提示进入 Thoughter。
  ///
  /// 提示本身作为开场白（[ThoughterPage.openingMessage]），既是对话的
  /// 第一句，也进入模型上下文——不需要再让 AI 生成一次开场，也不替用户
  /// 先问一句，接下来说什么由用户决定。
  void _openThoughterWithPrompt() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThoughterPage(
          entrySource: ThoughterEntrySource.explore,
          openingMessage: _openingMessage(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _promptSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);
    final l10n = AppLocalizations.of(context);
    // 提问用 `bodyMedium`，不是 `bodyLarge`。
    //
    // 上一轮为了把标签压下去，两头都动了：标签降到 `labelLarge`，提问抬到
    // `bodyLarge`。**抬过头了**——衬线 17px w600 在这张卡里会撑成两行、把整张卡
    // 顶高，跟上面那张一言卡抢分量。真正起作用的是降标签那一半：标签一旦是黑体
    // `labelLarge`，提问只要还是衬线、还比它深，主次就已经正过来了，不需要再放大。
    //
    // 所有屏幕尺寸都用这一级，不再按屏分档；随屏变的只剩 `maxLines`。
    //
    // 仍然取成局部变量而不是两处各写一遍 `theme.textTheme.bodyMedium`：样式和
    // 颜色必须读同一级，写成两处就等着将来改了一处漏另一处——#529 那版正是
    // 样式取 `bodyMedium`、颜色却取 `bodyLarge`，在极小屏上错配。
    final promptStyle = theme.textTheme.bodyMedium;
    final aiService = context.watch<AIService>();
    final settingsService = context.watch<SettingsService>();
    // 以多 provider 设置为准：生成链路读的是 multiAISettings.currentProvider，
    // 而 legacy aiSettings 只在 AI 设置页保存 provider 时才被镜像写入，
    // 单纯切换当前 provider 不会同步，用它判断会误报"未配置"。
    final currentProvider = settingsService.multiAISettings.currentProvider;
    final isAiConfigured = aiService.hasValidApiKey() &&
        (currentProvider?.apiUrl.isNotEmpty ?? false) &&
        (currentProvider?.model.isNotEmpty ?? false);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        widget.screenWidth > 600 ? 16.0 : (widget.isVerySmallScreen ? 8.0 : 12),
        widget.isVerySmallScreen ? 2.0 : 4.0,
        widget.screenWidth > 600 ? 16.0 : (widget.isVerySmallScreen ? 8.0 : 12),
        // 底部让开 FAB 探进来的那半颗，见 `_fabClearance`。
        _fabClearance,
      ),
      padding: EdgeInsets.all(
        widget.screenWidth > 600
            ? 18.0
            : (widget.isVerySmallScreen ? 10.0 : 14.0),
      ),
      decoration: BoxDecoration(
        // 卡片色，不是页面底色。`colorScheme.surface` 在手工色板里就是**纸**，
        // 卡片是比它更亮的那一档（`AppSurfaceTokens.card`）；用 surface 等于让
        // 卡片和纸同色，层次全压在那道快看不见的描边上。
        color: AppSurfaceTokens.of(context).card,
        borderRadius: BorderRadius.circular(shape.cardRadius),
        boxShadow: shape.restShadow,
        // 描边跟着 borderWidth 令牌走，和一言卡同一套判据：手工风格实打实
        // 描一道发丝线，material 保持原来那道几乎看不见的浅描边。
        border: Border.all(
          color: shape.borderWidth > 0
              ? theme.colorScheme.outlineVariant
              : theme.colorScheme.outline.withValues(alpha: 0.12),
          width: shape.borderWidth > 0 ? shape.borderWidth : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 按钮浮在标题行上而不是并排：32 的点击尺寸并排会把整行（原本只有
          // 一行标题的高度）撑高近 10px，卡片跟着变高。Positioned 的子节点不
          // 参与 Stack 尺寸计算，行高回到只由标题决定，标题也仍是整行居中。
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Padding(
                // 给右侧按钮让位，避免长标题压到按钮下面
                padding: const EdgeInsets.symmetric(horizontal: _askButtonSize),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: theme.colorScheme.primary,
                      size: widget.screenWidth > 600
                          ? 22
                          : (widget.isVerySmallScreen ? 16 : 18),
                    ),
                    SizedBox(width: widget.isVerySmallScreen ? 4 : 6),
                    Flexible(
                      child: Text(
                        l10n.todayThoughts,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // 「今日思考」是这张卡的**标签**，不是它的标题——真正的
                        // 内容是下面那句提问。用 `titleMedium` 会让它吃到标题
                        // 字重下限（衬线风格下 w700），再叠上强调色和比正文还大
                        // 的字号，chrome 就压过了 content：眼睛先读到这四个字，
                        // 而不是那个问题。`labelLarge` 才是它的角色——和按钮、
                        // 胶囊、导航栏标签同一档功能性文字。
                        //
                        // 顺带去掉写死的字号：写死等于把这张卡从
                        // `ThemeStyleForm.readingFontScale` 体系里摘出去。
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                child: _buildAskThoughterButton(theme, l10n),
              ),
            ],
          ),
          SizedBox(
            height:
                widget.isVerySmallScreen ? 4 : (widget.isSmallScreen ? 6 : 8),
          ),
          if (_isGeneratingDailyPrompt && _accumulatedPromptText.isEmpty)
            _DailyPromptLoading(
              isAiConfigured: isAiConfigured,
              screenWidth: widget.screenWidth,
              isSmallScreen: widget.isSmallScreen,
              isVerySmallScreen: widget.isVerySmallScreen,
            )
          else
            Text(
              _accumulatedPromptText.isNotEmpty
                  ? _accumulatedPromptText.trim()
                  : (isAiConfigured
                      ? l10n.waitingForTodayThoughts
                      : l10n.noTodayThoughts),
              style: promptStyle?.copyWith(
                // 这张卡是紧排的两三行居中提问，不跟正文行高（纸墨 1.75）走，
                // 否则卡片会显著变高、把上面那张一言卡挤扁。
                height: 1.4,
                // 颜色要读**实际选中的那一级**：极小屏用的是 bodyMedium，
                // 却去取 bodyLarge 的颜色，一旦主题给两级配了不同颜色就会错。
                color: _accumulatedPromptText.isNotEmpty
                    ? promptStyle.color
                    : theme.colorScheme.onSurface.withAlpha(120),
              ),
              textAlign: TextAlign.center,
              maxLines: widget.isVerySmallScreen ? 2 : 3,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _DailyPromptLoading extends StatelessWidget {
  final bool isAiConfigured;
  final double screenWidth;
  final bool isSmallScreen;
  final bool isVerySmallScreen;

  const _DailyPromptLoading({
    required this.isAiConfigured,
    required this.screenWidth,
    required this.isSmallScreen,
    required this.isVerySmallScreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: isVerySmallScreen ? 16 : 18,
          height: isVerySmallScreen ? 16 : 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        SizedBox(height: isVerySmallScreen ? 3 : (isSmallScreen ? 4 : 6)),
        Text(
          isAiConfigured
              ? l10n.loadingTodayThoughts
              : l10n.fetchingDefaultPrompt,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(160),
            fontSize: screenWidth > 600 ? 13 : (isVerySmallScreen ? 10 : 12),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
