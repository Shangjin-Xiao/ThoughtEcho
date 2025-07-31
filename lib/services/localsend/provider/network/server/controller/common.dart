import 'dart:io';
import 'package:common/util/simple_server.dart';
import '../server_utils.dart';

/// Responds with 401 or 429 if the pin is invalid or too many attempts.
Future<bool> checkPin({
  required ServerUtils server,
  required String? pin,
  required Map<String, int> pinAttempts,
  required HttpRequest request,
}) async {
  if (pin == null || pin.isEmpty) {
    return true; // No pin required
  }
  
  final providedPin = request.uri.queryParameters['pin'];
  if (providedPin == pin) {
    return true;
  }
  
  // Track failed attempts
  final ip = request.ip;
  pinAttempts[ip] = (pinAttempts[ip] ?? 0) + 1;
  
  if (pinAttempts[ip]! > 3) {
    await request.respondJson(429, message: 'Too many attempts');
    return false;
  }
  
  await request.respondJson(401, message: 'Invalid PIN');
  return false;
}
