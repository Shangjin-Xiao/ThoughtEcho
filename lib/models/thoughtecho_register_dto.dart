import 'package:thoughtecho/constants/thoughtecho_constants.dart';
import 'package:thoughtecho/models/localsend_device.dart';
import 'package:thoughtecho/models/thoughtecho_multicast_dto.dart';

class RegisterDto {
  final String alias;
  final String? version; // v2, format: major.minor
  final String? deviceModel;
  final DeviceType? deviceType;
  final String fingerprint;
  final int? port; // v2
  final ProtocolType? protocol; // v2
  final bool? download; // v2

  const RegisterDto({
    required this.alias,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.fingerprint,
    required this.port,
    required this.protocol,
    required this.download,
  });

  factory RegisterDto.fromJson(Map<String, dynamic> json) {
    return RegisterDto(
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
    };
  }
}

extension RegisterDtoExt on RegisterDto {
  Device toDevice(String ip, int ownPort, bool ownHttps, DiscoveryMethod method) {
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
      discoveryMethods: {method},
    );
  }
}
