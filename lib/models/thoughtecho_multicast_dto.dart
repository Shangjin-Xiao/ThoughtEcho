import 'package:thoughtecho/constants/thoughtecho_constants.dart';
import 'package:thoughtecho/models/localsend_device.dart';

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

  factory MulticastDto.fromJson(Map<String, dynamic> json) {
    return MulticastDto(
      alias: json['alias'] as String,
      version: json['version'] as String?,
      deviceModel: json['deviceModel'] as String?,
      deviceType: json['deviceType'] != null ? DeviceType.values.firstWhere(
        (e) => e.toString().split('.').last == json['deviceType'],
        orElse: () => DeviceType.desktop,
      ) : null,
      fingerprint: json['fingerprint'] as String,
      port: json['port'] as int?,
      protocol: json['protocol'] != null ? ProtocolType.values.firstWhere(
        (e) => e.toString().split('.').last == json['protocol'],
        orElse: () => ProtocolType.http,
      ) : null,
      download: json['download'] as bool?,
      announcement: json['announcement'] as bool?,
      announce: json['announce'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alias': alias,
      'version': version,
      'deviceModel': deviceModel,
      'deviceType': deviceType?.toString().split('.').last,
      'fingerprint': fingerprint,
      'port': port,
      'protocol': protocol?.toString().split('.').last,
      'download': download,
      'announcement': announcement,
      'announce': announce,
    };
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
