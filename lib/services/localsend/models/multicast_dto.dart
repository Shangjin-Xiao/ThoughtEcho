import '../constants.dart';
import 'device.dart';

enum ProtocolType { http, https }

class MulticastDto {
  final String alias;
  final String? version; // v2, format: major.minor
  final String? deviceModel;
  final DeviceType? deviceType; // nullable since v2
  final String fingerprint;
  final int? port; // v2
  final ProtocolType? protocol; // v2
  final bool? download; // v2
  final bool? announcement; // v1
  final bool? announce; // v2

  const MulticastDto({
    required this.alias,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.fingerprint,
    required this.port,
    required this.protocol,
    required this.download,
    required this.announcement,
    required this.announce,
  });

  Map<String, dynamic> toJson() {
    return {
      'alias': alias,
      if (version != null) 'version': version,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (deviceType != null) 'deviceType': deviceType!.name,
      'fingerprint': fingerprint,
      if (port != null) 'port': port,
      if (protocol != null) 'protocol': protocol!.name,
      if (download != null) 'download': download,
      if (announcement != null) 'announcement': announcement,
      if (announce != null) 'announce': announce,
    };
  }

  static MulticastDto fromJson(Map<String, dynamic> json) {
    return MulticastDto(
      alias: json['alias'] as String,
      version: json['version'] as String?,
      deviceModel: json['deviceModel'] as String?,
      deviceType: json['deviceType'] != null
          ? DeviceType.values.firstWhere(
              (e) => e.name == json['deviceType'],
              orElse: () => DeviceType.desktop,
            )
          : null,
      fingerprint: json['fingerprint'] as String,
      port: json['port'] as int?,
      protocol: json['protocol'] != null
          ? ProtocolType.values.firstWhere(
              (e) => e.name == json['protocol'],
              orElse: () => ProtocolType.https,
            )
          : null,
      download: json['download'] as bool?,
      announcement: json['announcement'] as bool?,
      announce: json['announce'] as bool?,
    );
  }
}

extension MulticastDtoToDeviceExt on MulticastDto {
  Device toDevice(String ip, int ownPort, bool ownHttps) {
    return Device(
      signalingId: null,
      ip: ip,
      version: version ?? fallbackProtocolVersion,
      port: port ?? ownPort,
      https: protocol != null ? protocol == ProtocolType.https : ownHttps,
      fingerprint: fingerprint,
      alias: alias,
      deviceModel: deviceModel,
      deviceType: deviceType ?? DeviceType.desktop,
      download: download ?? false,
      discoveryMethods: {const MulticastDiscovery()},
    );
  }
}
