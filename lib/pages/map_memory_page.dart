import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

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
                      const SnackBar(content: Text('请在主页列表中进行编辑操作')),
                    );
                  },
                  onDelete: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请在主页列表中进行删除操作')),
                    );
                  },
                  onAskAI: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AIAssistantPage(quote: quote),
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

    final markers = _mapQuotes.map((quote) {
      return Marker(
        point: LatLng(quote.latitude!, quote.longitude!),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showQuoteBottomSheet(context, quote),
          child: const Icon(
            Icons.location_on,
            size: 40,
            color: Colors.red,
          ),
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Memory'),
      ),
      body: Stack(
        children: [
          FlutterMap(
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
                  size: const Size(40, 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  maxZoom: 15,
                  markers: markers,
                  builder: (context, clusterMarkers) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Theme.of(context).primaryColor,
                      ),
                      child: Center(
                        child: Text(
                          clusterMarkers.length.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (!hasData)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        '目前还没有带坐标的笔记',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
