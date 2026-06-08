import 'dart:convert';
import 'dart:io';

const String _legacyPrefix = 'THOUGHTECHO_PERF:';
const String _chunkPrefix = 'THOUGHTECHO_PERF_CHUNK:';

Never _usage() {
  stderr.writeln(
    'Usage: dart run scripts/extract_firebase_performance_results.dart '
    '<firebase-results-directory> <output.json>',
  );
  exit(64);
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    _usage();
  }

  final Directory source = Directory(arguments[0]);
  if (!source.existsSync()) {
    stderr.writeln('Firebase results directory not found: ${source.path}');
    exit(66);
  }

  final Map<String, Map<String, dynamic>> scenarios =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<int, String>> scenarioChunks =
      <String, Map<int, String>>{};
  for (final FileSystemEntity entity
      in source.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    String contents;
    try {
      contents = entity.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    for (final String line in const LineSplitter().convert(contents)) {
      final int chunkPrefixIndex = line.indexOf(_chunkPrefix);
      if (chunkPrefixIndex >= 0) {
        final String record =
            line.substring(chunkPrefixIndex + _chunkPrefix.length);
        final int scenarioSeparator = record.indexOf(':');
        final int indexSeparator = record.indexOf(':', scenarioSeparator + 1);
        if (scenarioSeparator > 0 && indexSeparator > scenarioSeparator) {
          final String scenario = record.substring(0, scenarioSeparator);
          final int? chunkIndex = int.tryParse(
            record.substring(scenarioSeparator + 1, indexSeparator),
          );
          if (chunkIndex != null) {
            scenarioChunks.putIfAbsent(
                    scenario, () => <int, String>{})[chunkIndex] =
                record.substring(indexSeparator + 1).trim();
          }
        }
      }

      final int legacyPrefixIndex = line.indexOf(_legacyPrefix);
      if (legacyPrefixIndex < 0) {
        continue;
      }
      final String rawJson =
          line.substring(legacyPrefixIndex + _legacyPrefix.length);
      try {
        final Object? decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic> && decoded['scenario'] is String) {
          scenarios[decoded['scenario'] as String] = decoded;
        }
      } on FormatException {
        // Some Test Lab files truncate long log lines. Other log files from the
        // same execution may still contain the complete JSON record.
      }
    }
  }

  for (final MapEntry<String, Map<int, String>> entry
      in scenarioChunks.entries) {
    final List<MapEntry<int, String>> chunks = entry.value.entries.toList()
      ..sort(
        (MapEntry<int, String> a, MapEntry<int, String> b) =>
            a.key.compareTo(b.key),
      );
    try {
      final String rawJson = utf8.decode(
        base64Decode(chunks.map((MapEntry<int, String> e) => e.value).join()),
      );
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        scenarios[entry.key] = decoded;
      }
    } on FormatException {
      stderr.writeln('Incomplete performance chunks for ${entry.key}');
    }
  }

  if (scenarios.isEmpty) {
    stderr.writeln('No performance records found under ${source.path}');
    exit(65);
  }

  final List<Map<String, dynamic>> ordered = scenarios.values.toList()
    ..sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['scenario'] as String).compareTo(b['scenario'] as String),
    );
  final File output = File(arguments[1]);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'scenarios': ordered,
    }),
  );

  stdout.writeln('Extracted ${ordered.length} performance scenarios:');
  for (final Map<String, dynamic> scenario in ordered) {
    stdout.writeln(
      '${scenario['scenario']}: '
      'buildP99=${scenario['99th_percentile_frame_build_time_millis']}ms, '
      'rasterP99=${scenario['99th_percentile_frame_rasterizer_time_millis']}ms',
    );
  }
}
