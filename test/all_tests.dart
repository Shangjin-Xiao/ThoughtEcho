/// Main test file for ThoughtEcho application
/// This file imports all test suites for easier running
library;

import 'package:flutter_test/flutter_test.dart';

// Import model tests
import 'unit/models/quote_model_test.dart' as quote_model_test;
import 'unit/models/note_category_test.dart' as note_category_test;
import 'unit/models/weather_data_test.dart' as weather_data_test;

// Import service tests
import 'unit/services/database_service_test.dart' as database_service_test;
import 'unit/services/database_health_service_test.dart'
    as database_health_service_test;
import 'unit/services/excerpt_intent_service_test.dart'
    as excerpt_intent_service_test;
import 'unit/services/settings_service_test.dart' as settings_service_test;
import 'unit/services/weather_service_test.dart' as weather_service_test;
import 'unit/services/location_service_test.dart' as location_service_test;
import 'unit/services/clipboard_service_test.dart' as clipboard_service_test;
import 'unit/services/ai_analysis_database_service_test.dart'
    as ai_analysis_service_test;
import 'unit/services/database_health_security_test.dart'
    as database_health_security_test;
import 'unit/services/location_format_test.dart' as location_format_test;
import 'unit/services/log_service_adapter_test.dart'
    as log_service_adapter_test;
import 'unit/services/smart_push_security_test.dart'
    as smart_push_security_test;
import 'storage_management_test.dart' as storage_management_test;
import 'performance/day_period_patch_test.dart' as day_period_patch_test;

// Import utility tests
import 'unit/time_utils_test.dart' as time_utils_test;
import 'unit/utils/time_utils_test.dart' as time_utils_utils_test;
import 'unit/utils/anniversary_display_utils_test.dart'
    as anniversary_display_utils_test;
import 'unit/utils/anniversary_banner_text_utils_test.dart'
    as anniversary_banner_text_utils_test;
import 'unit/utils/motion_photo_utils_test.dart' as motion_photo_utils_test;
import 'unit/utils/quill_ai_apply_utils_test.dart' as quill_ai_apply_utils_test;
import 'unit/utils/http_utils_test.dart' as http_utils_test;
import 'unit/utils/memory_optimization_helper_test.dart'
    as memory_optimization_helper_test;
import 'unit/utils/media_optimization_utils_test.dart'
    as media_optimization_utils_test;
import 'unit/utils/lww_decision_maker_test.dart' as lww_decision_maker_test;
import 'unit/widgets/anniversary_animation_overlay_test.dart'
    as anniversary_animation_overlay_test;
import 'unit/widgets/anniversary_notebook_icon_test.dart'
    as anniversary_notebook_icon_test;
import 'unit/widgets/motion_photo_preview_page_test.dart'
    as motion_photo_preview_page_test;

// Import widget tests
// Import controller tests
import 'unit/controllers/search_controller_test.dart' as search_controller_test;

import 'widget/pages/home_page_test.dart' as home_page_test;

void main() {
  group('ThoughtEcho Test Suite', () {
    group('Model Tests', () {
      quote_model_test.main();
      note_category_test.main();
      weather_data_test.main();
    });

    group('Service Tests', () {
      database_service_test.main();
      database_health_service_test.main();
      excerpt_intent_service_test.main();
      settings_service_test.main();
      weather_service_test.main();
      location_service_test.main();
      location_format_test.main();
      clipboard_service_test.main();
      ai_analysis_service_test.main();
      database_health_security_test.main();
      log_service_adapter_test.main();
      smart_push_security_test.main();
      storage_management_test.main();
      day_period_patch_test.main();
    });

    group('Utility Tests', () {
      time_utils_test.main();
      time_utils_utils_test.main();
      anniversary_banner_text_utils_test.main();
      anniversary_display_utils_test.main();
      motion_photo_utils_test.main();
      quill_ai_apply_utils_test.main();
      http_utils_test.main();
      memory_optimization_helper_test.main();
      media_optimization_utils_test.main();
      lww_decision_maker_test.main();
      anniversary_animation_overlay_test.main();
      anniversary_notebook_icon_test.main();
      motion_photo_preview_page_test.main();
    });

    group('Controller Tests', () {
      search_controller_test.main();
    });

    group('Widget Tests', () {
      // excerpt_preferences_page_test 未并入全量入口，避免增加现有测试套件内存压力
      home_page_test.main();
    });
  });
}
