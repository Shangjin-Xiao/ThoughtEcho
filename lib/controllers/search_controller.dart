import 'package:flutter/material.dart';

class NoteSearchController extends ChangeNotifier {
  String _searchQuery = '';
  
  String get searchQuery => _searchQuery;
  
  void updateSearch(String query) {
    if (_searchQuery != query) {
      _searchQuery = query;
      notifyListeners();
    }
  }
  
  void clearSearch() {
    if (_searchQuery.isNotEmpty) {
      _searchQuery = '';
      notifyListeners();
    }
  }
}