1. **Add `Semantics` wrapper to checkbox row in `ExperimentalBadge` dialog (lib/widgets/ai/experimental_badge.dart).**
   - The checkbox row in the `showExperimentalNoticeDialog` currently uses an `InkWell` to make the row clickable for toggling the "Don't show again" checkbox, but it lacks a `Semantics` wrapper to expose it properly to screen readers as a toggleable checkbox with its label.
   - I will wrap the `InkWell` (or its child) in a `Semantics` widget, providing `value`, `onTap`, and possibly setting it as a `button`/`checkbox`.

2. **Add `Semantics` wrapper to slash command list items (lib/widgets/ai/slash_commands_menu.dart).**
   - The `_SlashCommandTile` uses an `InkWell` to make the list items clickable, but they don't have explicit `Semantics` to indicate to screen readers that they are actionable buttons.
   - I will add a `Semantics(button: true)` wrapper around the `InkWell`.

3. **Complete Pre-commit Steps.**
   - Run the checks indicated by `pre_commit_instructions` tool to verify the code correctly and format it.

4. **Submit PR.**
   - Commit and submit using standard branch and commit messages in Chinese.
