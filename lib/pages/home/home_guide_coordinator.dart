import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/pages/settings_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/pages/home/guide_quota.dart';
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

  /// 被动引导的打扰配额，语义和取值见 [GuideQuota]。
  final GuideQuota _quota = GuideQuota();

  bool get _active => !_disposed && isMounted() && context.mounted;

  void triggerForCurrentPage() {
    final page = currentPage();
    _quota.onPageChanged(page);

    switch (page) {
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
    if (!_quota.isAvailable ||
        _homePending ||
        FeatureGuideHelper.hasShown(context, 'homepage_daily_quote')) {
      return;
    }
    _homePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_active || currentPage() != 0) {
        _homePending = false;
        return;
      }
      final shown = await FeatureGuideHelper.show(
        context: context,
        guideId: 'homepage_daily_quote',
        targetKey: dailyQuoteKey,
        shouldShow: () => _active && currentPage() == 0,
      );
      if (shown) _quota.consume();
      _homePending = false;
    });
  }

  void _scheduleNoteGuide({Duration delay = Duration.zero}) {
    if (!_quota.isAvailable || _notePending || _allNoteGuidesShown()) return;
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
    // 智能推送排在这一页自己的引导之后：它是「去别处看看」的发现提示，
    // 优先级低于用户此刻正看着的这个列表怎么用。
    if (await _shouldSuggestSmartPush()) {
      guides.add(('smart_push_entry', settingsTabKey));
    }
    // 上面那次判断要查数据库，回来时页面可能已经不在了。
    // `context.mounted` 要显式写出来，包在 `_active` 里分析器看不穿。
    if (!context.mounted || !_active || currentPage() != 1) return;
    if (guides.isEmpty) return;

    final shown = await FeatureGuideHelper.showFirstAvailable(
      context: context,
      guides: guides,
      shouldShow: () => _active && currentPage() == 1,
    );
    if (shown) _quota.consume();
  }

  /// 智能推送默认关闭，入口只有设置里的一个二级页，用户几乎发现不了。
  ///
  /// 但这个功能的内容是「把你写过的旧笔记推回来」，笔记太少时推不出东西，
  /// 提示了反而像空头承诺——所以要等攒够 [_smartPushNoteThreshold] 条再提，
  /// 而且已经自己开过的人不再提。
  static const int _smartPushNoteThreshold = 5;

  Future<bool> _shouldSuggestSmartPush() async {
    if (!_active) return false;
    if (FeatureGuideHelper.hasShown(context, 'smart_push_entry')) return false;

    try {
      final smartPush = Provider.of<SmartPushService>(context, listen: false);
      final settings = smartPush.settings;
      if (settings.enabled || settings.dailyQuotePushEnabled) return false;

      final database = Provider.of<DatabaseService>(context, listen: false);
      final count = await database.getQuotesCount();
      return count >= _smartPushNoteThreshold;
    } catch (e) {
      // 拿不到服务或数不出来时就不提示——引导不值得为此打断用户或抛错。
      debugPrint('判断智能推送引导条件失败: $e');
      return false;
    }
  }

  void _scheduleSettingsGuide() {
    if (!_quota.isAvailable || _settingsPending) return;
    final allShown =
        FeatureGuideHelper.hasShown(context, 'settings_preferences') &&
            FeatureGuideHelper.hasShown(context, 'settings_startup') &&
            FeatureGuideHelper.hasShown(context, 'settings_theme');
    if (allShown) return;

    _settingsPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_active || currentPage() != 3) {
        _settingsPending = false;
        return;
      }
      final shown = await settingsPageKey.currentState?.showGuidesIfNeeded(
        shouldShow: () => _active && currentPage() == 3,
      );
      if (shown ?? false) _quota.consume();
      _settingsPending = false;
    });
  }

  void dispose() {
    _disposed = true;
    _noteDelay?.cancel();
    _trashDelay?.cancel();
  }
}
