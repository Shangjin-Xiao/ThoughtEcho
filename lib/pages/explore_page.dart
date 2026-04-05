import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/ai_assistant_entry.dart';
import '../services/database_service.dart';
import 'ai_assistant_page.dart';
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
    final l10n = AppLocalizations.of(context);
    final stats = await _statsFuture;
    final favorites = await _favoritesFuture;
    if (!mounted) return;

    final summary = _buildAssistantGuideSummary(
      l10n: l10n,
      stats: stats,
      favorites: favorites,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.explore,
          exploreGuideSummary: summary,
        ),
      ),
    );
  }

  String _buildAssistantGuideSummary({
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
            // ── AppBar ──
            SliverAppBar.medium(
              title: Text(l10n.explore),
            ),

            // ── 内容 ──
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.list(
                children: [
                  // ─── 数据概览 ───
                  _SectionHeader(
                    icon: Icons.analytics_outlined,
                    title: l10n.dataOverview,
                  ),
                  const SizedBox(height: 12),
                  _buildStatsSection(l10n, theme),
                  const SizedBox(height: 24),

                  // ─── 快捷入口 ───
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _EntryCard(
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
              child: Column(
                children: [
                  // 第一行：笔记数 + 总字数
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: l10n.noteCount,
                          value: '${stats.noteCount}',
                          unit: l10n.notesUnitPlain,
                          icon: Icons.note_alt_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: l10n.totalWordCount,
                          value: '${stats.totalWords}',
                          unit: l10n.wordsUnitPlain,
                          icon: Icons.text_fields,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 第二行：平均字数 + 活跃天数
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: l10n.avgWords,
                          value: '${stats.avgWords}',
                          unit: l10n.wordsPerNote,
                          icon: Icons.calculate_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: l10n.activeDays,
                          value: '${stats.activeDays}',
                          unit: l10n.daysUnitPlain,
                          icon: Icons.calendar_today_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 第三行：常用时段 + 天气 + 标签
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: l10n.commonPeriod,
                          value: stats.topPeriod ?? l10n.noDataYet,
                          icon: Icons.timelapse,
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          label: l10n.commonWeather,
                          value: stats.topWeather ?? l10n.noDataYet,
                          icon: Icons.cloud_queue,
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          label: l10n.commonTag,
                          value: stats.topTag ?? l10n.noDataYet,
                          icon: Icons.label_outline,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ],
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final bool compact;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.unit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: compact ? 18 : 20, color: theme.colorScheme.primary),
            SizedBox(height: compact ? 6 : 8),
            Text(
              value,
              style: compact
                  ? theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (unit != null && unit!.isNotEmpty)
              Text(unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            const SizedBox(height: 4),
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
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
