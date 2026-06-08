import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/timeline_slice_extractor.dart';

void main() {
  group('extractTimelineSlices', () {
    test('extracts complete, nested synchronous, and asynchronous slices', () {
      final slices = extractTimelineSlices(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Complete',
          'ph': 'X',
          'pid': 1,
          'tid': 2,
          'ts': 10,
          'dur': 25,
          'args': <String, String>{'widget': 'QuoteContent'},
        },
        <String, dynamic>{
          'name': 'Outer',
          'ph': 'B',
          'pid': 1,
          'tid': 2,
          'ts': 100,
        },
        <String, dynamic>{
          'name': 'Inner',
          'ph': 'B',
          'pid': 1,
          'tid': 2,
          'ts': 110,
        },
        <String, dynamic>{
          'name': 'Inner',
          'ph': 'E',
          'pid': 1,
          'tid': 2,
          'ts': 130,
        },
        <String, dynamic>{
          'name': 'Outer',
          'ph': 'E',
          'pid': 1,
          'tid': 2,
          'ts': 160,
        },
        <String, dynamic>{
          'name': 'Async',
          'cat': 'ThoughtEcho',
          'id': 'task-1',
          'ph': 'b',
          'pid': 1,
          'tid': 2,
          'ts': 200,
        },
        <String, dynamic>{
          'name': 'Async',
          'cat': 'ThoughtEcho',
          'id': 'task-1',
          'ph': 'e',
          'pid': 1,
          'tid': 3,
          'ts': 280,
        },
      ]);

      expect(
        slices.map((slice) => (slice['name'], slice['duration_us'])).toList(),
        <(String, double)>[
          ('Complete', 25),
          ('Inner', 20),
          ('Outer', 60),
          ('Async', 80),
        ],
      );
      expect(
        slices.first['arguments'],
        <String, String>{'widget': 'QuoteContent'},
      );
      expect(
        slices.map((slice) => slice['kind']).toList(),
        <String>['complete', 'synchronous', 'synchronous', 'asynchronous'],
      );
    });

    test('ignores unmatched and zero-duration events', () {
      final slices = extractTimelineSlices(<Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Unmatched',
          'ph': 'E',
          'pid': 1,
          'tid': 2,
          'ts': 10,
        },
        <String, dynamic>{
          'name': 'Zero',
          'ph': 'X',
          'pid': 1,
          'tid': 2,
          'ts': 20,
          'dur': 0,
        },
      ]);

      expect(slices, isEmpty);
    });
  });
}
