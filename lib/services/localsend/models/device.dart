// LocalSend device models adapted for ThoughtEcho

enum DeviceType {
  mobile,
  desktop,
  web,
  headless,
  server,
}

sealed class DiscoveryMethod {
  const DiscoveryMethod();

  Map<String, dynamic> toJson();

  static DiscoveryMethod fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'multicast':
        return const MulticastDiscovery();
      case 'http':
        return HttpDiscovery(ip: json['ip'] as String);
      case 'signaling':
        return SignalingDiscovery(signalingServer: json['signalingServer'] as String);
      default:
        throw ArgumentError('Unknown discovery method type: $type');
    }
  }
}

class MulticastDiscovery extends DiscoveryMethod {
  const MulticastDiscovery();

  @override
  Map<String, dynamic> toJson() => {'type': 'multicast'};

  @override
  bool operator ==(Object other) => other is MulticastDiscovery;

  @override
  int get hashCode => 'multicast'.hashCode;
}

class HttpDiscovery extends DiscoveryMethod {
  final String ip;

  const HttpDiscovery({required this.ip});

  @override
  Map<String, dynamic> toJson() => {'type': 'http', 'ip': ip};

  @override
  bool operator ==(Object other) => other is HttpDiscovery && other.ip == ip;

  @override
  int get hashCode => Object.hash('http', ip);
}

class SignalingDiscovery extends DiscoveryMethod {
  final String signalingServer;

  const SignalingDiscovery({required this.signalingServer});

  @override
  Map<String, dynamic> toJson() => {'type': 'signaling', 'signalingServer': signalingServer};

  @override
  bool operator ==(Object other) => other is SignalingDiscovery && other.signalingServer == signalingServer;

  @override
  int get hashCode => Object.hash('signaling', signalingServer);
}

enum TransmissionMethod {
  http('HTTP'),
  webrtc('WebRTC');

  final String label;

  const TransmissionMethod(this.label);
}

/// Internal device model.
/// It gets not serialized.
class Device {
  /// A unique ID provided by the signaling server.
  final String? signalingId;

  /// The IP address of the device.
  /// Is null when found via signaling.
  final String? ip;

  final String version;
  final int port;
  final bool https;
  final String fingerprint;
  final String alias;
  final String? deviceModel;
  final DeviceType deviceType;
  final bool download;
  final Set<DiscoveryMethod> discoveryMethods;

  Set<TransmissionMethod> get transmissionMethods {
    bool http = false;
    bool webrtc = false;

    for (final method in discoveryMethods) {
      if (method is SignalingDiscovery) {
        webrtc = true;
      } else {
        http = true;
      }
    }

    final methods = <TransmissionMethod>{};
    if (http) {
      methods.add(TransmissionMethod.http);
    }
    if (webrtc) {
      methods.add(TransmissionMethod.webrtc);
    }

    return methods;
  }

  const Device({
    required this.signalingId,
    required this.ip,
    required this.version,
    required this.port,
    required this.https,
    required this.fingerprint,
    required this.alias,
    required this.deviceModel,
    required this.deviceType,
    required this.download,
    required this.discoveryMethods,
  });

  static const empty = Device(
    signalingId: null,
    ip: null,
    version: '',
    port: -1,
    https: false,
    fingerprint: '',
    alias: '',
    deviceModel: null,
    deviceType: DeviceType.desktop,
    download: false,
    discoveryMethods: {},
  );

  Device copyWith({
    String? signalingId,
    String? ip,
    String? version,
    int? port,
    bool? https,
    String? fingerprint,
    String? alias,
    String? deviceModel,
    DeviceType? deviceType,
    bool? download,
    Set<DiscoveryMethod>? discoveryMethods,
  }) {
    return Device(
      signalingId: signalingId ?? this.signalingId,
      ip: ip ?? this.ip,
      version: version ?? this.version,
      port: port ?? this.port,
      https: https ?? this.https,
      fingerprint: fingerprint ?? this.fingerprint,
      alias: alias ?? this.alias,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceType: deviceType ?? this.deviceType,
      download: download ?? this.download,
      discoveryMethods: discoveryMethods ?? this.discoveryMethods,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'signalingId': signalingId,
      'ip': ip,
      'version': version,
      'port': port,
      'https': https,
      'fingerprint': fingerprint,
      'alias': alias,
      'deviceModel': deviceModel,
      'deviceType': deviceType.name,
      'download': download,
      'discoveryMethods': discoveryMethods.map((e) => e.toJson()).toList(),
    };
  }

  static Device fromJson(Map<String, dynamic> json) {
    return Device(
      signalingId: json['signalingId'] as String?,
      ip: json['ip'] as String?,
      version: json['version'] as String,
      port: json['port'] as int,
      https: json['https'] as bool,
      fingerprint: json['fingerprint'] as String,
      alias: json['alias'] as String,
      deviceModel: json['deviceModel'] as String?,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == json['deviceType'],
        orElse: () => DeviceType.desktop,
      ),
      download: json['download'] as bool,
      discoveryMethods: (json['discoveryMethods'] as List<dynamic>)
          .map((e) => DiscoveryMethod.fromJson(e as Map<String, dynamic>))
          .toSet(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Device &&
        other.signalingId == signalingId &&
        other.ip == ip &&
        other.version == version &&
        other.port == port &&
        other.https == https &&
        other.fingerprint == fingerprint &&
        other.alias == alias &&
        other.deviceModel == deviceModel &&
        other.deviceType == deviceType &&
        other.download == download &&
        other.discoveryMethods.length == discoveryMethods.length &&
        other.discoveryMethods.containsAll(discoveryMethods);
  }

  @override
  int get hashCode {
    return Object.hash(
      signalingId,
      ip,
      version,
      port,
      https,
      fingerprint,
      alias,
      deviceModel,
      deviceType,
      download,
      discoveryMethods.length,
    );
  }
}
