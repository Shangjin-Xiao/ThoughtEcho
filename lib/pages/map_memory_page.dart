import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/note_tag.dart';
import '../models/quote_map_point.dart';
import '../models/quote_model.dart';
import '../models/thoughter_entry.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../utils/app_logger.dart';
import '../widgets/app_error_view.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/map/osm_map_layers.dart';
import '../widgets/quote_item_widget.dart';
import 'note_full_editor_page.dart';
import 'thoughter_page.dart';

part 'map_memory/map_memory_sheet.dart';

/// 地图回忆：把所有带坐标的笔记摆在一张地图上。
///
/// 和 [MapLocationPickerPage] 的分工：选点页是「给这条笔记打一个地点」的工具，
/// 这里是纯浏览——不筛时间、不筛标签，永远显示全部足迹，缩小时靠聚合。
class MapMemoryPage extends StatefulWidget {
  const MapMemoryPage({super.key});

  @override
  State<MapMemoryPage> createState() => _MapMemoryPageState();
}

class _MapMemoryPageState extends State<MapMemoryPage> {
  /// 一条笔记都没有、又拿不到设备位置时的兜底中心。
  static const LatLng _fallbackCenter = LatLng(39.9042, 116.4074);
  static const double _emptyStateZoom = 11;

  /// 全局总览时最多放大到这一级。
  ///
  /// 所有笔记都在同一个街区时，不设上限会一路推到街道级，看着像"只有一条"；
  /// 停在城市级才看得出这是一片足迹。
  static const double _overviewMaxZoom = 14;

  static const EdgeInsets _overviewPadding = EdgeInsets.all(48);

  final MapController _mapController = MapController();

  List<QuoteMapPoint> _points = const [];
  Map<String, NoteTag> _tagMap = const {};
  bool _loading = true;
  bool _failed = false;

  /// 没有任何坐标笔记时，地图落在设备位置附近，而不是给一张空的世界地图。
  LatLng? _deviceCenter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final database = context.read<DatabaseService>();
    final locationService = context.read<LocationService>();
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }

    try {
      final points = await database.getQuotesWithCoordinates();
      final tags = await database.getTags();

      // 一条坐标笔记都没有时才去问设备位置——有足迹的话地图按足迹取景，
      // 多问一次没有意义。
      final deviceCenter =
          points.isEmpty ? await _resolveDeviceCenter(locationService) : null;

      if (!mounted) return;
      setState(() {
        _points = points;
        _tagMap = {for (final tag in tags) tag.id: tag};
        _deviceCenter = deviceCenter;
        _loading = false;
      });
    } catch (e, stack) {
      logError(
        '加载地图回忆数据失败',
        error: e,
        stackTrace: stack,
        source: 'MapMemoryPage',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// 空状态下地图落在哪儿。
  ///
  /// 缓存里没有位置时补取一次：[LocationService.getCurrentLocation] 只
  /// `checkPermission` 不 `requestPermission`，所以这里不会凭空弹权限框，
  /// 没授权就返回 null，落到兜底中心。
  ///
  /// 取不到位置不算这一页加载失败——地图照样能看，所以异常在这里就地咽下，
  /// 不往上抛去触发错误态。
  Future<LatLng?> _resolveDeviceCenter(LocationService locationService) async {
    try {
      final position = locationService.currentPosition ??
          await locationService.getCurrentLocation(highAccuracy: false);
      if (position == null) return null;
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      logDebug('地图空状态取设备位置失败: $e', source: 'MapMemoryPage');
      return null;
    }
  }

  /// 回到「看得见全部足迹」的取景。
  void _fitAllPoints() {
    if (_points.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _points.map(_toLatLng).toList(),
        padding: _overviewPadding,
        maxZoom: _overviewMaxZoom,
      ),
    );
  }

  static LatLng _toLatLng(QuoteMapPoint point) =>
      LatLng(point.latitude, point.longitude);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.exploreMapMemory)),
      body: _buildBody(theme, l10n),
      floatingActionButton: _points.isEmpty || _loading || _failed
          ? null
          : FloatingActionButton(
              tooltip: l10n.mapMemoryResetView,
              onPressed: _fitAllPoints,
              child: const Icon(Icons.zoom_out_map),
            ),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    if (_loading) return const AppLoadingView();
    if (_failed) return AppErrorView(text: l10n.mapMemoryLoadFailed);

    return Stack(
      children: [
        RepaintBoundary(child: _buildMap(theme)),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: _buildHintCard(theme, l10n),
        ),
      ],
    );
  }

  Widget _buildMap(ThemeData theme) {
    final hasPoints = _points.isNotEmpty;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // 有足迹就按足迹取景，进来第一眼就是"我去过这些地方"。
        initialCameraFit: hasPoints
            ? CameraFit.coordinates(
                coordinates: _points.map(_toLatLng).toList(),
                padding: _overviewPadding,
                maxZoom: _overviewMaxZoom,
              )
            : null,
        initialCenter: _deviceCenter ?? _fallbackCenter,
        initialZoom: _emptyStateZoom,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
      ),
      children: [
        OsmMapLayers.tiles(),
        if (hasPoints)
          MarkerClusterLayerWidget(
            options: MarkerClusterLayerOptions(
              markers:
                  _points.map((point) => _buildMarker(theme, point)).toList(),
              size: const Size(44, 44),
              maxClusterRadius: 48,
              padding: _overviewPadding,
              // 聚合展开的动画就是「放大相册」的那个手感，保持默认即可
              builder: (context, markers) =>
                  _buildClusterBadge(theme, markers.length),
            ),
          ),
        OsmMapLayers.attribution(),
      ],
    );
  }

  Marker _buildMarker(ThemeData theme, QuoteMapPoint point) {
    return Marker(
      key: ValueKey(point.id),
      point: _toLatLng(point),
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: () => _openNoteSheet(point.id),
        child: _MapPin(
          child: Icon(
            Icons.edit_note,
            size: 20,
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildClusterBadge(ThemeData theme, int count) {
    return _MapPin(
      child: Text(
        '$count',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }

  Widget _buildHintCard(ThemeData theme, AppLocalizations l10n) {
    final hasPoints = _points.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              hasPoints ? Icons.map_outlined : Icons.explore_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasPoints
                    ? l10n.mapMemoryPlaceCount(_points.length)
                    : l10n.mapMemoryEmptyHint,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 地图上的标记底座：一个描边的实心圆。
///
/// marker 和 cluster 用同一个底座，缩放时聚合泡展开成单点不会换一副长相。
/// 描边取 surface，让标记在深浅不一的瓦片上都能从底图里跳出来。
class _MapPin extends StatelessWidget {
  const _MapPin({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 2),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.24),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}
