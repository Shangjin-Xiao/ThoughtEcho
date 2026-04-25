part of '../home_page.dart';

/// Extension for feature guide logic
extension _HomeGuides on _HomePageState {
  /// 根据当前选中的标签页触发对应的功能引导
  void _triggerGuideForCurrentIndex() {
    switch (_currentIndex) {
      case 0:
        _scheduleHomeGuideIfNeeded();
        break;
      case 1:
        _scheduleNoteGuideIfNeeded();
        break;
      case 3:
        _scheduleSettingsGuideIfNeeded();
        break;
      default:
        break;
    }
  }

  void _scheduleHomeGuideIfNeeded() {
    if (_homeGuidePending) return;
    if (FeatureGuideHelper.hasShown(context, 'homepage_daily_quote')) {
      return;
    }

    _homeGuidePending = true;
    // 立即显示，不等待
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _homeGuidePending = false;
        return;
      }

      if (_currentIndex != 0) {
        _homeGuidePending = false;
        return;
      }

      await _showHomePageGuides();
      _homeGuidePending = false;
    });
  }

  void _scheduleNoteGuideIfNeeded({Duration delay = Duration.zero}) {
    if (_noteGuidePending) return;

    final filterShown = FeatureGuideHelper.hasShown(
      context,
      'note_page_filter',
    );
    final favoriteShown = FeatureGuideHelper.hasShown(
      context,
      'note_page_favorite',
    );
    final expandShown = FeatureGuideHelper.hasShown(
      context,
      'note_page_expand',
    );

    if (filterShown && favoriteShown && expandShown) {
      return;
    }

    _noteGuidePending = true;
    if (delay == Duration.zero) {
      // 立即显示
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _noteGuidePending = false;
          return;
        }

        if (_currentIndex != 1) {
          _noteGuidePending = false;
          return;
        }

        await _showNotePageGuides();
        _noteGuidePending = false;
      });
    } else {
      Future.delayed(delay, () async {
        if (!mounted) {
          _noteGuidePending = false;
          return;
        }

        if (_currentIndex != 1) {
          _noteGuidePending = false;
          return;
        }

        await _showNotePageGuides();
        _noteGuidePending = false;
      });
    }
  }

  void _handleNoteGuideTargetsReady() {
    if (!mounted) return;
    if (_currentIndex != 1) {
      return;
    }

    _consumeInitialHighlightedNote();
    _scheduleNoteGuideIfNeeded(delay: const Duration(milliseconds: 150));
  }

  void _consumeInitialHighlightedNote() {
    if (!mounted || _hasConsumedInitialHighlightedNote || _currentIndex != 1) {
      return;
    }

    final noteId = widget.initialHighlightedNoteId;
    if (noteId == null || noteId.isEmpty) {
      return;
    }

    context.read<NoteSearchController>().clearSearch();

    final noteListState = _noteListViewKey.currentState;
    if (noteListState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _consumeInitialHighlightedNote();
      });
      return;
    }

    _hasConsumedInitialHighlightedNote = true;
    noteListState.scrollToQuoteById(noteId);
  }

  void _scheduleSettingsGuideIfNeeded() {
    if (_settingsGuidePending) return;

    final allShown =
        FeatureGuideHelper.hasShown(context, 'settings_preferences') &&
            FeatureGuideHelper.hasShown(context, 'settings_startup') &&
            FeatureGuideHelper.hasShown(context, 'settings_theme');
    if (allShown) {
      return;
    }

    _settingsGuidePending = true;
    // 立即显示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _settingsGuidePending = false;
        return;
      }

      if (_currentIndex != 3) {
        _settingsGuidePending = false;
        return;
      }

      _settingsPageKey.currentState?.showGuidesIfNeeded(
        shouldShow: () => mounted && _currentIndex == 3,
      );
      _settingsGuidePending = false;
    });
  }

  /// 显示回收站位置引导（删除笔记后）
  void _scheduleTrashLocationGuide() {
    if (!mounted) return;
    if (FeatureGuideHelper.hasShown(context, 'trash_location_guide')) {
      return;
    }

    // 等待 SnackBar 显示完成后再显示引导气泡
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      FeatureGuideHelper.show(
        context: context,
        guideId: 'trash_location_guide',
        targetKey: _settingsTabGuideKey,
        autoDismissDuration: const Duration(milliseconds: 3000), // 稍长一点，让用户看清
        shouldShow: () => mounted,
      );
    });
  }

  /// 显示首页功能引导
  Future<void> _showHomePageGuides() {
    return FeatureGuideHelper.show(
      context: context,
      guideId: 'homepage_daily_quote',
      targetKey: _dailyQuoteGuideKey,
      shouldShow: () => mounted && _currentIndex == 0,
    );
  }

  /// 显示记录页功能引导
  Future<void> _showNotePageGuides() async {
    final noteListState = _noteListViewKey.currentState;
    if (noteListState == null) {
      return;
    }

    final guides = <(String, GlobalKey?)>[];

    if (!FeatureGuideHelper.hasShown(context, 'note_page_filter') &&
        noteListState.isFilterGuideReady) {
      guides.add(('note_page_filter', _noteFilterGuideKey));
    }

    if (!FeatureGuideHelper.hasShown(context, 'note_page_favorite') &&
        noteListState.canShowFavoriteGuide) {
      guides.add(('note_page_favorite', _noteFavoriteGuideKey));
    }

    if (!FeatureGuideHelper.hasShown(context, 'note_page_expand') &&
        noteListState.canShowExpandGuide) {
      guides.add(('note_page_expand', _noteFoldGuideKey));
    }

    if (!FeatureGuideHelper.hasShown(context, 'note_item_more_share') &&
        noteListState.hasQuotes) {
      guides.add(('note_item_more_share', _noteMoreGuideKey));
    }

    if (guides.isEmpty) {
      return;
    }

    await FeatureGuideHelper.showSequence(
      context: context,
      guides: guides,
      shouldShow: () => mounted && _currentIndex == 1,
    );
  }
}
