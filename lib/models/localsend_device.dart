/// Device model for LocalSend integration in ThoughtEcho

class Device {
  final String ip;
  final int port;
  final String alias;
  final String deviceType;
  final String fingerprint;

  const Device({
    required this.ip,
    required this.port,
    required this.alias,
    required this.deviceType,
    required this.fingerprint,
  });

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'alias': alias,
      'deviceType': deviceType,
      'fingerprint': fingerprint,
    };
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      ip: json['ip'] as String,
      port: json['port'] as int,
      alias: json['alias'] as String,
      deviceType: json['deviceType'] as String,
      fingerprint: json['fingerprint'] as String,
    );
  }

  @override
  String toString() => 'Device(ip: $ip, alias: $alias)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => Object.hash(ip, port, fingerprint);
}
