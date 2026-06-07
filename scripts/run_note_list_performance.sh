#!/usr/bin/env bash
set -euo pipefail

device_id="${1:-}"
device_args=()
if [[ -n "$device_id" ]]; then
  device_args=(-d "$device_id")
fi

flutter drive \
  --profile \
  "${device_args[@]}" \
  --driver=test_driver/note_list_performance_driver.dart \
  --target=integration_test/note_list_performance_test.dart

summary="build/note_list_mixed_scroll_timeline.timeline_summary.json"
dart run scripts/analyze_note_list_performance.dart "$summary"
