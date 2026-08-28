part of '../explore_page.dart';

/// 探索页通往地图回忆的入口。
///
/// 和上面的 Thoughter 入口并列，是这一页的第二个「去处」：一个按时间读笔记，
/// 一个按地点读笔记。地图页自己负责取数，这里只管跳转。
extension _ExploreMapEntry on _ExplorePageState {
  Widget _buildMapMemoryEntry() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius:
          BorderRadius.circular(AppShapeTokens.of(context).buttonRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openMapMemory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.map_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.exploreMapMemory,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.exploreMapMemoryDesc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMapMemory() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MapMemoryPage()),
    );
    // 地图页里能编辑和删除笔记，回来这一页的统计就不一定还准
    if (!mounted) return;
    await _loadPeriodData(showLoading: false);
  }
}
