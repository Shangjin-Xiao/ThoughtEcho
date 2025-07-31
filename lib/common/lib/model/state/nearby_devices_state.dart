import '../device.dart';

/// State for nearby devices
class NearbyDevicesState {
  final Map<String, Device> devices;
  final Map<String, Set<Device>> signalingDevices;
  final Set<String> runningIps;
  final bool runningFavoriteScan;

  const NearbyDevicesState({
    required this.devices,
    required this.signalingDevices,
    required this.runningIps,
    required this.runningFavoriteScan,
  });

  NearbyDevicesState copyWith({
    Map<String, Device>? devices,
    Map<String, Set<Device>>? signalingDevices,
    Set<String>? runningIps,
    bool? runningFavoriteScan,
  }) {
    return NearbyDevicesState(
      devices: devices ?? this.devices,
      signalingDevices: signalingDevices ?? this.signalingDevices,
      runningIps: runningIps ?? this.runningIps,
      runningFavoriteScan: runningFavoriteScan ?? this.runningFavoriteScan,
    );
  }
}