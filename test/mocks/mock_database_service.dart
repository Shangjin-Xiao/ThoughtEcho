import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import '../../lib/services/database_service.dart';
import '../../lib/models/quote_model.dart';
import '../../lib/models/note_category.dart';

// Mock class generation annotation
@GenerateMocks([DatabaseService])
class MockDatabaseService extends Mock implements DatabaseService {
  // Test data
  static final List<Quote> _testQuotes = [
    Quote(
      id: '1',
      content: 'Test quote 1',
      date: '2024-01-01T10:00:00.000Z',
      categoryId: 'test-category-1',
      location: 'Test Location',
      weather: 'Sunny',
      temperature: '25°C',
    ),
    Quote(
      id: '2',
      content: 'Test quote 2',
      date: '2024-01-02T15:30:00.000Z',
      categoryId: 'test-category-2',
      source: 'Test Source',
      sourceAuthor: 'Test Author',
    ),
  ];

  static final List<NoteCategory> _testCategories = [
    NoteCategory(
      id: 'test-category-1',
      name: 'Test Category 1',
      isDefault: false,
      iconName: 'bookmark',
    ),
    NoteCategory(
      id: 'test-category-2',
      name: 'Test Category 2',
      isDefault: false,
      iconName: 'note',
    ),
    NoteCategory(
      id: DatabaseService.defaultCategoryIdHitokoto,
      name: '一言',
      isDefault: true,
      iconName: 'hitokoto',
    ),
  ];

  // Override common methods with test implementations
  @override
  Future<void> initialize() async {
    // Mock initialization - do nothing
  }

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    String orderBy = 'date DESC',
    int? limit,
  }) async {
    var quotes = List<Quote>.from(_testQuotes);
    
    // Apply category filter
    if (categoryId != null) {
      quotes = quotes.where((q) => q.categoryId == categoryId).toList();
    }
    
    // Apply tag filter
    if (tagIds != null && tagIds.isNotEmpty) {
      quotes = quotes.where((q) => 
        tagIds.any((tagId) => q.tagIds.contains(tagId))
      ).toList();
    }
    
    // Apply limit
    if (limit != null && limit < quotes.length) {
      quotes = quotes.take(limit).toList();
    }
    
    return quotes;
  }

  @override
  Future<void> addQuote(Quote quote) async {
    // Mock adding quote - just add to test data
    _testQuotes.add(quote);
    notifyListeners();
  }

  @override
  Future<void> updateQuote(Quote quote) async {
    // Mock updating quote
    final index = _testQuotes.indexWhere((q) => q.id == quote.id);
    if (index != -1) {
      _testQuotes[index] = quote;
      notifyListeners();
    }
  }

  @override
  Future<void> deleteQuote(String id) async {
    // Mock deleting quote
    _testQuotes.removeWhere((q) => q.id == id);
    notifyListeners();
  }

  @override
  Future<Quote?> getQuoteById(String id) async {
    try {
      return _testQuotes.firstWhere((q) => q.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<NoteCategory>> getCategories() async {
    return List<NoteCategory>.from(_testCategories);
  }

  @override
  Future<void> addCategory(NoteCategory category) async {
    _testCategories.add(category);
    notifyListeners();
  }

  @override
  Future<void> updateCategory(NoteCategory category) async {
    final index = _testCategories.indexWhere((c) => c.id == category.id);
    if (index != -1) {
      _testCategories[index] = category;
      notifyListeners();
    }
  }

  @override
  Future<void> deleteCategory(String id) async {
    _testCategories.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  @override
  Future<NoteCategory?> getCategoryById(String id) async {
    try {
      return _testCategories.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<int> getQuoteCount({String? categoryId, List<String>? tagIds}) async {
    var quotes = _testQuotes;
    
    if (categoryId != null) {
      quotes = quotes.where((q) => q.categoryId == categoryId).toList();
    }
    
    if (tagIds != null && tagIds.isNotEmpty) {
      quotes = quotes.where((q) => 
        tagIds.any((tagId) => q.tagIds.contains(tagId))
      ).toList();
    }
    
    return quotes.length;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    return {
      'quotes': _testQuotes.map((q) => q.toJson()).toList(),
      'categories': _testCategories.map((c) => c.toJson()).toList(),
      'exportTime': DateTime.now().toIso8601String(),
      'version': '1.0.0',
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data, {bool override = false}) async {
    if (override) {
      _testQuotes.clear();
      _testCategories.clear();
    }
    
    if (data['quotes'] != null) {
      for (var quoteJson in data['quotes']) {
        _testQuotes.add(Quote.fromJson(quoteJson));
      }
    }
    
    if (data['categories'] != null) {
      for (var categoryJson in data['categories']) {
        _testCategories.add(NoteCategory.fromJson(categoryJson));
      }
    }
    
    notifyListeners();
  }

  // Test helper methods
  static void resetTestData() {
    _testQuotes.clear();
    _testCategories.clear();
    
    // Re-add default test data
    _testQuotes.addAll([
      Quote(
        id: '1',
        content: 'Test quote 1',
        date: '2024-01-01T10:00:00.000Z',
        categoryId: 'test-category-1',
      ),
      Quote(
        id: '2',
        content: 'Test quote 2',
        date: '2024-01-02T15:30:00.000Z',
        categoryId: 'test-category-2',
      ),
    ]);
    
    _testCategories.addAll([
      NoteCategory(
        id: 'test-category-1',
        name: 'Test Category 1',
        isDefault: false,
        iconName: 'bookmark',
      ),
      NoteCategory(
        id: 'test-category-2',
        name: 'Test Category 2',
        isDefault: false,
        iconName: 'note',
      ),
    ]);
  }

  static List<Quote> get testQuotes => List<Quote>.from(_testQuotes);
  static List<NoteCategory> get testCategories => List<NoteCategory>.from(_testCategories);
}