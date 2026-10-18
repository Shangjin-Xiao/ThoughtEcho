import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/add_note_controller.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/services/database_service.dart';

class BenchmarkDatabaseService extends DatabaseService {
  BenchmarkDatabaseService(this.tagsMap) : super.forTesting();

  final Map<String, NoteTag> tagsMap;

  @override
  Future<List<NoteTag>> getTags() async {
    return tagsMap.values.toList();
  }

  @override
  Future<NoteTag?> getTagById(String id) async {
    return tagsMap[id];
  }

  @override
  bool get isInitialized => true;
}

class FakeBuildContext extends Fake implements BuildContext {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Benchmark ensureTagExists lookup performance', () async {
    // Generate 500 tags to simulate a realistic or larger tag dataset
    final Map<String, NoteTag> tagsMap = {};
    for (int i = 0; i < 500; i++) {
      final id = 'tag_id_$i';
      final name = 'Tag Name $i';
      tagsMap[id] = NoteTag(id: id, name: name, iconName: '🏷️');
    }
    tagsMap['default_hitokoto'] =
        NoteTag(id: 'default_hitokoto', name: '每日一言', iconName: '💭');
    tagsMap['default_anime'] =
        NoteTag(id: 'default_anime', name: '动画', iconName: '🎬');

    final db = BenchmarkDatabaseService(tagsMap);

    // Warm up VM
    final controller = AddNoteController(context: FakeBuildContext())
      ..updateServices(dbService: db);
    await controller.ensureTagExists(db, '动画', '🎬', fixedId: 'default_anime');

    const iterations = 50000;

    // Benchmark O(1) Map Lookup
    final stopwatchMap = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      await controller.ensureTagExists(
        db,
        '动画',
        '🎬',
        fixedId: 'default_anime',
      );
      await controller.ensureTagExists(
        db,
        'tag name 499',
        '🏷️',
      );
    }
    stopwatchMap.stop();

    final elapsedMsMap = stopwatchMap.elapsedMilliseconds;
    final usPerOpMap = (stopwatchMap.elapsedMicroseconds / (iterations * 2))
        .toStringAsFixed(2);

    debugPrint(
      'Map lookup time for ${iterations * 2} lookups: $elapsedMsMap ms ($usPerOpMap us/op)',
    );

    expect(elapsedMsMap, greaterThanOrEqualTo(0));
  });
}
