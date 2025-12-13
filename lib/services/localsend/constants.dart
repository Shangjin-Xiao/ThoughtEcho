/// The protocol version.
///
/// Version table:
/// Protocols | App (Official implementation)
/// ----------|------------------------------
/// 1.0       | 1.0.0 - 1.8.0
/// 1.0, 2.0  | 1.9.0 - 1.14.0
/// 1.0, 2.1  | 1.15.0
const protocolVersion = '2.1';

/// Assumed protocol version of peers for first handshake.
/// Generally this should be slightly lower than the current protocol version.
const peerProtocolVersion = '1.0';

/// The protocol version when no version is specified.
/// Prior v2, the protocol version was not specified.
const fallbackProtocolVersion = '1.0';

/// The default http server port.
/// Using 53320 as the default port for ThoughtEcho sync
const defaultPort = 53320;

/// The default multicast discovery port.
/// Should be different from HTTP server port
const defaultMulticastPort = 53317;

/// The default discovery timeout in milliseconds.
/// This is the time the discovery server or UI waits for responses when actively
/// trying to discover nearby devices. Increased from 500ms to 30000ms (30s) to give
/// devices more time to respond on flaky or slow networks.
/// Keep this value conservative; callers may choose a different timeout.
const defaultDiscoveryTimeout = 30000;

/// The default multicast group should be 224.0.0.0/24
/// because on some Android devices this is the only IP range
/// that can receive UDP multicast messages.
/// Using 224.0.0.170 for ThoughtEcho multicast discovery
const defaultMulticastGroup = '224.0.0.170';

/// Compatibility multicast group used by upstream LocalSend implementations.
/// We broadcast/join both groups to maximize cross-platform discovery.
const localsendCompatibilityMulticastGroup = '224.0.0.167';
