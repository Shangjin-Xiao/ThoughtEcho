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

        // 添加最大搜索时间限制，5秒后自动重置搜索状态
        Future.delayed(const Duration(seconds: 5), () {
          if (_isSearching) {
            _isSearching = false;
            notifyListeners();
          }
        });

        notifyListeners();
      } catch (e) {
        _searchError = '搜索处理出错: $e';
        _isSearching = false;
        notifyListeners();
        logDebug('搜索控制器错误: $_searchError');
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

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
