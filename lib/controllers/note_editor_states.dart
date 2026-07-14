import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/location_service.dart';

/// Owns the editor document and its draft-related lifecycle.
class NoteEditorState extends ChangeNotifier {
  NoteEditorState({
    required this.initialPlainText,
    required this.initialDeltaContent,
    required this.draftStorageKey,
    required bool restoredFromDraft,
  })  : _restoredFromDraft = restoredFromDraft,
        _controller = quill.QuillController.basic();

  quill.QuillController _controller;
  final String initialPlainText;
  final String? initialDeltaContent;
  final String draftStorageKey;
  bool _restoredFromDraft;
  bool _draftLoaded = false;
  bool _isLoadingFullQuote = false;
  bool _richTextLoadFailed = false;
  Quote? _fullInitialQuote;
  Timer? _draftSaveTimer;
  VoidCallback? _draftChangeListener;
  bool _disposed = false;

  quill.QuillController get controller => _controller;
  set controller(quill.QuillController value) => replaceController(value);
  bool get restoredFromDraft => _restoredFromDraft;
  bool get draftLoaded => _draftLoaded;
  set draftLoaded(bool value) => setDraftLoaded(value);
  bool get isLoadingFullQuote => _isLoadingFullQuote;
  set isLoadingFullQuote(bool value) => setFullQuoteLoading(value);
  bool get richTextLoadFailed => _richTextLoadFailed;
  set richTextLoadFailed(bool value) => setRichTextLoadFailed(value);
  Quote? get fullInitialQuote => _fullInitialQuote;
  set fullInitialQuote(Quote? value) => setFullInitialQuote(value);

  void replaceController(quill.QuillController controller) {
    if (identical(_controller, controller)) return;
    final draftChangeListener = _draftChangeListener;
    if (draftChangeListener != null) {
      _controller.removeListener(draftChangeListener);
    }
    _controller.dispose();
    _controller = controller;
    if (draftChangeListener != null) {
      _controller.addListener(draftChangeListener);
    }
    notifyListeners();
  }

  void setDraftChangeListener(VoidCallback listener) {
    final previous = _draftChangeListener;
    if (previous != null) _controller.removeListener(previous);
    _draftChangeListener = listener;
    _controller.addListener(listener);
  }

  void setDraftLoaded(bool value) {
    _draftLoaded = value;
  }

  void scheduleDraftSave(Duration delay, Future<void> Function() save) {
    _draftSaveTimer?.cancel();
    if (!_draftLoaded || _disposed) return;
    _draftSaveTimer = Timer(delay, save);
  }

  void cancelDraftSave() {
    _draftSaveTimer?.cancel();
  }

  void setFullQuoteLoading(bool value) {
    if (_isLoadingFullQuote == value) return;
    _isLoadingFullQuote = value;
    notifyListeners();
  }

  void setFullInitialQuote(Quote? quote) {
    _fullInitialQuote = quote;
  }

  void setRichTextLoadFailed(bool value) {
    if (_richTextLoadFailed == value) return;
    _richTextLoadFailed = value;
    notifyListeners();
  }

  void markDraftSaved() {
    _restoredFromDraft = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _draftSaveTimer?.cancel();
    final draftChangeListener = _draftChangeListener;
    if (draftChangeListener != null) {
      _controller.removeListener(draftChangeListener);
    }
    _controller.dispose();
    super.dispose();
  }
}

/// Owns source, tag, color, location, weather and AI-analysis state.
class NoteEditorMetadataState extends ChangeNotifier {
  NoteEditorMetadataState({
    Quote? initialQuote,
    String? initialAuthor,
    String? initialWork,
    Iterable<String>? initialTagIds,
  })  : authorController = TextEditingController(
          text: initialQuote?.sourceAuthor ?? initialAuthor ?? '',
        ),
        workController = TextEditingController(
          text: initialQuote?.sourceWork ?? initialWork ?? '',
        ),
        _selectedTagIds = List<String>.from(
          initialQuote?.tagIds ?? initialTagIds ?? const [],
        ),
        _selectedColorHex = initialQuote?.colorHex,
        _location = initialQuote?.location,
        _latitude = initialQuote?.latitude,
        _longitude = initialQuote?.longitude,
        _poiName = initialQuote?.poiName,
        _weather = initialQuote?.weather,
        _temperature = initialQuote?.temperature,
        _currentAiAnalysis = initialQuote?.aiAnalysis,
        _originalLocation = LocationService.isNonDisplayMarker(
          initialQuote?.location,
        )
            ? null
            : initialQuote?.location,
        _originalLatitude = initialQuote?.latitude,
        _originalLongitude = initialQuote?.longitude,
        _originalWeather = initialQuote?.weather,
        _showLocation = initialQuote?.location != null ||
            (initialQuote?.latitude != null && initialQuote?.longitude != null),
        _showWeather = initialQuote?.weather != null,
        _initialSnapshot = _MetadataSnapshot.fromQuote(
          initialQuote,
          author: initialQuote?.sourceAuthor ?? initialAuthor ?? '',
          work: initialQuote?.sourceWork ?? initialWork ?? '',
          tagIds: initialQuote?.tagIds ?? initialTagIds ?? const [],
        );

  final TextEditingController authorController;
  final TextEditingController workController;
  final TextEditingController tagSearchController = TextEditingController();
  _MetadataSnapshot _initialSnapshot;

  List<String> _selectedTagIds;
  String? _selectedColorHex;
  String? _location;
  double? _latitude;
  double? _longitude;
  String? _poiName;
  String? _weather;
  String? _temperature;
  bool _showLocation;
  bool _showWeather;
  String? _originalLocation;
  double? _originalLatitude;
  double? _originalLongitude;
  final String? _originalWeather;
  String? _currentAiAnalysis;
  String _tagSearchQuery = '';

  String get author => authorController.text;
  String get work => workController.text;
  UnmodifiableListView<String> get selectedTagIds =>
      UnmodifiableListView(_selectedTagIds);
  String? get selectedColorHex => _selectedColorHex;
  set selectedColorHex(String? value) => setSelectedColorHex(value);
  String? get location => _location;
  set location(String? value) => setLocation(value);
  double? get latitude => _latitude;
  set latitude(double? value) => setLatitude(value);
  double? get longitude => _longitude;
  set longitude(double? value) => setLongitude(value);
  String? get poiName => _poiName;
  set poiName(String? value) => setPoiName(value);
  String? get weather => _weather;
  set weather(String? value) => setWeather(value);
  String? get temperature => _temperature;
  set temperature(String? value) => setTemperature(value);
  bool get showLocation => _showLocation;
  set showLocation(bool value) => setShowLocation(value);
  bool get showWeather => _showWeather;
  set showWeather(bool value) => setShowWeather(value);
  String? get originalLocation => _originalLocation;
  set originalLocation(String? value) => updateOriginalLocation(
        location: value,
        latitude: _originalLatitude,
        longitude: _originalLongitude,
      );
  double? get originalLatitude => _originalLatitude;
  set originalLatitude(double? value) => updateOriginalLocation(
        location: _originalLocation,
        latitude: value,
        longitude: _originalLongitude,
      );
  double? get originalLongitude => _originalLongitude;
  set originalLongitude(double? value) => updateOriginalLocation(
        location: _originalLocation,
        latitude: _originalLatitude,
        longitude: value,
      );
  String? get originalWeather => _originalWeather;
  String? get currentAiAnalysis => _currentAiAnalysis;
  set currentAiAnalysis(String? value) => setAiAnalysis(value);
  String get tagSearchQuery => _tagSearchQuery;
  set tagSearchQuery(String value) => setTagSearchQuery(value);

  void setAuthor(String value) {
    if (authorController.text == value) return;
    authorController.text = value;
    notifyListeners();
  }

  void setWork(String value) {
    if (workController.text == value) return;
    workController.text = value;
    notifyListeners();
  }

  void setSelectedTagIds(Iterable<String> value) {
    final next = List<String>.from(value);
    if (listEquals(_selectedTagIds, next)) return;
    _selectedTagIds = next;
    notifyListeners();
  }

  void toggleTag(String tagId, {required bool selected}) {
    final next = List<String>.from(_selectedTagIds);
    if (selected) {
      if (!next.contains(tagId)) next.add(tagId);
    } else {
      next.removeWhere((id) => id == tagId);
    }
    setSelectedTagIds(next);
  }

  void removeTag(String tagId) => toggleTag(tagId, selected: false);

  void setSelectedColorHex(String? value) {
    if (_selectedColorHex == value) return;
    _selectedColorHex = value;
    notifyListeners();
  }

  void updateLocation({
    required String? location,
    required double? latitude,
    required double? longitude,
    String? poiName,
    bool? show,
  }) {
    if (_location == location &&
        _latitude == latitude &&
        _longitude == longitude &&
        _poiName == poiName &&
        (show == null || _showLocation == show)) {
      return;
    }
    _location = location;
    _latitude = latitude;
    _longitude = longitude;
    _poiName = poiName;
    if (show != null) _showLocation = show;
    notifyListeners();
  }

  void updateWeather({
    required String? weather,
    required String? temperature,
    bool? show,
  }) {
    if (_weather == weather &&
        _temperature == temperature &&
        (show == null || _showWeather == show)) {
      return;
    }
    _weather = weather;
    _temperature = temperature;
    if (show != null) _showWeather = show;
    notifyListeners();
  }

  void setShowLocation(bool value) {
    if (_showLocation == value) return;
    _showLocation = value;
    notifyListeners();
  }

  void setShowWeather(bool value) {
    if (_showWeather == value) return;
    _showWeather = value;
    notifyListeners();
  }

  void setAiAnalysis(String? value) {
    if (_currentAiAnalysis == value) return;
    _currentAiAnalysis = value;
    notifyListeners();
  }

  void hydrateAiAnalysisIfUnchanged(String? value) {
    if (_currentAiAnalysis != _initialSnapshot.aiAnalysis) return;
    _currentAiAnalysis = value;
    _initialSnapshot = _initialSnapshot.copyWith(aiAnalysis: value);
    notifyListeners();
  }

  void setLocation(String? value) => updateLocation(
        location: value,
        latitude: _latitude,
        longitude: _longitude,
        poiName: _poiName,
      );

  void setLatitude(double? value) => updateLocation(
        location: _location,
        latitude: value,
        longitude: _longitude,
        poiName: _poiName,
      );

  void setLongitude(double? value) => updateLocation(
        location: _location,
        latitude: _latitude,
        longitude: value,
        poiName: _poiName,
      );

  void setPoiName(String? value) => updateLocation(
        location: _location,
        latitude: _latitude,
        longitude: _longitude,
        poiName: value,
      );

  void setWeather(String? value) => updateWeather(
        weather: value,
        temperature: _temperature,
      );

  void setTemperature(String? value) => updateWeather(
        weather: _weather,
        temperature: value,
      );

  void updateOriginalLocation({
    required String? location,
    required double? latitude,
    required double? longitude,
  }) {
    _originalLocation = location;
    _originalLatitude = latitude;
    _originalLongitude = longitude;
    notifyListeners();
  }

  void setTagSearchQuery(String value) {
    if (_tagSearchQuery == value) return;
    _tagSearchQuery = value;
    notifyListeners();
  }

  /// Establishes the clean baseline after page-level defaults are applied.
  void captureInitialSnapshot() {
    _initialSnapshot = _MetadataSnapshot(
      author: author,
      work: work,
      tagIds: Set<String>.from(_selectedTagIds),
      colorHex: _selectedColorHex,
      location: _location,
      latitude: _latitude,
      longitude: _longitude,
      poiName: _poiName,
      weather: _weather,
      temperature: _temperature,
      aiAnalysis: _currentAiAnalysis,
    );
  }

  bool hasChanges({required bool isExistingNote}) {
    final current = _MetadataSnapshot(
      author: author,
      work: work,
      tagIds: Set<String>.from(_selectedTagIds),
      colorHex: _selectedColorHex,
      location: _location,
      latitude: _latitude,
      longitude: _longitude,
      poiName: _poiName,
      weather: _weather,
      temperature: _temperature,
      aiAnalysis: _currentAiAnalysis,
    );
    return current.differsFrom(
      _initialSnapshot,
      compareLocationAndWeather: isExistingNote,
    );
  }

  @override
  void dispose() {
    authorController.dispose();
    workController.dispose();
    tagSearchController.dispose();
    super.dispose();
  }
}

/// Owns session media tracking and save-progress state.
class NoteEditorMediaState extends ChangeNotifier {
  final Set<String> _sessionImportedMedia = <String>{};
  bool _didSaveSuccessfully = false;
  bool _isSaving = false;
  double _saveProgress = 0;
  String? _saveStatus;

  Set<String> get unsavedImportedMedia => Set<String>.unmodifiable(
        _didSaveSuccessfully ? const <String>{} : _sessionImportedMedia,
      );
  Set<String> get sessionImportedMedia =>
      Set<String>.unmodifiable(_sessionImportedMedia);
  bool get didSaveSuccessfully => _didSaveSuccessfully;
  bool get isSaving => _isSaving;
  set isSaving(bool value) => setSaving(value);
  double get saveProgress => _saveProgress;
  set saveProgress(double value) => updateSaveProgress(value);
  String? get saveStatus => _saveStatus;
  set saveStatus(String? value) => setSaveStatus(value);

  void recordImportedMedia(String path) {
    if (_sessionImportedMedia.add(path)) notifyListeners();
  }

  void beginSave({String? status}) {
    _isSaving = true;
    _saveProgress = 0;
    _saveStatus = status;
    notifyListeners();
  }

  void setSaving(bool value) {
    if (_isSaving == value) return;
    _isSaving = value;
    notifyListeners();
  }

  void setSaveStatus(String? value) {
    if (_saveStatus == value) return;
    _saveStatus = value;
    notifyListeners();
  }

  void updateSaveProgress(double progress, {String? status}) {
    _saveProgress = progress.clamp(0, 1).toDouble();
    if (status != null) _saveStatus = status;
    notifyListeners();
  }

  void resetSaveAfterFailure() {
    _isSaving = false;
    _saveProgress = 0;
    notifyListeners();
  }

  void finishSave() {
    _isSaving = false;
    _saveProgress = 1;
    notifyListeners();
  }

  void markSavedSuccessfully() {
    _didSaveSuccessfully = true;
    _sessionImportedMedia.clear();
    notifyListeners();
  }
}

class _MetadataSnapshot {
  const _MetadataSnapshot({
    required this.author,
    required this.work,
    required this.tagIds,
    required this.colorHex,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.poiName,
    required this.weather,
    required this.temperature,
    required this.aiAnalysis,
  });

  factory _MetadataSnapshot.fromQuote(
    Quote? quote, {
    required String author,
    required String work,
    required Iterable<String> tagIds,
  }) {
    return _MetadataSnapshot(
      author: author,
      work: work,
      tagIds: Set<String>.from(tagIds),
      colorHex: quote?.colorHex,
      location: quote?.location,
      latitude: quote?.latitude,
      longitude: quote?.longitude,
      poiName: quote?.poiName,
      weather: quote?.weather,
      temperature: quote?.temperature,
      aiAnalysis: quote?.aiAnalysis,
    );
  }

  final String author;
  final String work;
  final Set<String> tagIds;
  final String? colorHex;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? poiName;
  final String? weather;
  final String? temperature;
  final String? aiAnalysis;

  _MetadataSnapshot copyWith({String? aiAnalysis}) {
    return _MetadataSnapshot(
      author: author,
      work: work,
      tagIds: tagIds,
      colorHex: colorHex,
      location: location,
      latitude: latitude,
      longitude: longitude,
      poiName: poiName,
      weather: weather,
      temperature: temperature,
      aiAnalysis: aiAnalysis,
    );
  }

  bool differsFrom(
    _MetadataSnapshot other, {
    required bool compareLocationAndWeather,
  }) {
    if (author != other.author ||
        work != other.work ||
        !setEquals(tagIds, other.tagIds) ||
        colorHex != other.colorHex ||
        aiAnalysis != other.aiAnalysis) {
      return true;
    }
    if (!compareLocationAndWeather) return false;
    return location != other.location ||
        latitude != other.latitude ||
        longitude != other.longitude ||
        poiName != other.poiName ||
        weather != other.weather ||
        temperature != other.temperature;
  }
}
