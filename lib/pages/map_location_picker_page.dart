import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../services/local_geocoding_service.dart';
import '../services/location_service.dart';

class MapPickerResult {
  const MapPickerResult({
    required this.latitude,
    required this.longitude,
    this.location,
    this.poiName,
  });

  final double latitude;
  final double longitude;
  final String? location;
  final String? poiName;
}

class MapLocationPickerPage extends StatefulWidget {
  const MapLocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<MapLocationPickerPage> createState() => _MapLocationPickerPageState();
}

class _MapLocationPickerPageState extends State<MapLocationPickerPage> {
  static const LatLng _defaultCenter = LatLng(39.9042, 116.4074);

  final MapController _mapController = MapController();
  LatLng? _selectedPoint;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint =
          LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentLocationIfNeeded();
    });
  }

  Future<void> _loadCurrentLocationIfNeeded() async {
    if (!mounted || _selectedPoint != null) return;

    final locationService =
        Provider.of<LocationService>(context, listen: false);
    final cached = locationService.currentPosition;
    if (cached != null) {
      final point = LatLng(cached.latitude, cached.longitude);
      setState(() {
        _selectedPoint = point;
      });
      _mapController.move(point, 14);
      return;
    }

    final current =
        await locationService.getCurrentLocation(highAccuracy: false);
    if (!mounted || current == null) return;
    final point = LatLng(current.latitude, current.longitude);
    setState(() {
      _selectedPoint = point;
    });
    _mapController.move(point, 14);
  }

  String? _buildPoiName(Map<String, String?> info) {
    final street = info['street']?.trim();
    final district = info['district']?.trim();
    final city = info['city']?.trim();
    final candidates = [street, district, city];
    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _confirmSelection() async {
    if (_selectedPoint == null || _isConfirming) return;
    setState(() {
      _isConfirming = true;
    });

    String? location;
    String? poiName;
    try {
      final locationService =
          Provider.of<LocationService>(context, listen: false);
      final addressInfo = await LocalGeocodingService.getAddressFromCoordinates(
        _selectedPoint!.latitude,
        _selectedPoint!.longitude,
        localeCode: locationService.currentLocaleCode,
      );
      if (addressInfo != null) {
        final formattedAddress = addressInfo['formatted_address']?.trim();
        if (formattedAddress != null && formattedAddress.isNotEmpty) {
          location = formattedAddress;
        }
        poiName = _buildPoiName(addressInfo);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConfirming = false;
        });
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      MapPickerResult(
        latitude: _selectedPoint!.latitude,
        longitude: _selectedPoint!.longitude,
        location: location,
        poiName: poiName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final center = _selectedPoint ?? _defaultCenter;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapPickerTitle),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              onTap: (_, point) {
                setState(() {
                  _selectedPoint = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.thoughtecho.app',
              ),
              if (_selectedPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPoint!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_on,
                        size: 40,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedPoint == null
                            ? l10n.mapPickerCurrentLocation
                            : LocationService.formatCoordinates(
                                _selectedPoint!.latitude,
                                _selectedPoint!.longitude,
                                precision: 5,
                              ),
                      ),
                    ),
                    FilledButton(
                      onPressed: _selectedPoint == null || _isConfirming
                          ? null
                          : _confirmSelection,
                      child: _isConfirming
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.mapPickerConfirm),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadCurrentLocationIfNeeded,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
