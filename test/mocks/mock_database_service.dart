/// Mock DatabaseService for testing
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/note_category.dart';
import '../test_utils/test_data.dart';

class MockDatabaseService extends ChangeNotifier {
  final List<Quote> _quotes = [];
  final List<NoteCategory> _categories = [];
  final StreamController<List<Quote>> _quotesController = StreamController<List<Quote>>.broadcast();
  final StreamController<List<NoteCategory>> _categoriesController = StreamController<List<NoteCategory>>.broadcast();

  bool _isInitialized = false;
  String? _lastError;

  // Getters
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  List<Quote> get quotes => List.from(_quotes);
  List<NoteCategory> get categories => List.from(_categories);
  Stream<List<Quote>> get quotesStream => _quotesController.stream;
  Stream<List<NoteCategory>> get categoriesStream => _categoriesController.stream;

  /// Initialize mock database
  Future<void> initialize() async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate initialization delay
    _isInitialized = true;
    
    // Add default categories
    _categories.addAll(TestData.createTestCategoryList());
    _categoriesController.add(_categories);
    
    notifyListeners();
  }

  /// Add a quote
  Future<Quote> addQuote(Quote quote) async {
    await Future.delayed(const Duration(milliseconds: 50)); // Simulate database operation
    
    final quoteWithId = quote.copyWith(
      id: quote.id ?? 'mock-${_quotes.length + 1}',
    );
    
    _quotes.add(quoteWithId);
    _quotesController.add(_quotes);
    notifyListeners();
    
    return quoteWithId;
  }

  /// Update a quote
  Future<void> updateQuote(Quote quote) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final index = _quotes.indexWhere((q) => q.id == quote.id);
    if (index != -1) {
      _quotes[index] = quote;
      _quotesController.add(_quotes);
      notifyListeners();
    } else {
      throw Exception('Quote not found: ${quote.id}');
    }
  }

  /// Delete a quote
  Future<void> deleteQuote(String quoteId) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final removed = _quotes.removeWhere((q) => q.id == quoteId);
    if (removed > 0) {
      _quotesController.add(_quotes);
      notifyListeners();
    } else {
      throw Exception('Quote not found: $quoteId');
    }
  }

  /// Get quote by ID
  Future<Quote?> getQuoteById(String id) async {
    await Future.delayed(const Duration(milliseconds: 30));
    
    try {
      return _quotes.firstWhere((q) => q.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get all user quotes
  Future<List<Quote>> getUserQuotes({
    int? limit,
    int? offset,
    String? orderBy,
    String? categoryId,
    List<String>? tagIds,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    var filteredQuotes = List<Quote>.from(_quotes);
    
    // Apply category filter
    if (categoryId != null) {
      filteredQuotes = filteredQuotes.where((q) => q.categoryId == categoryId).toList();
    }
    
    // Apply tag filter
    if (tagIds != null && tagIds.isNotEmpty) {
      filteredQuotes = filteredQuotes.where((q) {
        return tagIds.any((tagId) => q.tagIds.contains(tagId));
      }).toList();
    }
    
    // Apply sorting
    if (orderBy != null) {
      if (orderBy.contains('date')) {
        filteredQuotes.sort((a, b) {
          final dateA = DateTime.parse(a.date);
          final dateB = DateTime.parse(b.date);
          return orderBy.contains('DESC') ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
        });
      }
    }
    
    // Apply pagination
    if (offset != null) {
      filteredQuotes = filteredQuotes.skip(offset).toList();
    }
    if (limit != null) {
      filteredQuotes = filteredQuotes.take(limit).toList();
    }
    
    return filteredQuotes;
  }

  /// Search quotes
  Future<List<Quote>> searchQuotes(String query) async {
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (query.trim().isEmpty) return _quotes;
    
    return _quotes.where((quote) {
      return quote.content.toLowerCase().contains(query.toLowerCase()) ||
             (quote.summary?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
             (quote.source?.toLowerCase().contains(query.toLowerCase()) ?? false);
    }).toList();
  }

  /// Add category
  Future<NoteCategory> addCategory(NoteCategory category) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final categoryWithId = category.copyWith(
      id: category.id ?? 'mock-cat-${_categories.length + 1}',
    );
    
    _categories.add(categoryWithId);
    _categoriesController.add(_categories);
    notifyListeners();
    
    return categoryWithId;
  }

  /// Update category
  Future<void> updateCategory(NoteCategory category) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final index = _categories.indexWhere((c) => c.id == category.id);
    if (index != -1) {
      _categories[index] = category;
      _categoriesController.add(_categories);
      notifyListeners();
    } else {
      throw Exception('Category not found: ${category.id}');
    }
  }

  /// Delete category
  Future<void> deleteCategory(String categoryId) async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    final removed = _categories.removeWhere((c) => c.id == categoryId);
    if (removed > 0) {
      _categoriesController.add(_categories);
      notifyListeners();
    } else {
      throw Exception('Category not found: $categoryId');
    }
  }

  /// Get all categories
  Future<List<NoteCategory>> getAllCategories() async {
    await Future.delayed(const Duration(milliseconds: 30));
    return List.from(_categories);
  }

  /// Export data
  Future<Map<String, dynamic>> exportData() async {
    await Future.delayed(const Duration(milliseconds: 200));
    
    return {
      'app_info': {
        'name': 'ThoughtEcho',
        'version': '1.0.0',
        'export_time': DateTime.now().toIso8601String(),
      },
      'quotes': _quotes.map((q) => q.toJson()).toList(),
      'categories': _categories.map((c) => c.toJson()).toList(),
    };
  }

  /// Import data
  Future<void> importData(Map<String, dynamic> data, {bool overwrite = false}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (overwrite) {
      _quotes.clear();
      _categories.clear();
    }
    
    // Import quotes
    if (data['quotes'] != null) {
      final quotesData = data['quotes'] as List;
      for (final quoteJson in quotesData) {
        final quote = Quote.fromJson(quoteJson);
        if (!_quotes.any((q) => q.id == quote.id)) {
          _quotes.add(quote);
        }
      }
    }
    
    // Import categories
    if (data['categories'] != null) {
      final categoriesData = data['categories'] as List;
      for (final categoryJson in categoriesData) {
        final category = NoteCategory.fromJson(categoryJson);
        if (!_categories.any((c) => c.id == category.id)) {
          _categories.add(category);
        }
      }
    }
    
    _quotesController.add(_quotes);
    _categoriesController.add(_categories);
    notifyListeners();
  }

  /// Simulate database error
  void simulateError(String error) {
    _lastError = error;
    notifyListeners();
  }

  /// Clear all data
  Future<void> clearAllData() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _quotes.clear();
    _categories.clear();
    _quotesController.add(_quotes);
    _categoriesController.add(_categories);
    notifyListeners();
  }

  /// Add test data
  void addTestData() {
    _quotes.addAll(TestData.createTestQuoteList(5));
    _categories.addAll(TestData.createTestCategoryList());
    _quotesController.add(_quotes);
    _categoriesController.add(_categories);
    notifyListeners();
  }

  @override
  void dispose() {
    _quotesController.close();
    _categoriesController.close();
    super.dispose();
  }
}