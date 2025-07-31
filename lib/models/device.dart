/// Device model for P2P sync functionality
class Device {
  final String id;
  final String alias;
  final String ip;
  final int port;
  final String fingerprint;
  final DeviceType deviceType;
  final String deviceModel;

  const Device({
    required this.id,
    required this.alias,
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.deviceType,
    required this.deviceModel,
  });

  @override
  String toString() {
    return 'Device(id: $id, alias: $alias, ip: $ip:$port)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum DeviceType {
  mobile,
  desktop,
  web,
  headless,
  server,
}