import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:thoughtecho/models/note_category.dart';

/// Owns the observable navigation and note-list state composed by [HomePage].
///
/// I/O remains behind callbacks so this module can be exercised without a
/// widget tree and does not retain a page [BuildContext].
class HomePageController extends ChangeNotifier {
  HomePageController({required int initialPage}) : _currentIndex = initialPage;

  int _currentIndex;
  List<NoteCategory> _tags = const [];
  List<String> _selectedTagIds = const [];
  bool _isLoadingTags = true;
  String _sortType = 'time';
  bool _sortAscending = false;
  List<String> _selectedWeathers = const [];
  List<String> _selectedDayPeriods = const [];
  int _tagLoadGeneration = 0;
  bool _disposed = false;

  // Transient orchestration state. Keeping it here prevents navigation,
  // guide and intent flows from leaking private flags into the page State.
  bool homeGuidePending = false;
  bool noteGuidePending = false;
  bool settingsGuidePending = false;
  bool trashGuideScheduled = false;
  String? lastConsumedExcerptText;
  bool isHandlingExcerptIntent = false;
  bool hasConsumedInitialTargetNote = false;
  bool isConsumingInitialTargetNote = false;
  int initialTargetScrollRetryCount = 0;
  String? pendingNotificationNoteId;
  Timer? trashSnackBarTimer;

  int get currentIndex => _currentIndex;
  UnmodifiableListView<NoteCategory> get tags => UnmodifiableListView(_tags);
  UnmodifiableListView<String> get selectedTagIds =>
      UnmodifiableListView(_selectedTagIds);
  bool get isLoadingTags => _isLoadingTags;
  String get sortType => _sortType;
  bool get sortAscending => _sortAscending;
  UnmodifiableListView<String> get selectedWeathers =>
      UnmodifiableListView(_selectedWeathers);
  UnmodifiableListView<String> get selectedDayPeriods =>
      UnmodifiableListView(_selectedDayPeriods);

  void selectPage(int index) {
    if (_currentIndex == index) return;
    _currentIndex = index;
    notifyListeners();
  }

  void setSelectedTagIds(Iterable<String> tagIds) {
    final next = List<String>.unmodifiable(tagIds);
    if (listEquals(_selectedTagIds, next)) return;
    _selectedTagIds = next;
    notifyListeners();
  }

  void setSort({required String type, required bool ascending}) {
    if (_sortType == type && _sortAscending == ascending) return;
    _sortType = type;
    _sortAscending = ascending;
    notifyListeners();
  }

  void setFilters({
    required Iterable<String> weathers,
    required Iterable<String> dayPeriods,
  }) {
    final nextWeathers = List<String>.unmodifiable(weathers);
    final nextDayPeriods = List<String>.unmodifiable(dayPeriods);
    if (listEquals(_selectedWeathers, nextWeathers) &&
        listEquals(_selectedDayPeriods, nextDayPeriods)) {
      return;
    }
    _selectedWeathers = nextWeathers;
    _selectedDayPeriods = nextDayPeriods;
    notifyListeners();
  }

  /// Loads tags as one state transition and ignores an older overlapping load.
  Future<void> loadTags(
    Future<List<NoteCategory>> Function() fetchTags,
  ) async {
    final generation = ++_tagLoadGeneration;
    if (!_isLoadingTags) {
      _isLoadingTags = true;
      notifyListeners();
    }

    try {
      final tags = await fetchTags();
      if (_disposed || generation != _tagLoadGeneration) return;
      _tags = List<NoteCategory>.unmodifiable(tags);
    } finally {
      if (!_disposed && generation == _tagLoadGeneration) {
        _isLoadingTags = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _tagLoadGeneration++;
    trashSnackBarTimer?.cancel();
    super.dispose();
  }
}
