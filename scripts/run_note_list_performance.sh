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

mapfile -t summaries < <(
  find build -maxdepth 1 -type f \
    -name 'thoughtecho_*.timeline_summary.json' \
    -print | sort
)

if [[ ${#summaries[@]} -eq 0 ]]; then
  echo "No ThoughtEcho performance summaries were generated." >&2
  exit 66
fi

dart run scripts/analyze_note_list_performance.dart "${summaries[@]}"
