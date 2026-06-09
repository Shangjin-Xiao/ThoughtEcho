import 'dart:convert';
import 'dart:io';

Never _usage() {
  stderr.writeln(
    'Usage: dart run scripts/summarize_firebase_performance_results.dart '
    '<thoughtecho-performance-summary.json>',
  );
  exit(64);
}

String _format(dynamic value) {
  if (value is num) {
    return value.toStringAsFixed(1);
  }
  return '-';
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    _usage();
  }

  final file = File(arguments.single);
  if (!file.existsSync()) {
    stderr.writeln('Summary file not found: ${file.path}');
    exit(66);
  }

  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic> || decoded['scenarios'] is! List) {
    stderr.writeln('Invalid performance summary: ${file.path}');
    exit(65);
  }

  final scenarios =
      (decoded['scenarios'] as List).whereType<Map<String, dynamic>>().toList()
        ..sort(
          (a, b) => (a['scenario']?.toString() ?? '')
              .compareTo(b['scenario']?.toString() ?? ''),
        );

  stdout.writeln('ThoughtEcho Firebase performance summary');
  stdout.writeln(
    [
      'scenario',
      'frames',
      'build99',
      'buildWorst',
      'raster99',
      'rasterWorst',
      'BUILD',
      'RenderSliverList',
      'GPUDraw',
      'itemBuild',
      'itemLayout',
      'sizeChanged',
    ].join('\t'),
  );

  for (final scenario in scenarios) {
    final slowest = scenario['slowest_slices_ms'] is Map<String, dynamic>
        ? scenario['slowest_slices_ms'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final events = scenario['custom_event_counts'] is Map<String, dynamic>
        ? scenario['custom_event_counts'] as Map<String, dynamic>
        : const <String, dynamic>{};

    stdout.writeln(
      [
        scenario['scenario']?.toString() ?? '-',
        scenario['frame_count']?.toString() ?? '-',
        _format(scenario['99th_percentile_frame_build_time_millis']),
        _format(scenario['worst_frame_build_time_millis']),
        _format(scenario['99th_percentile_frame_rasterizer_time_millis']),
        _format(scenario['worst_frame_rasterizer_time_millis']),
        _format(slowest['BUILD']),
        _format(slowest['RenderSliverList']),
        _format(slowest['GPURasterizer::Draw']),
        (events['ThoughtEcho.NoteListView.itemBuilder'] ?? 0).toString(),
        (events['ThoughtEcho.NoteListView.itemLayout'] ?? 0).toString(),
        (events['ThoughtEcho.NoteListView.itemSizeChanged'] ?? 0).toString(),
      ].join('\t'),
    );
  }
}
