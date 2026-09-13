import 'package:geolocator/geolocator.dart' show Position;

import '../services/location_service.dart';

class LocationSnapshot {
  const LocationSnapshot({
    required this.position,
    required this.location,
    this.poiName,
  });

  final Position position;
  final String location;
  final String? poiName;
}

class LocationWeatherHelper {
  const LocationWeatherHelper._();

  static Future<bool> ensureLocationPermission(
    LocationService locationService,
  ) async {
    if (locationService.hasLocationPermission) {
      return true;
    }

    return locationService.requestLocationPermission();
  }

  static Future<LocationSnapshot?> fetchLocation(
    LocationService locationService,
  ) async {
    final position = await locationService.getCurrentLocation();
    if (position == null) {
      return null;
    }

    String? poiName;
    try {
      poiName = locationService.currentPoiName;
    } catch (_) {
      poiName = null;
    }

    return LocationSnapshot(
      position: position,
      location: locationService.getFormattedLocation(),
      poiName: poiName,
    );
  }
}
