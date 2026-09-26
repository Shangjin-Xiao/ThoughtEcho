import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/agent_memory.dart';
import '../../services/agent_memory_service.dart';
import '../../theme/theme_style.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_snackbar.dart';
import 'agent_memory_card.dart';
import 'agent_memory_dialogs.dart';
import 'agent_memory_overview_card.dart';

/// 记忆展示过滤器。
enum _MemoryFilter {
  all,
  profile,
  pulse,
  facts,
  history,
}

/// Thoughter 长期记忆管理页面。
///
/// 满足 2026-08-28 记忆二期硬性上线前置（第七节）：
/// 1. 可视化查阅、编辑与删除全部画像条目与近况切片与事实；
/// 2. 归因证据展示（每条由 Dreaming 归纳的条目均可下钻追溯来源笔记）；
/// 3. 认知负荷与注入硬预算计量。
class AgentMemoryPage extends StatefulWidget {
  const AgentMemoryPage({super.key});

  @override
  State<AgentMemoryPage> createState() => _AgentMemoryPageState();
}

class _AgentMemoryPageState extends State<AgentMemoryPage> {
  _MemoryFilter _currentFilter = _MemoryFilter.all;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  Future<_MemoryBundle>? _bundleFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshBundle();
  }

  void _refreshBundle() {
    final memoryService = context.read<AgentMemoryService>();
    _bundleFuture = _loadBundle(memoryService, _searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final colorScheme = theme.colorScheme;
    final memoryService = context.watch<AgentMemoryService>();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: l10n.agentMemorySearchHint,
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim().toLowerCase();
                    _refreshBundle();
                  });
                },
              )
            : Text(l10n.agentMemoryPageTitle),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                  _refreshBundle();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(shapeTokens.dialogRadius),
            ),
            onSelected: (value) async {
              if (value == 'compact') {
                await _handleCompact(context, memoryService);
              } else if (value == 'clear_all') {
                await _handleClearAll(context, memoryService);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'compact',
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_fix_high_outlined,
                      size: 20,
                      color: colorScheme.onSurface,
                    ),
                    const SizedBox(width: 12),
                    Text(l10n.agentMemoryCompactTitle),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_sweep_outlined,
                      size: 20,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.agentMemoryClearTitle,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<_MemoryBundle>(
        future: _bundleFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final bundle = snapshot.data ??
              const _MemoryBundle(
                profiles: [],
                slices: [],
                facts: [],
              );

          final activeProfiles =
              bundle.profiles.where((p) => p.isActive).toList();
          final supersededProfiles =
              bundle.profiles.where((p) => !p.isActive).toList();

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshBundle()),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: AgentMemoryOverviewCard(
                      activeProfiles: activeProfiles,
                      activeSlices: bundle.slices,
                      factCount: bundle.facts.length,
                      onCompactTap: () =>
                          _handleCompact(context, memoryService),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _buildFilterChip(
                          filter: _MemoryFilter.all,
                          label: l10n.agentMemoryTabAll,
                          count: activeProfiles.length +
                              bundle.slices.length +
                              bundle.facts.length,
                          shapeTokens: shapeTokens,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          filter: _MemoryFilter.profile,
                          label: l10n.agentMemoryTabProfile,
                          count: activeProfiles.length,
                          shapeTokens: shapeTokens,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          filter: _MemoryFilter.pulse,
                          label: l10n.agentMemoryTabPulse,
                          count: bundle.slices.length,
                          shapeTokens: shapeTokens,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          filter: _MemoryFilter.facts,
                          label: l10n.agentMemoryTabFacts,
                          count: bundle.facts.length,
                          shapeTokens: shapeTokens,
                          colorScheme: colorScheme,
                        ),
                        if (supersededProfiles.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            filter: _MemoryFilter.history,
                            label: l10n.agentMemoryTabHistory,
                            count: supersededProfiles.length,
                            shapeTokens: shapeTokens,
                            colorScheme: colorScheme,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _buildListSliver(
                  context: context,
                  bundle: bundle,
                  activeProfiles: activeProfiles,
                  supersededProfiles: supersededProfiles,
                  memoryService: memoryService,
                  l10n: l10n,
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await showAddMemoryDialog(context);
          if (added && mounted) {
            setState(_refreshBundle);
          }
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeTokens.fabRadius),
        ),
        icon: const Icon(Icons.add),
        label: Text(l10n.agentMemoryAddTitle),
      ),
    );
  }

  Widget _buildFilterChip({
    required _MemoryFilter filter,
    required String label,
    required int count,
    required AppShapeTokens shapeTokens,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _currentFilter == filter;
    return ChoiceChip(
      selected: isSelected,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
      ),
      label: Text('$label ($count)'),
      onSelected: (_) {
        setState(() => _currentFilter = filter);
      },
    );
  }

  Widget _buildListSliver({
    required BuildContext context,
    required _MemoryBundle bundle,
    required List<AgentMemoryProfileEntry> activeProfiles,
    required List<AgentMemoryProfileEntry> supersededProfiles,
    required AgentMemoryService memoryService,
    required AppLocalizations l10n,
  }) {
    final items = <Widget>[];

    switch (_currentFilter) {
      case _MemoryFilter.all:
        for (final profile in activeProfiles) {
          items.add(_buildProfileItem(context, profile, memoryService));
        }
        for (final slice in bundle.slices) {
          items.add(_buildSliceItem(context, slice, memoryService));
        }
        for (final fact in bundle.facts) {
          items.add(_buildFactItem(context, fact, memoryService));
        }
      case _MemoryFilter.profile:
        for (final profile in activeProfiles) {
          items.add(_buildProfileItem(context, profile, memoryService));
        }
      case _MemoryFilter.pulse:
        for (final slice in bundle.slices) {
          items.add(_buildSliceItem(context, slice, memoryService));
        }
      case _MemoryFilter.facts:
        for (final fact in bundle.facts) {
          items.add(_buildFactItem(context, fact, memoryService));
        }
      case _MemoryFilter.history:
        for (final profile in supersededProfiles) {
          items.add(_buildProfileItem(context, profile, memoryService));
        }
    }

    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppEmptyView(
          text: l10n.agentMemoryEmpty,
          message: l10n.agentMemoryEmptyDesc,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index.isOdd) {
              return const SizedBox(height: 8);
            }
            final itemIndex = index ~/ 2;
            return items[itemIndex];
          },
          childCount: items.length * 2 - 1,
        ),
      ),
    );
  }

  Widget _buildProfileItem(
    BuildContext context,
    AgentMemoryProfileEntry entry,
    AgentMemoryService memoryService,
  ) {
    return ProfileEntryCard(
      entry: entry,
      onEdit: () async {
        final edited = await showEditDirectiveDialog(context, entry: entry);
        if (edited && mounted) {
          setState(_refreshBundle);
        }
      },
      onForget: () async {
        final confirmed = await showForgetMemoryConfirmDialog(
          context,
          previewText: entry.directive,
        );
        if (!confirmed) return;
        final success = await memoryService.forgetProfile(entry.id);
        if (context.mounted && success) {
          AppSnackBar.success(
            context,
            AppLocalizations.of(context).agentMemoryForgotten,
          );
          setState(_refreshBundle);
        }
      },
    );
  }

  Widget _buildSliceItem(
    BuildContext context,
    AgentMemoryRecentSlice slice,
    AgentMemoryService memoryService,
  ) {
    return RecentSliceCard(
      slice: slice,
      onForget: () async {
        final confirmed = await showForgetMemoryConfirmDialog(
          context,
          previewText: slice.content,
        );
        if (!confirmed) return;
        final success = await memoryService.clearRecentSlice(id: slice.id);
        if (context.mounted && success) {
          AppSnackBar.success(
            context,
            AppLocalizations.of(context).agentMemoryForgotten,
          );
          setState(_refreshBundle);
        }
      },
    );
  }

  Widget _buildFactItem(
    BuildContext context,
    AgentMemoryFact fact,
    AgentMemoryService memoryService,
  ) {
    return FactCard(
      fact: fact,
      onForget: () async {
        final confirmed = await showForgetMemoryConfirmDialog(
          context,
          previewText: fact.content,
        );
        if (!confirmed) return;
        final success = await memoryService.forgetFact(fact.id);
        if (context.mounted && success) {
          AppSnackBar.success(
            context,
            AppLocalizations.of(context).agentMemoryForgotten,
          );
          setState(_refreshBundle);
        }
      },
    );
  }

  Future<_MemoryBundle> _loadBundle(
    AgentMemoryService memoryService,
    String query,
  ) async {
    final allProfiles = await memoryService.allProfileEntries();
    final allSlices = await memoryService.activeRecentSlices();
    final allFacts = await memoryService.allFacts(query: query);

    if (query.isEmpty) {
      return _MemoryBundle(
        profiles: allProfiles,
        slices: allSlices,
        facts: allFacts,
      );
    }

    final filteredProfiles = allProfiles.where((p) {
      return p.directive.toLowerCase().contains(query);
    }).toList(growable: false);

    final filteredSlices = allSlices.where((s) {
      return s.content.toLowerCase().contains(query);
    }).toList(growable: false);

    return _MemoryBundle(
      profiles: filteredProfiles,
      slices: filteredSlices,
      facts: allFacts,
    );
  }

  Future<void> _handleCompact(
    BuildContext context,
    AgentMemoryService memoryService,
  ) async {
    final confirmed = await showCompactConfirmDialog(context);
    if (!confirmed) return;

    final stats = await memoryService.compactAndPrune();
    if (!context.mounted) return;

    setState(_refreshBundle);

    final l10n = AppLocalizations.of(context);
    if (stats.totalPruned > 0) {
      AppSnackBar.success(
        context,
        l10n.agentMemoryCompactDone(stats.totalPruned),
      );
    } else {
      AppSnackBar.info(context, l10n.agentMemoryCompactNoop);
    }
  }

  Future<void> _handleClearAll(
    BuildContext context,
    AgentMemoryService memoryService,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final shapeTokens = AppShapeTokens.of(dialogContext);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(shapeTokens.dialogRadius),
          ),
          title: Text(l10n.agentMemoryClearConfirmTitle),
          content: Text(l10n.agentMemoryClearConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.agentMemoryClearConfirmAction),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await memoryService.clearAll();
    if (!context.mounted) return;
    setState(_refreshBundle);
    AppSnackBar.success(context, l10n.agentMemoryCleared);
  }
}

class _MemoryBundle {
  const _MemoryBundle({
    required this.profiles,
    required this.slices,
    required this.facts,
  });

  final List<AgentMemoryProfileEntry> profiles;
  final List<AgentMemoryRecentSlice> slices;
  final List<AgentMemoryFact> facts;
}
