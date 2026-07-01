import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/app_logger.dart';

class NoteSearchController extends ChangeNotifier {
  String _searchQuery = '';
  Timer? _debounceTimer; // 保留字段用于 dispose 清理（updateSearch 不再使用）
  Timer? _timeoutTimer;
  bool _isSearching = false;
  String? _searchError;
  int _searchVersion = 0; // 搜索版本号，超时保护用

  String get searchQuery => _searchQuery;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  /// 更新搜索。防抖由调用方（NoteListView）负责，此处立即更新状态，
  /// 避免双重 300ms 延迟导致列表长时间停留在变淡动画状态。
  void updateSearch(String query) {
    // 取消可能残留的旧定时器（updateSearchImmediate 等路径可能设置过）
    _debounceTimer?.cancel();
    _timeoutTimer?.cancel();

    // 如果搜索内容没变，不执行任何操作
    if (_searchQuery == query) return;

    // 如果是空查询，立即清除搜索状态
    if (query.isEmpty) {
      _searchQuery = '';
      _isSearching = false;
      _searchError = null;
      _searchVersion++;
      notifyListeners();
      logDebug('搜索控制器: 清空搜索内容', source: 'SearchController');
      return;
    }

    // 查询长度 < 2 时，只同步文本但不触发实际搜索
    if (query.length < 2) {
      _searchQuery = query;
      _isSearching = false;
      _searchError = null;
      notifyListeners();
      return;
    }

    // 立即更新查询并通知监听者（防抖已由 NoteListView 完成）
    _isSearching = true;
    _searchError = null;
    _searchVersion++;
    final currentVersion = _searchVersion;
    _searchQuery = query;
    notifyListeners();
    logDebug('搜索查询已更新: $query', source: 'SearchController');

    // 保留超时保护，防止数据库查询无限挂起
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_isSearching &&
          _searchQuery == query &&
          currentVersion == _searchVersion) {
        _isSearching = false;
        _searchError = '搜索超时，请重试';
        notifyListeners();
        logDebug('搜索超时，已自动重置状态，查询: $query', source: 'SearchController');
      }
    });
  }

  /// 立即更新搜索，不使用防抖
  void updateSearchImmediate(String query) {
    if (_searchQuery != query) {
      // 取消可能存在的定时器
      _debounceTimer?.cancel();
      _searchQuery = query;
      _isSearching = false;
      _searchError = null;
      notifyListeners();
    }
  }

  void clearSearch() {
    // 取消可能存在的定时器
    _debounceTimer?.cancel();
    if (_searchQuery.isNotEmpty || _isSearching || _searchError != null) {
      _searchQuery = '';
      _isSearching = false;
      _searchError = null;
      notifyListeners();
    }
  }

  /// 设置搜索状态
  void setSearchState(bool isSearching) {
    if (_isSearching != isSearching) {
      _isSearching = isSearching;
      if (!isSearching) {
        // 搜索完成时取消超时定时器
        _timeoutTimer?.cancel();
      }
      notifyListeners();
    }
  }

  /// 重置搜索状态（用于解决卡住的搜索状态）
  void resetSearchState() {
    _debounceTimer?.cancel();
    _timeoutTimer?.cancel();
    _isSearching = false;
    _searchError = null;
    _searchVersion++; // 增加版本号，使正在进行的搜索失效
    notifyListeners();
    logDebug('搜索状态已手动重置', source: 'SearchController');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }
}
