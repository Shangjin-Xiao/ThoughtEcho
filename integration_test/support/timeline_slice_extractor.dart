/// Converts Chrome trace complete events and begin/end event pairs into
/// duration-bearing slices.
List<Map<String, dynamic>> extractTimelineSlices(List<dynamic> rawEvents) {
  final List<Map<String, dynamic>> slices = <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> synchronousStacks =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, Map<String, dynamic>> asynchronousBegins =
      <String, Map<String, dynamic>>{};

  for (final dynamic rawEvent in rawEvents) {
    if (rawEvent is! Map<String, dynamic>) {
      continue;
    }

    final String phase = rawEvent['ph']?.toString() ?? '';
    final String name = rawEvent['name']?.toString() ?? '';
    final num? timestamp = rawEvent['ts'] as num?;
    if (timestamp == null) {
      continue;
    }

    if (phase == 'X') {
      final num? duration = rawEvent['dur'] as num?;
      if (name.isNotEmpty && duration != null && duration > 0) {
        slices.add(
          _sliceFrom(rawEvent, name, timestamp, duration, kind: 'complete'),
        );
      }
      continue;
    }

    final String threadKey = '${rawEvent['pid']}:${rawEvent['tid']}';
    if (phase == 'B') {
      synchronousStacks
          .putIfAbsent(threadKey, () => <Map<String, dynamic>>[])
          .add(rawEvent);
      continue;
    }
    if (phase == 'E') {
      final List<Map<String, dynamic>>? stack = synchronousStacks[threadKey];
      if (stack == null || stack.isEmpty) {
        continue;
      }
      final Map<String, dynamic> begin = stack.removeLast();
      final String beginName = begin['name']?.toString() ?? '';
      final num? beginTimestamp = begin['ts'] as num?;
      if (beginName.isNotEmpty &&
          beginTimestamp != null &&
          timestamp > beginTimestamp) {
        slices.add(
          _sliceFrom(
            begin,
            beginName,
            beginTimestamp,
            timestamp - beginTimestamp,
            kind: 'synchronous',
          ),
        );
      }
      continue;
    }

    if (phase == 'b') {
      asynchronousBegins[_asyncKey(rawEvent)] = rawEvent;
      continue;
    }
    if (phase == 'e') {
      final Map<String, dynamic>? begin =
          asynchronousBegins.remove(_asyncKey(rawEvent));
      final String beginName = begin?['name']?.toString() ?? '';
      final num? beginTimestamp = begin?['ts'] as num?;
      if (begin != null &&
          beginName.isNotEmpty &&
          beginTimestamp != null &&
          timestamp > beginTimestamp) {
        slices.add(
          _sliceFrom(
            begin,
            beginName,
            beginTimestamp,
            timestamp - beginTimestamp,
            kind: 'asynchronous',
          ),
        );
      }
    }
  }

  return slices;
}

String _asyncKey(Map<String, dynamic> event) {
  final Object? id = event['id'] ?? event['id2'];
  return '${event['pid']}:${event['cat']}:${event['name']}:$id';
}

Map<String, dynamic> _sliceFrom(
  Map<String, dynamic> event,
  String name,
  num timestamp,
  num duration, {
  required String kind,
}) {
  return <String, dynamic>{
    'name': name,
    'kind': kind,
    if (event['cat'] != null) 'category': event['cat'].toString(),
    if (event['tid'] != null) 'thread_id': event['tid'],
    if (event['args'] case final Map<dynamic, dynamic> arguments
        when arguments.isNotEmpty)
      'arguments': _compactArguments(arguments),
    'timestamp_us': timestamp.toDouble(),
    'duration_us': duration.toDouble(),
  };
}

Map<String, String> _compactArguments(Map<dynamic, dynamic> arguments) {
  return <String, String>{
    for (final MapEntry<dynamic, dynamic> entry in arguments.entries.take(4))
      entry.key.toString(): _truncate(entry.value.toString(), 200),
  };
}

String _truncate(String value, int maxLength) {
  return value.length <= maxLength
      ? value
      : '${value.substring(0, maxLength - 3)}...';
}
