/// Favorite device model
class FavoriteDevice {
  final String id;
  final String fingerprint;
  final String ip;
  final int port;
  final String alias;
  final bool customAlias;

  const FavoriteDevice({
    required this.id,
    required this.fingerprint,
    required this.ip,
    required this.port,
    required this.alias,
    this.customAlias = false,
  });

  FavoriteDevice copyWith({
    String? id,
    String? fingerprint,
    String? ip,
    int? port,
    String? alias,
    bool? customAlias,
  }) {
    return FavoriteDevice(
      id: id ?? this.id,
      fingerprint: fingerprint ?? this.fingerprint,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      alias: alias ?? this.alias,
      customAlias: customAlias ?? this.customAlias,
    );
  }
}