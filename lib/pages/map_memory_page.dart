import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/ai_assistant_entry.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../widgets/quote_item_widget.dart';
import 'ai_assistant_page.dart';

class MapMemoryPage extends StatefulWidget {
  const MapMemoryPage({super.key});

  @override
  State<MapMemoryPage> createState() => _MapMemoryPageState();
}

class _MapMemoryPageState extends State<MapMemoryPage> {
  bool _isLoading = true;
  List<Quote> _mapQuotes = [];
  final MapController _mapController = MapController();
  late AppLocalizations l10n;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    l10n = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = context.read<DatabaseService>();
    final allQuotes = await db.getAllQuotes();
    if (mounted) {
      setState(() {
        _mapQuotes = allQuotes
            .where((q) => q.latitude != null && q.longitude != null)
            .toList();
        _isLoading = false;
      });
    }
  }

  void _showQuoteBottomSheet(BuildContext context, Quote quote) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: QuoteItemWidget(
                  quote: quote,
                  tagMap: const {},
                  isExpanded: false,
                  onToggleExpanded: (bool expanded) {},
                  onEdit: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.editNoteMenu)),
                    );
                  },
                  onDelete: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.deleteNoteMenu)),
                    );
                  },
                  onAskAI: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AIAssistantPage(
                          entrySource: AIAssistantEntrySource.note,
                          quote: quote,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasData = _mapQuotes.isNotEmpty;
    final initialCenter = hasData
        ? LatLng(_mapQuotes.first.latitude!, _mapQuotes.first.longitude!)
        : const LatLng(39.9042, 116.4074); // Default to Beijing
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkTheme = theme.brightness == Brightness.dark;
    final markerBorderColor = isDarkTheme
        ? colorScheme.onSurface.withValues(alpha: 0.66)
        : colorScheme.surface;
    final markerShadowColor = isDarkTheme
        ? Colors.black.withValues(alpha: 0.34)
        : colorScheme.shadow.withValues(alpha: 0.24);
    final markerGradient = LinearGradient(
      colors: isDarkTheme
          ? [
              colorScheme.primaryContainer.withValues(alpha: 0.96),
              colorScheme.primary.withValues(alpha: 0.96),
            ]
          : [
              colorScheme.primary,
              colorScheme.primary.withValues(alpha: 0.82),
            ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final markerContentColor =
        isDarkTheme ? colorScheme.onPrimaryContainer : colorScheme.onPrimary;
    final isCompactInfoCard = MediaQuery.sizeOf(context).width < 370;
    final infoCardHorizontalPadding = isCompactInfoCard ? 12.0 : 14.0;
    final infoCardVerticalPadding = isCompactInfoCard ? 10.0 : 12.0;
    final infoCardIconPadding = isCompactInfoCard ? 7.0 : 8.0;
    final infoCardIconSize = isCompactInfoCard ? 18.0 : 20.0;

    final markers = _mapQuotes.map((quote) {
      return Marker(
        point: LatLng(quote.latitude!, quote.longitude!),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _showQuoteBottomSheet(context, quote),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: markerGradient,
              border: Border.all(
                color: markerBorderColor,
                width: isDarkTheme ? 2.8 : 2.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: markerShadowColor,
                  blurRadius: isDarkTheme ? 11 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.location_on_rounded,
              size: isDarkTheme ? 21 : 22,
              color: markerContentColor,
            ),
          ),
        ),
      );
    }).toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colorScheme.surface.withValues(alpha: 0.96),
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l10n.exploreMapMemory,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 5.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.thoughtecho.app',
              ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 45,
                  size: const Size(46, 46),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  maxZoom: 15,
                  markers: markers,
                  builder: (context, clusterMarkers) {
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: markerGradient,
                        border: Border.all(
                          color: markerBorderColor,
                          width: isDarkTheme ? 2.8 : 2.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: markerShadowColor,
                            blurRadius: isDarkTheme ? 11 : 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          clusterMarkers.length.toString(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: markerContentColor,
                            fontWeight: FontWeight.w800,
                            fontSize: isDarkTheme ? 13 : 12.5,
                            height: 1,
                            shadows: isDarkTheme
                                ? [
                                    Shadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: isDarkTheme
                    ? colorScheme.surface.withValues(alpha: 0.9)
                    : colorScheme.surface.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDarkTheme
                      ? colorScheme.outline.withValues(alpha: 0.36)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDarkTheme
                        ? Colors.black.withValues(alpha: 0.2)
                        : colorScheme.shadow.withValues(alpha: 0.12),
                    blurRadius: isDarkTheme ? 10 : 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: infoCardHorizontalPadding,
                  vertical: infoCardVerticalPadding,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(infoCardIconPadding),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: isDarkTheme ? 0.68 : 0.8,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.map_outlined,
                        size: infoCardIconSize,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    SizedBox(width: isCompactInfoCard ? 10 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.exploreMapMemory,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: isCompactInfoCard ? 14 : null,
                            ),
                          ),
                          SizedBox(height: isCompactInfoCard ? 2 : 3),
                          Text(
                            hasData
                                ? '${l10n.exploreMapMemoryDesc} · ${_mapQuotes.length}'
                                : l10n.noNotesFound,
                            maxLines: isCompactInfoCard ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: (isCompactInfoCard
                                    ? theme.textTheme.bodySmall
                                    : theme.textTheme.bodyMedium)
                                ?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: isDarkTheme ? 0.95 : 0.9,
                              ),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: hasData
          ? FloatingActionButton(
              onPressed: () {
                _mapController.move(initialCenter, 5.0);
              },
              elevation: 2,
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: const Icon(Icons.my_location_rounded),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
