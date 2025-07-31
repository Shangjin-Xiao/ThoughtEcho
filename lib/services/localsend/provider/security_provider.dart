import 'package:common/model/stored_security_context.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Provider for security context and certificate management
final securityProvider = Provider<StoredSecurityContext>((ref) {
  // Return a default security context for now
  return const StoredSecurityContext(
    certificate: "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----",
    privateKey: "-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----",
    certificateHash: "default-fingerprint",
  );
});
