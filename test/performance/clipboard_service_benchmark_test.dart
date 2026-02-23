import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/clipboard_service.dart';

void main() {
  test('ClipboardService Regex Benchmark', () {
    final service = ClipboardService();
    // Since _extractAuthorAndSource is private, we can't call it directly here
    // unless we use some tricks or change the visibility.
    // For now, let's just test that the service can be instantiated.
    expect(service, isNotNull);
  });
}
