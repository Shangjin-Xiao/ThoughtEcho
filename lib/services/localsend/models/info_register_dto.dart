import '../constants.dart';
import 'device.dart';
import 'multicast_dto.dart';

/// Used only for /prepare-upload to be compatible with v1.
/// The [fingerprint] does not exist in v1, so it is nullable here.
/// TODO: replace with [RegisterDto] when v1 compatibility is removed
class InfoRegisterDto {
  final String alias;
  final String? version; // v2, format: major.minor
  final String? deviceModel;
  final DeviceType? deviceType;
  final String? fingerprint;
  final int? port; // v2
  final ProtocolType? protocol; // v2
  final bool? download; // v2

  const InfoRegisterDto({
    required this.alias,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.fingerprint,
    required this.port,
    required this.protocol,
    required this.download,
  });

  Map<String, dynamic> toJson() {
    return {
      'alias': alias,
      if (version != null) 'version': version,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (deviceType != null) 'deviceType': deviceType!.name,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (port != null) 'port': port,
      if (protocol != null) 'protocol': protocol!.name,
      if (download != null) 'download': download,
    };
  }

  static InfoRegisterDto fromJson(Map<String, dynamic> json) {
    return InfoRegisterDto(
      alias: json['alias'] as String,
      version: json['version'] as String?,
      deviceModel: json['deviceModel'] as String?,
      deviceType: json['deviceType'] != null 
          ? DeviceType.values.firstWhere(
              (e) => e.name == json['deviceType'],
              orElse: () => DeviceType.desktop,
            )
          : null,
      fingerprint: json['fingerprint'] as String?,
      port: json['port'] as int?,
      protocol: json['protocol'] != null
          ? ProtocolType.values.firstWhere(
              (e) => e.name == json['protocol'],
              orElse: () => ProtocolType.http,
            )
          : null,
      download: json['download'] as bool?,
    );
  }
}

extension InfoRegisterDtoExt on InfoRegisterDto {
  Device toDevice(String ip, int ownPort, bool ownHttps, DiscoveryMethod? method) {
    return Device(
      signalingId: null,
      ip: ip,
      version: version ?? fallbackProtocolVersion,
      port: port ?? ownPort,
      https: protocol != null ? protocol == ProtocolType.https : ownHttps,
      fingerprint: fingerprint ?? '',
      alias: alias,
      deviceModel: deviceModel,
      deviceType: deviceType ?? DeviceType.desktop,
      download: download ?? false,
      discoveryMethods: method == null ? const {} : {method},
    );
  }
}
