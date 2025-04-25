import 'package:flutter/material.dart';
import 'dart:async';

class NoteSearchController extends ChangeNotifier {
  String _searchQuery = '';
  Timer? _debounceTimer;
  final int _debounceTime = 300; // 毫秒
  
  String get searchQuery => _searchQuery;
  
  /// 更新搜索，带有防抖功能，避免频繁触发搜索操作
  void updateSearch(String query) {
    // 取消之前的延迟操作
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }
    
    // 如果搜索内容没变，不执行任何操作
    if (_searchQuery == query) return;
    
    // 使用定时器实现防抖
    _debounceTimer = Timer(Duration(milliseconds: _debounceTime), () {
      _searchQuery = query;
      notifyListeners();
    });
  }
  
  /// 立即更新搜索，不使用防抖
  void updateSearchImmediate(String query) {
    if (_searchQuery != query) {
      // 取消可能存在的定时器
      _debounceTimer?.cancel();
      _searchQuery = query;
      notifyListeners();
    }
  }
  
  void clearSearch() {
    // 取消可能存在的定时器
    _debounceTimer?.cancel();
    if (_searchQuery.isNotEmpty) {
      _searchQuery = '';
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}