/// Model for favorite device persistence

class FavoriteDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final bool https;
  final String? fingerprint;

  const FavoriteDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.https,
    this.fingerprint,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'https': https,
      'fingerprint': fingerprint,
    };
  }

  factory FavoriteDevice.fromJson(Map<String, dynamic> json) {
    return FavoriteDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      https: json['https'] as bool,
      fingerprint: json['fingerprint'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FavoriteDevice(id: $id, name: $name, ip: $ip:$port)';
}
