import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_harness.dart';

void main() {
  setUp(TestHarness.initialize);
  tearDown(TestHarness.tearDown);

  test('installs isolated plugin fakes for the current test isolate', () async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final temporaryDirectory = await getTemporaryDirectory();
    final preferences = await SharedPreferences.getInstance();

    expect(PathProviderPlatform.instance, isA<TestPathProviderPlatform>());
    expect(
      documentsDirectory.path,
      equals(TestHarness.applicationDocumentsDirectory.path),
    );
    expect(await documentsDirectory.exists(), isTrue);
    expect(await temporaryDirectory.exists(), isTrue);
    expect(documentsDirectory.path, startsWith(Directory.systemTemp.path));
    expect(preferences.getKeys(), isEmpty);
  });

  test('removes test-owned temporary directories during cleanup', () async {
    final directory = await TestHarness.createTempDirectory('owned');
    await File('${directory.path}/data.txt').writeAsString('test data');

    expect(await directory.exists(), isTrue);
    await TestHarness.tearDown();

    expect(await directory.exists(), isFalse);
  });
}
