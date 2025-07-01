import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/app_logger.dart';

class NoteSearchController extends ChangeNotifier {
  String _searchQuery = '';
  Timer? _debounceTimer;
  final int _debounceTime = 300; // 毫秒
  bool _isSearching = false;
  String? _searchError;

  String get searchQuery => _searchQuery;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  /// 更新搜索，带有防抖功能，避免频繁触发搜索操作
  void updateSearch(String query) {
    // 取消之前的延迟操作
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }

    // 如果搜索内容没变，不执行任何操作
    if (_searchQuery == query) return;

    // 如果是空查询，立即清除搜索状态
    if (query.isEmpty) {
      _searchQuery = '';
      _isSearching = false;
      _searchError = null;
      notifyListeners();
      logDebug('搜索控制器: 清空搜索内容', source: 'SearchController');
      return;
    }

    // 标记开始搜索状态
    _isSearching = true;
    _searchError = null;
    notifyListeners();

    // 使用定时器实现防抖
    _debounceTimer = Timer(Duration(milliseconds: _debounceTime), () {
      try {
        _searchQuery = query;

        // 添加较短的搜索时间限制，确保搜索状态不会永远卡住
        Future.delayed(const Duration(seconds: 10), () {
          if (_isSearching && _searchQuery == query) {
            _isSearching = false;
            _searchError = '搜索超时，请重试';
            notifyListeners();
            logDebug('搜索超时，已自动重置状态，查询: $query');
          }
        });

        notifyListeners();
        logDebug('搜索查询已更新: $query', source: 'SearchController');
      } catch (e) {
        _searchError = '搜索处理出错: $e';
        _isSearching = false;
        notifyListeners();
        logError('搜索控制器错误: $_searchError', error: e, source: 'SearchController');
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
    if (_searchQuery.isNotEmpty) {
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
      notifyListeners();
    }
  }

  /// 重置搜索状态（用于解决卡住的搜索状态）
  void resetSearchState() {
    _debounceTimer?.cancel();
    _isSearching = false;
    _searchError = null;
    notifyListeners();
    logDebug('搜索状态已手动重置');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
