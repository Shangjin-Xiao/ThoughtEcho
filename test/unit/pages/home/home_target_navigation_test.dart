import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/pages/home/home_target_navigation.dart';

void main() {
  test('notification target selects notes, loads tags, then scrolls', () async {
    var currentPage = 0;
    var tagsLoading = true;
    final events = <String>[];
    final navigation = HomeTargetNavigation(
      initialTargetNoteId: null,
      currentPage: () => currentPage,
      selectNotesPage: () {
        currentPage = 1;
        events.add('select');
      },
      isTagsLoading: () => tagsLoading,
      ensureTagsLoaded: () async {
        tagsLoading = false;
        events.add('tags');
      },
      scrollToNote: (noteId) async {
        events.add('scroll:$noteId');
        return true;
      },
    );

    await navigation.acceptNotificationTarget('note-1');

    expect(events, ['select', 'tags', 'scroll:note-1']);
    navigation.dispose();
  });

  test('a notification target supersedes the cold-start target', () async {
    final scrolledIds = <String>[];
    final navigation = HomeTargetNavigation(
      initialTargetNoteId: 'cold-start',
      currentPage: () => 1,
      selectNotesPage: () {},
      isTagsLoading: () => false,
      ensureTagsLoaded: () async {},
      scrollToNote: (noteId) async {
        scrolledIds.add(noteId);
        return true;
      },
    );

    await navigation.acceptNotificationTarget('notification');
    navigation.onNotesReady();
    await Future<void>.delayed(Duration.zero);

    expect(scrolledIds, ['notification']);
    navigation.dispose();
  });
}
