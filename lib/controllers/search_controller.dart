import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/app_logger.dart';

class NoteSearchController extends ChangeNotifier {
  String _searchQuery = '';
  Timer? _debounceTimer;
  Timer? _timeoutTimer;
  final int _debounceTime = 500; // 优化：增加防抖时间到500ms，减少频繁查询
  bool _isSearching = false;
  String? _searchError;
  int _searchVersion = 0; // 优化：添加搜索版本号，避免过期结果覆盖新结果

  String get searchQuery => _searchQuery;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  /// 更新搜索，带有防抖功能，避免频繁触发搜索操作
  void updateSearch(String query) {
    // 取消之前的延迟操作和超时定时器
    _debounceTimer?.cancel();
    _timeoutTimer?.cancel();

    // 如果搜索内容没变，不执行任何操作
    if (_searchQuery == query) return;

    // 如果是空查询，立即清除搜索状态
    if (query.isEmpty) {
      _searchQuery = '';
      _isSearching = false;
      _searchError = null;
      _searchVersion++; // 增加版本号
      notifyListeners();
      logDebug('搜索控制器: 清空搜索内容', source: 'SearchController');
      return;
    }

    // 优化：只有在查询长度大于1时才开始搜索，避免单字符搜索
    if (query.length < 2) {
      _searchQuery = query;
      _isSearching = false;
      _searchError = null;
      notifyListeners();
      return;
    }

    // 标记开始搜索状态
    _isSearching = true;
    _searchError = null;
    _searchVersion++; // 增加版本号
    final currentVersion = _searchVersion;
    notifyListeners();

    // 使用定时器实现防抖
    _debounceTimer = Timer(Duration(milliseconds: _debounceTime), () {
      try {
        // 检查版本号，避免过期的搜索结果
        if (currentVersion != _searchVersion) {
          logDebug('搜索版本过期，忽略结果: $query', source: 'SearchController');
          return;
        }

        _searchQuery = query;

        // 优化：设置更合理的超时时间，与数据库查询超时保持一致
        _timeoutTimer = Timer(const Duration(seconds: 5), () {
          if (_isSearching && _searchQuery == query && currentVersion == _searchVersion) {
            _isSearching = false;
            _searchError = '搜索超时，请重试';
            notifyListeners();
            logDebug('搜索超时，已自动重置状态，查询: $query', source: 'SearchController');
          }
        });

        notifyListeners();
        logDebug('搜索查询已更新: $query', source: 'SearchController');
      } catch (e) {
        _searchError = '搜索处理出错: $e';
        _isSearching = false;
        notifyListeners();
        logError(
          '搜索控制器错误: $_searchError',
          error: e,
          source: 'SearchController',
        );
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
