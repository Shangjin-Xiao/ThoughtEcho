# Note List Visible Quill Prefix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep Flutter Quill as the renderer for collapsed notes while preventing content below the 160px preview viewport from entering the editor layout tree.

**Architecture:** Add a width-aware collapsed-document prefix compiler behind `QuoteContent`. It retains Delta attributes and embeds, includes the first block that crosses the preview boundary as a safety guard, and caches the resulting document variant by content, width, text scale, locale, and preview settings. Expanded notes continue to receive the complete Delta document.

**Tech Stack:** Flutter, Dart, Flutter Quill 11.5.x, `flutter_test`.

---

### Task 1: Lock down the visible-prefix behavior

**Files:**
- Modify: `test/quote_content_widget_test.dart`

1. Add a widget test with long styled text followed by several image embeds.
2. Assert the collapsed Quill document keeps the content intersecting the 160px preview but excludes later invisible embeds.
3. Assert the expanded editor still receives every embed and the complete text.
4. Run the focused test and confirm it fails because the current 640px heuristic retains invisible embeds.

### Task 2: Implement the width-aware prefix compiler

**Files:**
- Modify: `lib/widgets/quote_content_widget.dart`
- Modify: `test/quote_content_widget_test.dart`

1. Move collapsed rich-text document resolution under the available-width layout seam.
2. Measure styled text conservatively at the actual preview width and text scale.
3. Preserve Delta attributes and Unicode grapheme boundaries while cutting only invisible suffix text.
4. Keep the first embed/block intersecting the preview and omit later blocks.
5. Include width and text environment in cache variants so rotation and accessibility scaling cannot reuse stale prefixes.
6. Run the focused test until green, then run the full `quote_content_widget_test.dart` file.

### Task 3: Preserve rendering and integration behavior

**Files:**
- Modify: `test/widgets/quote_item_widget_test.dart` only if an existing seam needs coverage.

1. Verify collapsed content still uses `QuillEditor` and `_CollapsedContentWrapper`.
2. Verify full/expanded content is not truncated.
3. Verify image embeds that intersect the preview still use the existing optimized image builder.
4. Run the relevant quote item tests.

### Task 4: Record and verify

**Files:**
- Modify: `.squad/decisions.md`
- Create: `.squad/note_list_visible_quill_prefix_handoff_2026-07-12.md`

1. Record the July 12 device evidence and why image decode deferral did not address Quill layout.
2. Record the selected same-renderer visible-prefix design, validation commands, and remaining device-measurement gate.
3. Format changed Dart files.
4. Run focused Flutter tests and targeted static analysis.
5. Inspect `git diff`, stage only explicit files, commit, merge into `main`, and push `main`.
