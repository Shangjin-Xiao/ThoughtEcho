import 'dart:async';

import 'package:flutter/material.dart';

import 'package:thoughtecho/pages/settings_page.dart';
import 'package:thoughtecho/utils/feature_guide_helper.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

/// Owns home-page guide eligibility, scheduling and sequencing.
class HomeGuideCoordinator {
  HomeGuideCoordinator({
    required this.context,
    required this.isMounted,
    required this.currentPage,
    required this.dailyQuoteKey,
    required this.noteListKey,
    required this.noteFilterKey,
    required this.noteFavoriteKey,
    required this.noteMoreKey,
    required this.noteFoldKey,
    required this.settingsTabKey,
    required this.settingsPageKey,
  });

  final BuildContext context;
  final bool Function() isMounted;
  final int Function() currentPage;
  final GlobalKey dailyQuoteKey;
  final GlobalKey<NoteListViewState> noteListKey;
  final GlobalKey noteFilterKey;
  final GlobalKey noteFavoriteKey;
  final GlobalKey noteMoreKey;
  final GlobalKey noteFoldKey;
  final GlobalKey settingsTabKey;
  final GlobalKey<SettingsPageState> settingsPageKey;

  bool _homePending = false;
  bool _notePending = false;
  bool _settingsPending = false;
  bool _trashPending = false;
  Timer? _noteDelay;
  Timer? _trashDelay;
  bool _disposed = false;

  bool get _active => !_disposed && isMounted() && context.mounted;

  void triggerForCurrentPage() {
    switch (currentPage()) {
      case 0:
        _scheduleHomeGuide();
      case 1:
        _scheduleNoteGuide();
      case 3:
        _scheduleSettingsGuide();
    }
  }

  void onNoteTargetsReady({required VoidCallback onConsumeTarget}) {
    if (!_active || currentPage() != 1) return;
    onConsumeTarget();
    _scheduleNoteGuide(delay: const Duration(milliseconds: 150));
  }

  void unfocusNoteSearch() {
    noteListKey.currentState?.unfocusSearchField();
  }

  void scheduleTrashLocationGuide() {
    if (!_active ||
        _trashPending ||
        FeatureGuideHelper.hasShown(context, 'trash_location_guide')) {
      return;
    }
    _trashPending = true;
    _trashDelay?.cancel();
    _trashDelay = Timer(const Duration(milliseconds: 1200), () {
      if (!_active) {
        _trashPending = false;
        return;
      }
      unawaited(
        FeatureGuideHelper.show(
          context: context,
          guideId: 'trash_location_guide',
          targetKey: settingsTabKey,
          autoDismissDuration: const Duration(milliseconds: 3000),
          shouldShow: () => _active,
        ).whenComplete(() => _trashPending = false),
      );
    });
  }

  void _scheduleHomeGuide() {
    if (_homePending ||
        FeatureGuideHelper.hasShown(context, 'homepage_daily_quote')) {
      return;
    }
    _homePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_active || currentPage() != 0) {
        _homePending = false;
        return;
      }
      await FeatureGuideHelper.show(
        context: context,
        guideId: 'homepage_daily_quote',
        targetKey: dailyQuoteKey,
        shouldShow: () => _active && currentPage() == 0,
      );
      _homePending = false;
    });
  }

  void _scheduleNoteGuide({Duration delay = Duration.zero}) {
    if (_notePending || _allNoteGuidesShown()) return;
    _notePending = true;

    void schedule() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!_active || currentPage() != 1) {
          _notePending = false;
          return;
        }
        await _showNoteGuides();
        _notePending = false;
      });
    }

    _noteDelay?.cancel();
    if (delay == Duration.zero) {
      schedule();
    } else {
      _noteDelay = Timer(delay, schedule);
    }
  }

  bool _allNoteGuidesShown() {
    return FeatureGuideHelper.hasShown(context, 'note_page_filter') &&
        FeatureGuideHelper.hasShown(context, 'note_page_favorite') &&
        FeatureGuideHelper.hasShown(context, 'note_page_expand');
  }

  Future<void> _showNoteGuides() async {
    final noteListState = noteListKey.currentState;
    if (noteListState == null) return;
    final guides = <(String, GlobalKey?)>[];

    if (!FeatureGuideHelper.hasShown(context, 'note_page_filter') &&
        noteListState.isFilterGuideReady) {
      guides.add(('note_page_filter', noteFilterKey));
    }
    if (!FeatureGuideHelper.hasShown(context, 'note_page_favorite') &&
        noteListState.canShowFavoriteGuide) {
      guides.add(('note_page_favorite', noteFavoriteKey));
    }
    if (!FeatureGuideHelper.hasShown(context, 'note_page_expand') &&
        noteListState.canShowExpandGuide) {
      guides.add(('note_page_expand', noteFoldKey));
    }
    if (!FeatureGuideHelper.hasShown(context, 'note_item_more_share') &&
        noteListState.hasQuotes) {
      guides.add(('note_item_more_share', noteMoreKey));
    }
    if (guides.isEmpty) return;

    await FeatureGuideHelper.showSequence(
      context: context,
      guides: guides,
      shouldShow: () => _active && currentPage() == 1,
    );
  }

  void _scheduleSettingsGuide() {
    if (_settingsPending) return;
    final allShown =
        FeatureGuideHelper.hasShown(context, 'settings_preferences') &&
            FeatureGuideHelper.hasShown(context, 'settings_startup') &&
            FeatureGuideHelper.hasShown(context, 'settings_theme');
    if (allShown) return;

    _settingsPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_active || currentPage() != 3) {
        _settingsPending = false;
        return;
      }
      settingsPageKey.currentState?.showGuidesIfNeeded(
        shouldShow: () => _active && currentPage() == 3,
      );
      _settingsPending = false;
    });
  }

  void dispose() {
    _disposed = true;
    _noteDelay?.cancel();
    _trashDelay?.cancel();
  }
}
