import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/ai_assistant_entry.dart';
import '../services/ai_service.dart';
import '../services/database_service.dart';
import 'ai_assistant_page.dart';
import 'insights_page.dart';
import 'map_memory_page.dart';

/// 探索页面 — 数据概览 + AI/地图入口 + 收藏笔记
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  static const _favoritesLimit = 5;
  late Future<_ExploreStats> _statsFuture;
  late Future<List<Map<String, dynamic>>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    _statsFuture = _ExploreStats.load(dbService);
    _favoritesFuture = _loadFavorites(dbService);
  }

  Future<List<Map<String, dynamic>>> _loadFavorites(
    DatabaseService dbService,
  ) async {
    final quotes = await dbService.getMostFavoritedQuotesThisWeek(
      limit: _favoritesLimit,
    );
    return quotes
        .map(
          (q) => <String, dynamic>{
            'id': q.id,
            'content': q.content,
            'date': q.date,
            'favorite_count': q.favoriteCount,
          },
        )
        .toList();
  }

  Future<void> _openAIAssistant() async {
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final stats = await _statsFuture;
    final favorites = await _favoritesFuture;
    if (!mounted) return;

    final summary = await _buildAssistantGuideSummary(
      l10n: l10n,
      stats: stats,
      favorites: favorites,
    );
    if (!mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.explore,
          exploreGuideSummary: summary,
        ),
      ),
    );
  }

  Future<void> _openInsightsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InsightsPage(),
      ),
    );
  }

  Future<String?> _buildAssistantGuideSummary({
    required AppLocalizations l10n,
    required _ExploreStats stats,
    required List<Map<String, dynamic>> favorites,
  }) async {
    final localSummary = _buildLocalAssistantGuideSummary(
      l10n: l10n,
      stats: stats,
      favorites: favorites,
    );
    // 只返回 AI 生成的自然语言总结；AI 不可用时返回 null，
    // 由 _generateAndShowDynamicInsight 显示简洁统计
    return _tryBuildAiAssistantGuideSummary(localSummary);
  }

  String _buildLocalAssistantGuideSummary({
    required AppLocalizations l10n,
    required _ExploreStats stats,
    required List<Map<String, dynamic>> favorites,
  }) {
    final buffer = StringBuffer()
      ..writeln('${l10n.noteCount}: ${stats.noteCount}')
      ..writeln('${l10n.totalWordCount}: ${stats.totalWords}')
      ..writeln('${l10n.activeDays}: ${stats.activeDays}')
      ..writeln('${l10n.commonPeriod}: ${stats.topPeriod ?? l10n.noDataYet}')
      ..writeln('${l10n.commonWeather}: ${stats.topWeather ?? l10n.noDataYet}')
      ..writeln('${l10n.commonTag}: ${stats.topTag ?? l10n.noDataYet}');

    if (favorites.isNotEmpty) {
      final favoriteContent =
          (favorites.first['content'] as String? ?? '').trim();
      if (favoriteContent.isNotEmpty) {
        final preview = favoriteContent.length > 60
            ? '${favoriteContent.substring(0, 60)}...'
            : favoriteContent;
        buffer.writeln('${l10n.favoriteNotes}: $preview');
      }
    }

    return buffer.toString().trim();
  }

  Future<String?> _tryBuildAiAssistantGuideSummary(String localSummary) async {
    final aiService = context.read<AIService>();
    if (!await aiService.hasValidApiKeyAsync()) {
      return null;
    }

    final buffer = StringBuffer();
    try {
      await for (final chunk in aiService.streamGeneralConversation(
        '请基于已有概览数据生成一段简短总结，突出记录特点与建议，100字以内。',
        systemContext: localSummary,
      )) {
        buffer.write(chunk);
      }
    } catch (_) {
      return null;
    }

    final summary = buffer.toString().trim();
    return summary.isEmpty ? null : summary;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_loadData);
        },
        child: CustomScrollView(
          slivers: [
            // ── AppBar（普通高度减少顶部空白）──
            SliverAppBar(
              floating: true,
              title: Text(l10n.explore),
            ),

            // ── 内容 ──
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.list(
                children: [
                  const SizedBox(height: 8),
                  // ─── 数据概览卡片（点击进入 InsightsPage）───
                  _buildStatsSection(l10n, theme),
                  const SizedBox(height: 16),

                  // ─── 快捷入口 ───
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _EntryCard(
                        key: const ValueKey('explore_ai_chat_entry'),
                        icon: Icons.smart_toy_outlined,
                        title: l10n.aiChat,
                        subtitle: l10n.chatWithAiAssistant,
                        color: theme.colorScheme.primaryContainer,
                        iconColor: theme.colorScheme.onPrimaryContainer,
                        onTap: _openAIAssistant,
                      ),
                      const SizedBox(height: 12),
                      _EntryCard(
                        icon: Icons.map_outlined,
                        title: l10n.exploreMapMemory,
                        subtitle: l10n.exploreMapMemoryDesc,
                        color: theme.colorScheme.secondaryContainer,
                        iconColor: theme.colorScheme.onSecondaryContainer,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MapMemoryPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ─── 收藏笔记 ───
                  _buildFavoritesSection(l10n, theme),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 统计区域 ───────────────────────────────────────────────

  Widget _buildStatsSection(AppLocalizations l10n, ThemeData theme) {
    return FutureBuilder<_ExploreStats>(
      future: _statsFuture,
      builder: (context, snap) {
        final stats = snap.data ?? _ExploreStats.empty();
        final loaded = snap.connectionState == ConnectionState.done;

        return TweenAnimationBuilder<double>(
          duration: loaded ? const Duration(milliseconds: 600) : Duration.zero,
          tween: Tween(begin: loaded ? 0.0 : 1.0, end: 1.0),
          builder: (context, t, _) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)),
              child: Card(
                key: const ValueKey('explore_stats_section_card'),
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openInsightsPage,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.insights_outlined,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.dataInsights,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatsChip(
                              label: l10n.noteCount,
                              value: '${stats.noteCount}',
                            ),
                            _StatsChip(
                              label: l10n.totalWordCount,
                              value: '${stats.totalWords}',
                            ),
                            _StatsChip(
                              label: l10n.activeDays,
                              value: '${stats.activeDays}',
                            ),
                            _StatsChip(
                              label: l10n.commonPeriod,
                              value: stats.topPeriod ?? l10n.noDataYet,
                            ),
                            _StatsChip(
                              label: l10n.commonWeather,
                              value: stats.topWeather ?? l10n.noDataYet,
                            ),
                            _StatsChip(
                              label: l10n.commonTag,
                              value: stats.topTag ?? l10n.noDataYet,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── 收藏区域 ───────────────────────────────────────────────

  Widget _buildFavoritesSection(AppLocalizations l10n, ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _favoritesFuture,
      builder: (context, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.favorite_outline,
              title: l10n.favoriteNotes,
            ),
            const SizedBox(height: 12),
            ...rows.map((row) {
              final content = row['content'] as String? ?? '';
              final preview = content.length > 80
                  ? '${content.substring(0, 80)}…'
                  : content;
              final count = row['favorite_count'] as int? ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withAlpha(80),
                    ),
                  ),
                  child: ListTile(
                    title: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Text('$count', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  数据模型
// ══════════════════════════════════════════════════════════════

class _ExploreStats {
  final int noteCount;
  final int totalWords;
  final int avgWords;
  final int activeDays;
  final String? topPeriod;
  final String? topWeather;
  final String? topTag;

  const _ExploreStats({
    required this.noteCount,
    required this.totalWords,
    required this.avgWords,
    required this.activeDays,
    this.topPeriod,
    this.topWeather,
    this.topTag,
  });

  factory _ExploreStats.empty() => const _ExploreStats(
        noteCount: 0,
        totalWords: 0,
        avgWords: 0,
        activeDays: 0,
      );

  static Future<_ExploreStats> load(DatabaseService dbService) async {
    try {
      if (kIsWeb) {
        return _ExploreStats.empty();
      }
      final db = await dbService.safeDatabase;
      final countRow = await db.rawQuery(
        'SELECT COUNT(*) as c, COALESCE(SUM(LENGTH(content)),0) as s '
        'FROM quotes',
      );
      final noteCount = countRow.first['c'] as int? ?? 0;
      final totalWords = countRow.first['s'] as int? ?? 0;
      final avgWords = noteCount > 0 ? (totalWords / noteCount).round() : 0;

      final daysRow = await db.rawQuery(
        'SELECT COUNT(DISTINCT substr(date,1,10)) as d FROM quotes',
      );
      final activeDays = daysRow.first['d'] as int? ?? 0;

      final periodRow = await db.rawQuery(
        'SELECT day_period, COUNT(*) as c FROM quotes '
        'WHERE day_period IS NOT NULL '
        'GROUP BY day_period ORDER BY c DESC LIMIT 1',
      );
      final topPeriod = periodRow.isNotEmpty
          ? periodRow.first['day_period'] as String?
          : null;

      final weatherRow = await db.rawQuery(
        'SELECT weather, COUNT(*) as c FROM quotes '
        'WHERE weather IS NOT NULL '
        'GROUP BY weather ORDER BY c DESC LIMIT 1',
      );
      final topWeather =
          weatherRow.isNotEmpty ? weatherRow.first['weather'] as String? : null;

      final tagRow = await db.rawQuery(
        'SELECT c.name, COUNT(*) as cnt '
        'FROM quote_tags qt JOIN categories c ON qt.tag_id=c.id '
        'GROUP BY qt.tag_id ORDER BY cnt DESC LIMIT 1',
      );
      final topTag = tagRow.isNotEmpty ? tagRow.first['name'] as String? : null;

      return _ExploreStats(
        noteCount: noteCount,
        totalWords: totalWords,
        avgWords: avgWords,
        activeDays: activeDays,
        topPeriod: topPeriod,
        topWeather: topWeather,
        topTag: topTag,
      );
    } catch (e) {
      return _ExploreStats.empty();
    }
  }
}

// ══════════════════════════════════════════════════════════════
//  子组件
// ══════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              Icon(icon, size: 20, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _EntryCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: iconColor.withAlpha(180),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatsChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
