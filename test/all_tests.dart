/// Main test file for ThoughtEcho application
/// This file imports all test suites for easier running
library;

import 'package:flutter_test/flutter_test.dart';

// Import model tests
import 'unit/models/quote_model_test.dart' as quote_model_test;
import 'unit/models/note_category_test.dart' as note_category_test;

// Import service tests
import 'unit/services/database_service_test.dart' as database_service_test;
import 'unit/services/settings_service_test.dart' as settings_service_test;
import 'unit/services/weather_service_test.dart' as weather_service_test;
import 'unit/services/location_service_test.dart' as location_service_test;
import 'unit/services/clipboard_service_test.dart' as clipboard_service_test;
import 'unit/services/ai_analysis_database_service_test.dart'
    as ai_analysis_service_test;
import 'unit/services/location_format_test.dart' as location_format_test;
import 'storage_management_test.dart' as storage_management_test;
import 'performance/day_period_patch_test.dart' as day_period_patch_test;

// Import widget tests
import 'widget/pages/home_page_test.dart' as home_page_test;

void main() {
  group('ThoughtEcho Test Suite', () {
    group('Model Tests', () {
      quote_model_test.main();
      note_category_test.main();
    });

    group('Service Tests', () {
      database_service_test.main();
      settings_service_test.main();
      weather_service_test.main();
      location_service_test.main();
      location_format_test.main();
      clipboard_service_test.main();
      ai_analysis_service_test.main();
      storage_management_test.main();
      day_period_patch_test.main();
    });

    group('Widget Tests', () {
      home_page_test.main();
    });
  });
}
