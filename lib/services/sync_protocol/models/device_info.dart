/// 设备信息模型
/// 简化版本的LocalSend设备信息
library;

enum DeviceType {
  mobile,
  desktop,
  web,
  headless,
  server,
}

enum ProtocolType { 
  http, 
  https 
}

/// 设备信息DTO
class DeviceInfo {
  final String alias;
  final String version;
  final String deviceModel;
  final DeviceType deviceType;
  final String fingerprint;
  final int port;
  final ProtocolType protocol;
  final bool download;

  const DeviceInfo({
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
      'version': version,
      'deviceModel': deviceModel,
      'deviceType': deviceType.name,
      'fingerprint': fingerprint,
      'port': port,
      'protocol': protocol.name,
      'download': download,
    };
  }

  static DeviceInfo fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      alias: json['alias'] as String,
      version: json['version'] as String,
      deviceModel: json['deviceModel'] as String,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == json['deviceType'],
        orElse: () => DeviceType.mobile,
      ),
      fingerprint: json['fingerprint'] as String,
      port: json['port'] as int,
      protocol: ProtocolType.values.firstWhere(
        (e) => e.name == json['protocol'],
        orElse: () => ProtocolType.http,
      ),
      download: json['download'] as bool,
    );
  }
}

/// 网络设备信息
class NetworkDevice {
  final String ip;
  final int port;
  final DeviceInfo info;
  final bool https;

  const NetworkDevice({
    required this.ip,
    required this.port,
    required this.info,
    required this.https,
  });

  String get baseUrl => '${https ? 'https' : 'http'}://$ip:$port';
}
