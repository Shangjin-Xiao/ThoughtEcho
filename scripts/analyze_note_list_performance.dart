import 'dart:convert';
import 'dart:io';

String _format(Object? value) {
  if (value is num) {
    return value.toStringAsFixed(2);
  }
  return value?.toString() ?? 'n/a';
}

Never _usage() {
  stderr.writeln(
    'Usage: dart run scripts/analyze_note_list_performance.dart '
    '<timeline_summary.json> [timeline_summary.json ...]',
  );
  exit(64);
}

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    _usage();
  }

  for (final path in arguments) {
    _printReport(File(path));
  }
}

void _printReport(File file) {
  if (!file.existsSync()) {
    stderr.writeln('Performance summary not found: ${file.path}');
    exit(66);
  }

  final Object? decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('Performance summary is not a JSON object: ${file.path}');
    exit(65);
  }

  const List<(String, String)> fields = <(String, String)>[
    ('frame_count', 'Frames'),
    ('90th_percentile_frame_build_time_millis', 'Build P90 ms'),
    ('99th_percentile_frame_build_time_millis', 'Build P99 ms'),
    ('worst_frame_build_time_millis', 'Build worst ms'),
    ('90th_percentile_frame_rasterizer_time_millis', 'Raster P90 ms'),
    ('99th_percentile_frame_rasterizer_time_millis', 'Raster P99 ms'),
    ('worst_frame_rasterizer_time_millis', 'Raster worst ms'),
    ('missed_frame_build_budget_count', 'Build budget misses'),
    ('missed_frame_rasterizer_budget_count', 'Raster budget misses'),
    ('new_gen_gc_count', 'New-generation GC'),
    ('old_gen_gc_count', 'Old-generation GC'),
  ];

  stdout.writeln('Note list performance report');
  stdout.writeln('Source: ${file.path}');
  for (final (String key, String label) in fields) {
    stdout.writeln('${label.padRight(24)} ${_format(decoded[key])}');
  }
  stdout.writeln();
}
