import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      if (data == null) {
        return;
      }

      for (final MapEntry<String, dynamic> entry in data.entries) {
        final Object? value = entry.value;
        if (value is! Map<String, dynamic> ||
            value['traceEvents'] is! List<dynamic>) {
          await writeResponseData(
            value is Map<String, dynamic>
                ? value
                : <String, dynamic>{'value': value},
            testOutputFilename: entry.key,
          );
          continue;
        }

        final driver.Timeline timeline = driver.Timeline.fromJson(value);
        final driver.TimelineSummary summary =
            driver.TimelineSummary.summarize(timeline);
        await summary.writeTimelineToFile(
          entry.key,
          pretty: true,
          includeSummary: true,
        );
      }
    },
  );
}
