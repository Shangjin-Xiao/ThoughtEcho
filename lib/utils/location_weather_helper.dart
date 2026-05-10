import 'package:geolocator/geolocator.dart' show Position;

import '../services/location_service.dart';

class LocationSnapshot {
  const LocationSnapshot({
    required this.position,
    required this.location,
  });

  final Position position;
  final String location;
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

    return LocationSnapshot(
      position: position,
      location: locationService.getFormattedLocation(),
    );
  }
}
