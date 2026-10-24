import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/app_navigator_key.dart';

void main() {
  group('AppNavigatorKey Tests', () {
    test('navigatorKey should be correctly initialized', () {
      expect(navigatorKey, isNotNull);
      expect(navigatorKey, isA<GlobalKey<NavigatorState>>());
    });
  });
}
