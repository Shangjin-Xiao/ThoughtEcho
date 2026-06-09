# NoteListView Performance Firebase Handoff - 2026-06-09

## Current Main Commits

- `6d1cd897 perf(note-list): window plain item keepalive`
  - Replaced full-list keepAlive with permanent keepAlive for rich/media/expandable notes plus a viewport-relative plain-item window.
  - Purpose: avoid `built=98@0-97` parent rebuild spikes while preserving nearby extent stability.
- `d0b321e4 test(firebase): compare note list visual effects`
  - Added Firebase performance summary printing in GitHub Actions.
  - Added test-only visual-effect override for QuoteItemWidget.
- `88e56ae1 test(firebase): rebuild flat visual note list scenarios`
  - Fixed invalid A/B setup so flat visual scenarios rebuild a fresh NoteListView after enabling the override.
- `45959d15 test(firebase): split note list visual effect diagnostics`
  - Added test-only split switches for card shadows and BackdropFilter blur.
  - Added Firebase scenarios for all-off, no-shadow, and no-backdrop comparisons.

## Valid Firebase Runs

### Run `27201960001` on `6d1cd897`

Result: success.

Evidence:

- The keepAlive change reduced build cost in multiple diagnostic scenarios compared with previous successful run `27196077326`.
- Some raster numbers moved in opposite directions between scenarios, so raster must be treated as noisy on Firebase virtual devices.
- `real_note_list_*_diagnostic` still showed large `RenderSliverList`/GPU slices.

### Run `27203244536` on `d0b321e4`

Result: success, but the initial flat-visual A/B was invalid.

Why invalid:

- `real_note_list_*_flatVisual_diagnostic` reported `itemBuild=0` / `itemLayout=0`.
- That means the static visual override was enabled after the existing widget tree had already been built, so it did not rebuild a fresh visual variant.

Do not use this run as proof that visual effects are or are not the root cause.

### Run `27204250378` on `88e56ae1`

Result: success and valid for all-off visual comparison.

Key A/B:

| Scenario Pair | build99 | raster99 | RenderSliverList | itemBuild | sizeChanged |
| --- | ---: | ---: | ---: | ---: | ---: |
| richText normal | 71.9ms | 190.8ms | 62.6ms | 14 | 8 |
| richText all visual effects off | 36.1ms | 1.8ms | 31.2ms | 12 | 6 |
| images normal | 58.7ms | 206.9ms | 51.7ms | 14 | 7 |
| images all visual effects off | 23.0ms | 10.1ms | 18.8ms | 6 | 3 |

Interpretation:

- The card visual layer is a major contributor to both build/layout and raster jank in Firebase.
- This does not yet identify whether the dominant cost is the card BoxShadow, the collapsed-content BackdropFilter, or their interaction.
- Production UI was not changed by this test-only override.

## Failed Firebase Run

### Run `27205278495` on `45959d15`

Result: failed before execution.

Reason from GitHub Actions log:

```text
TEST_QUOTA_EXCEEDED
Insufficient testing quota.
```

The split diagnostics are committed and ready to run once Firebase Test Lab quota resets.

## Current Best Hypotheses

1. The old full-list keepAlive caused rebuild spikes after scrolling because a parent rebuild swept all loaded items.
   - This has been addressed by `6d1cd897`.
2. Remaining jank is strongly correlated with the QuoteItem visual layer.
   - All-off visual A/B improved `build99`, `RenderSliverList`, and `raster99` substantially.
3. More evidence is needed before shipping a visual change:
   - Split Firebase scenarios should identify shadow-only vs backdrop-only contribution.
   - Until quota resets, do not claim shadow or blur alone is the root cause.

## Next Decision Point

If the user accepts a visual tradeoff before split Firebase data is available, the safest production experiment is likely NoteListView-only lighter card shadows:

- It affects every card, including plain text, matching the high raster seen even in plain-text scenarios.
- It avoids touching content blur semantics.
- It is visually noticeable, so it needs user approval.

The subtler alternative is replacing the collapsed-content BackdropFilter with the existing gradient scrim only:

- It is a smaller visual change.
- It only affects expandable collapsed notes, so it cannot explain plain-text raster by itself.

Recommended next Firebase run after quota reset:

```bash
gh workflow run "Firebase note-list performance test" --ref main
```

Then compare:

- `real_note_list_richText_diagnostic`
- `real_note_list_richText_noShadow_diagnostic`
- `real_note_list_richText_noBackdrop_diagnostic`
- `real_note_list_richText_flatVisual_diagnostic`
- `real_note_list_images_cold_diagnostic`
- `real_note_list_images_noShadow_diagnostic`
- `real_note_list_images_noBackdrop_diagnostic`
- `real_note_list_images_flatVisual_diagnostic`
