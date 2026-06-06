# Location and Weather Read-Only Protection in Edit Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure that when editing an already saved note, the location and weather information become read-only, preventing any addition, modification, or removal of these fields while displaying them as selected if they exist.

**Architecture:** 
1. We will update the `onSelected` callbacks for location and weather chips in both the quick add dialog and full editor metadata section.
2. In edit mode, when these chips are tapped, we will display a Toast/SnackBar message noting that location and weather of saved notes cannot be modified, and return early without changing the state.
3. The refresh location/weather button is already hidden in edit mode, so no further changes are needed there.

**Tech Stack:** Flutter / Dart / MMKV / Provider

---

### Task 1: Add Localizations

Add a localization key `editModeMetadataReadOnlyHint` to app_zh.arb and app_en.arb, then run `flutter gen-l10n`.

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`

**Step 1: Write the changes**

Add `"editModeMetadataReadOnlyHint": "已保存笔记的位置和天气不支持编辑修改",` after `cannotAddWeatherDesc` in `lib/l10n/app_zh.arb`:
```json
  "cannotAddWeatherDesc": "此笔记首次保存时未记录天气信息，无法补充添加。\n\n如需记录天气，请在新建笔记时勾选天气选项。",
  "editModeMetadataReadOnlyHint": "已保存笔记的位置和天气不支持编辑修改",
```

Add `"editModeMetadataReadOnlyHint": "Location and weather of saved notes cannot be modified",` after `cannotAddWeatherDesc` in `lib/l10n/app_en.arb`:
```json
  "cannotAddWeatherDesc": "This note did not record weather info on first save, cannot add later.\n\nTo record weather, check the weather option when creating a new note.",
  "editModeMetadataReadOnlyHint": "Location and weather of saved notes cannot be modified",
```

**Step 2: Generate localizations**

Run command: `flutter gen-l10n`
Expected output: Success code generation with zero exit code.

**Step 3: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb
git commit -m "intl: add read-only metadata hint localization"
```

---

### Task 2: Make Quick Add Dialog Location & Weather Chips Read-Only

Ensure that when editing a note in the Quick Add dialog, location/weather chips are non-modifiable and tapping them shows a SnackBar.

**Files:**
- Modify: `lib/widgets/add_note_dialog.dart`

**Step 1: Modify location chip in add_note_dialog.dart**

Around line 2199:
```dart
                                onSelected: (value) async {
                                  // 编辑模式下不允许修改位置与天气信息
                                  if (widget.initialQuote != null) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(AppLocalizations.of(context).editModeMetadataReadOnlyHint),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  // 新建模式：已有坐标/地址时弹对话框（查看/转换/移除）
                                  if (_includeLocation &&
                                      (_newLatitude != null ||
                                          _newLocation != null)) {
                                    await _showNewNoteLocationDialog(
                                        context, theme);
                                    return;
                                  }
                                  // 新建模式：首次勾选，获取位置
                                  if (value &&
                                      _newLocation == null &&
                                      _newLatitude == null) {
                                    _fetchLocationForNewNote();
                                  }
                                  setState(() {
                                    _includeLocation = value;
                                  });
                                },
```

**Step 2: Modify weather chip in add_note_dialog.dart**

Around line 2292:
```dart
                            onSelected: (value) async {
                              // 编辑模式下不允许修改位置与天气信息
                              if (widget.initialQuote != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(AppLocalizations.of(context).editModeMetadataReadOnlyHint),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                                return;
                              }
                              // 新建模式：已勾选天气时，点击弹出详情/移除对话框
                              if (_includeWeather) {
                                await _showNewNoteWeatherDialog(context, theme);
                                return;
                              }
                              // 新建模式：首次勾选
                              if (value) {
                                setState(() {
                                  _includeWeather = true;
                                });
                                // 勾选时获取天气
                                _fetchWeatherForNewNote();
                              } else {
                                setState(() {
                                  _includeWeather = false;
                                });
                              }
                            },
```

**Step 3: Verify build**

Run command: `flutter analyze --no-fatal-infos`
Expected output: No new static analysis issues.

**Step 4: Commit**

```bash
git add lib/widgets/add_note_dialog.dart
git commit -m "feat: make location and weather chips read-only in Quick Add Dialog edit mode"
```

---

### Task 3: Make Full Editor Metadata Section Location & Weather Chips Read-Only

Implement same read-only lock in the full-screen editor's metadata location section.

**Files:**
- Modify: `lib/pages/note_editor/editor_metadata_location_section.dart`

**Step 1: Modify location chip in editor_metadata_location_section.dart**

Around line 69:
```dart
                            onSelected: (value) async {
                              if (widget.initialQuote?.id != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.editModeMetadataReadOnlyHint),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                                return;
                              }
                              // 新建模式
                              if (value &&
                                  _location == null &&
                                  _latitude == null) {
                                // 先设置为选中，获取失败后会在回调中取消
                                _updateState(() {
                                  _showLocation = true;
                                });
                                setDialogState(() {});
                                await _fetchLocationForNewNoteWithFailCallback(
                                    () {
                                  // 失败回调：取消选中
                                  _updateState(() {
                                    _showLocation = false;
                                  });
                                  setDialogState(() {});
                                });
                              } else {
                                _updateState(() {
                                  _showLocation = value;
                                });
                                setDialogState(() {});
                              }
                            },
```

**Step 2: Modify weather chip in editor_metadata_location_section.dart**

Around line 144:
```dart
                        onSelected: (value) async {
                          if (widget.initialQuote?.id != null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.editModeMetadataReadOnlyHint),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                            return;
                          }
                          // 新建模式
                          if (value && _weather == null) {
                            // 先设置为选中，获取失败后会在回调中取消
                            _updateState(() {
                              _showWeather = true;
                            });
                            setDialogState(() {});
                            await _fetchLocationWeatherWithFailCallback(() {
                              // 失败回调：取消选中
                              _updateState(() {
                                _showWeather = false;
                              });
                              setDialogState(() {});
                            });
                          } else {
                            _updateState(() {
                              _showWeather = value;
                            });
                            setDialogState(() {});
                          }
                        },
```

**Step 3: Verify build**

Run command: `flutter analyze --no-fatal-infos`
Expected: Passes analyzer.

**Step 4: Commit**

```bash
git add lib/pages/note_editor/editor_metadata_location_section.dart
git commit -m "feat: make location and weather chips read-only in Full Editor metadata edit mode"
```

---

### Task 4: Write Widget Test for Verification

Add a widget test to verify that the Location and Weather chips show the read-only warning SnackBar in edit mode and do not modify any state.

**Files:**
- Create: `test/widget/add_note_dialog_metadata_readonly_test.dart`

**Step 1: Write the widget test**

Implement the widget test file:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';
import 'package:flutter_gen_l10n/app_localizations.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import '../../test_setup.dart'; // import base mock setups if any

class MockSettingsService extends Mock implements SettingsService {
  @override
  bool get autoAttachLocation => false;
  @override
  bool get autoAttachWeather => false;
}

class MockLocationService extends Mock implements LocationService {
  @override
  bool get hasPermission => true;
  @override
  bool get isLocationServiceEnabled => true;
}

class MockWeatherService extends Mock implements WeatherService {
  @override
  bool get hasData => true;
  @override
  String get currentWeather => 'Sunny';
}

void main() {
  testWidgets('AddNoteDialog shows SnackBar and retains check state in edit mode', (WidgetTester tester) async {
    final initialQuote = Quote(
      id: 'test-id-123',
      content: 'Test initial note content',
      date: DateTime.now(),
      location: Peking, China,
      latitude: 39.9,
      longitude: 116.4,
      weather: 'Sunny',
      temperature: '25°C',
    );

    final mockSettings = MockSettingsService();
    final mockLocation = MockLocationService();
    final mockWeather = MockWeatherService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SettingsService>.value(value: mockSettings),
          Provider<LocationService>.value(value: mockLocation),
          Provider<WeatherService>.value(value: mockWeather),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AddNoteDialog(
              initialQuote: initialQuote,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify chips are rendered and checked initially
    final locationChip = find.byKey(const ValueKey('add_note_location_chip'));
    final weatherChip = find.byKey(const ValueKey('add_note_weather_chip'));

    expect(locationChip, findsOneWidget);
    expect(weatherChip, findsOneWidget);

    final FilterChip locationWidget = tester.widget(locationChip);
    final FilterChip weatherWidget = tester.widget(weatherChip);

    expect(locationWidget.selected, isTrue);
    expect(weatherWidget.selected, isTrue);

    // Tap the location chip
    await tester.tap(locationChip);
    await tester.pump();

    // Verify SnackBar is shown with the read-only message
    expect(find.text('已保存笔记的位置和天气不支持编辑修改'), findsOneWidget);

    // Verify state remains selected
    final FilterChip locationWidgetAfterTap = tester.widget(locationChip);
    expect(locationWidgetAfterTap.selected, isTrue);
  });
}
```

**Step 2: Run test**

Run: `timeout 60s flutter test --reporter compact test/widget/add_note_dialog_metadata_readonly_test.dart`
Expected: PASS

**Step 3: Commit**

```bash
git add test/widget/add_note_dialog_metadata_readonly_test.dart
git commit -m "test: add widget test for metadata read-only verification"
```
