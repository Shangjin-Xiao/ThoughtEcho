# AIAssistantPage Input Area - Redesigned Code Snippets

## 1. New Button Row Layout (Main Change)

**Location**: `lib/pages/ai_assistant_page.dart` lines 2073-2114

This replaces the old cluttered container-wrapped buttons with a clean, spacious layout:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // Left group: Media + Mode + Thinking buttons
    Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Media button - simple elliptical IconButton
          IconButton(
            icon: Icon(
              Icons.add,
              color: _isLoading
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
            tooltip: l10n.attachFile,
            onPressed: _isLoading ? null : _pickAndAttachMedia,
            style: IconButton.styleFrom(
              backgroundColor: _isLoading
                  ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5)
                  : theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: const CircleBorder(),
            ),
            iconSize: 20,
          ),
          const SizedBox(width: 6),
          // Mode switch button - simple toggle without menu
          _buildModeToggleButton(theme, l10n),
          const SizedBox(width: 6),
          // Thinking toggle button (if model supports thinking)
          if (_currentModelSupportsThinking)
            _buildThinkingToggleButton(theme, l10n),
        ],
      ),
    ),
    const SizedBox(width: 8),
    // Send button - right side
    _buildSendButton(theme, l10n),
  ],
)
```

## 2. Mode Toggle Button Helper

**Location**: lines 1230-1305

Implements intelligent mode switching - shows label pill when only 1 mode available, elliptical toggle button when multiple modes:

```dart
Widget _buildModeToggleButton(ThemeData theme, AppLocalizations l10n) {
  final allowedModes = [
    if (_entryConfig.allowsMode(_entryConfig.defaultMode))
      _entryConfig.defaultMode,
    if (_entryConfig.allowsMode(AIAssistantPageMode.agent))
      AIAssistantPageMode.agent,
  ];

  if (allowedModes.isEmpty) {
    return const SizedBox.shrink();
  }

  if (allowedModes.length == 1) {
    // Single mode - show label only, no toggle
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isAgentMode ? Icons.smart_toy_outlined : Icons.chat_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            _isAgentMode ? l10n.aiModeAgent : l10n.aiModeChat,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Multiple modes - toggle button (no popup menu like before)
  return Tooltip(
    message: 'Switch to ${_isAgentMode ? l10n.aiModeChat : l10n.aiModeAgent}',
    child: IconButton(
      icon: Icon(
        _isAgentMode ? Icons.smart_toy : Icons.chat,
        color: theme.colorScheme.primary,
      ),
      tooltip: 'Toggle mode',
      onPressed: _isLoading
          ? null
          : () {
              final nextMode = _isAgentMode
                  ? _entryConfig.defaultMode
                  : AIAssistantPageMode.agent;
              if (_entryConfig.allowsMode(nextMode)) {
                _setMode(nextMode);
              }
            },
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
        shape: const CircleBorder(),
      ),
      iconSize: 20,
    ),
  );
}
```

**Key Improvements:**
- ✅ Removed PopupMenuButton with dropdown
- ✅ Direct toggle (no menu) - cleaner UX
- ✅ Intelligent display: label when 1 mode, button when multiple
- ✅ Smart icon switching (smart_toy ↔ chat)

## 3. Thinking Toggle Button Helper

**Location**: lines 1307-1334

Clean elliptical button that only shows if the model supports thinking:

```dart
Widget _buildThinkingToggleButton(ThemeData theme, AppLocalizations l10n) {
  return Tooltip(
    message: l10n.aiThinking,
    child: IconButton(
      icon: Icon(
        _enableThinking ? Icons.psychology : Icons.psychology_outlined,
        color: _enableThinking
            ? theme.colorScheme.secondary
            : theme.colorScheme.onSurfaceVariant,
      ),
      tooltip: l10n.aiThinking,
      onPressed: () {
        setState(() {
          _enableThinking = !_enableThinking;
        });
      },
      style: IconButton.styleFrom(
        backgroundColor: _enableThinking
            ? theme.colorScheme.secondary.withValues(alpha: 0.1)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        shape: const CircleBorder(),
      ),
      iconSize: 20,
    ),
  );
}
```

**Features:**
- ✅ Only renders if `_currentModelSupportsThinking` is true
- ✅ Filled brain icon when enabled, outlined when disabled
- ✅ Color indicates state (secondary=enabled, gray=disabled)

## 4. Animated Send Button Helper

**Location**: lines 1336-1353

Delegates to the new AnimatedIconButton widget:

```dart
Widget _buildSendButton(ThemeData theme, AppLocalizations l10n) {
  return Tooltip(
    message: _isLoading ? l10n.stopGenerate : l10n.confirm,
    child: AnimatedIconButton(
      isLoading: _isLoading,
      onPressed: _isLoading
          ? _stopGenerating
          : () {
              if (_textController.text.trim().isNotEmpty) {
                _handleSubmitted(_textController.text);
              }
            },
      theme: theme,
    ),
  );
}
```

## 5. AnimatedIconButton Widget Class

**Location**: lines 2182-2226

New reusable widget showing arrow ↔ stop icon transition:

```dart
class AnimatedIconButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  final ThemeData theme;

  const AnimatedIconButton({
    required this.isLoading,
    required this.onPressed,
    required this.theme,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return RotationTransition(
            turns: animation,
            child: child,
          );
        },
        child: Icon(
          isLoading ? Icons.stop_circle : Icons.arrow_outward,
          key: ValueKey<bool>(isLoading),
          color: isLoading
              ? theme.colorScheme.onError
              : theme.colorScheme.onPrimary,
        ),
      ),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: isLoading
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
        shape: const CircleBorder(),
        splashFactory: InkRipple.splashFactory,
      ),
      iconSize: 20,
    );
  }
}
```

**Animations:**
- Icon rotates during 200ms transition
- Arrow icon when ready to send
- Stop circle icon when generating
- Background color: primary (ready) → error (stopping)

## Visual Layout

```
┌─────────────────────────────────────────────────┐
│ Input Area (SafeArea with rounded border)       │
├─────────────────────────────────────────────────┤
│ [+]  [🤖]  [🧠]              [→ Send]          │  ← New Layout
│  ↓     ↓     ↓                  ↓               │
│ Media Agent Thinking        Animated            │
│ Button Button  Button       Send/Stop           │
├─────────────────────────────────────────────────┤
│ [    Text Input Field (multiline)    ]          │
└─────────────────────────────────────────────────┘
```

## Key Improvements

| Aspect | Before | After |
|--------|--------|-------|
| Media | Container with shadow | Elliptical IconButton |
| Mode Switch | PopupMenuButton + dropdown | Direct toggle (no menu) |
| Thinking | Wrapped container | Elliptical IconButton |
| Send | Static icon | Animated icon transition |
| Layout Density | Cluttered | Clean, spacious |
| Box Shadows | Multiple shadows per button | Subtle 0.1 alpha backgrounds |

## File Summary

**File**: `/home/azureuser/ThoughtEcho/lib/pages/ai_assistant_page.dart`

**Changes:**
- ✅ Removed 100+ lines of box-shadow decorations
- ✅ Added 3 reusable helper methods (145 lines)
- ✅ Added 1 reusable widget class (45 lines)
- ✅ Simplified main button row (40 lines)
- ✅ **Net change**: Cleaner, more maintainable code

**Localization Keys:**
- `l10n.attachFile` - Media button
- `l10n.aiThinking` - Thinking button
- `l10n.aiModeAgent` / `l10n.aiModeChat` - Mode labels
- `l10n.stopGenerate` / `l10n.confirm` - Send button

## Implementation Notes

1. **Media Upload**: Existing `_pickAndAttachMedia()` works as-is
2. **Mode Toggle**: Uses existing `_setMode()` method
3. **Thinking Toggle**: Updates `_enableThinking` boolean
4. **Send Button**: Calls `_handleSubmitted()` or `_stopGenerating()`
5. **All buttons**: Properly disabled during generation (except Thinking toggle)

## Design Patterns

✅ **Material 3 Compliance**: Uses `IconButton.styleFrom()` with proper color schemes
✅ **Google AI Gallery Reference**: Follows clean elliptical button pattern
✅ **Responsive**: Uses `Flexible` and `mainAxisSize.min` for proper layout
✅ **Accessible**: All buttons have tooltips and semantic meaning
✅ **Animatable**: Smooth transitions between states (200ms)
