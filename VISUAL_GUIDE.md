# Input Area Redesign - Visual Guide

## Overall Layout

```
┌────────────────────────────────────────────────────────────┐
│ AIAssistantPage                                            │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ╔════════════════════════════════════════════════════╗   │
│  ║  Messages Area (ListView)                         ║   │
│  ║  - User bubbles (right, blue)                     ║   │
│  ║  - AI bubbles (left, light gray)                 ║   │
│  ║  - Thinking panels (collapsed/expanded)          ║   │
│  ║  - Tool call indicators                          ║   │
│  ╚════════════════════════════════════════════════════╝   │
│                                                            │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Input Area Container (rounded border)              │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ [+]  [Agent]  [Thinking]           [Send]          │  │
│  │ Media Mode     Toggle              Button          │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ [=== Selected Media Files ===]                     │  │
│  │ [image.jpg 250KB ✕] [doc.pdf 1.2MB ✕]            │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ [    Type message... (multiline)    ]              │  │
│  └────────────────────────────────────────────────────┘  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Button Row Components

### Detailed Button Layout

```
┌──────────────────────────────────────────────────────────────┐
│ LEFT GROUP (Flexible, minSize)        │  SEND (Fixed)        │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────┐ 6px ┌──────┐ 6px ┌──────────┐        ┌──────┐      │
│  │  +   │     │ Agent│     │ Thinking │  8px   │ Send │      │
│  └──────┘     └──────┘     └──────────┘  gap   └──────┘      │
│   Media        Mode         Thinking            Send         │
│   Button      Toggle        Toggle              Button       │
│                                                              │
│ (Wraps if needed)           (Hidden if not supported)        │
└──────────────────────────────────────────────────────────────┘
```

## Button State Diagram

### Media Button States

```
┌──────────────┐
│ Idle         │
├──────────────┤
│  Icon: +     │
│  Color: Primary (0.1 alpha bg)
│  Cursor: pointer
│  OnTap: Open FilePicker
└──────────┬───┘
           │
           ↓
┌──────────────┐
│ Loading      │
├──────────────┤
│  Icon: +     │
│  Color: Gray (disabled)
│  Cursor: not-allowed
│  OnTap: null (disabled)
└──────────────┘
```

### Mode Toggle States

```
Single Mode Available:
┌─────────────────────────┐
│ Label Pill Display      │
├─────────────────────────┤
│  ┌─╖                    │
│  │ │ Icon + Text Label  │
│  │ │ "Agent" or "Chat"  │
│  └─╜ No action on tap   │
└─────────────────────────┘

Multiple Modes Available:
┌──────────────────────────┐
│ Toggle Button            │
├──────────────────────────┤
│  Idle: Agent Mode        │
│  Icon: smart_toy (filled)
│  Color: Primary (0.1 alpha)
│  OnTap: Switch to Chat   │
│                          │
│  ↓ (after tap)           │
│                          │
│  Active: Chat Mode       │
│  Icon: chat (filled)     │
│  Color: Primary (0.1 alpha)
│  OnTap: Switch to Agent  │
└──────────────────────────┘
```

### Thinking Toggle States

```
Model Does NOT Support Thinking:
┌────────────────┐
│ Hidden         │
│ (SizedBox.zero)
└────────────────┘

Model Supports Thinking:

Off State:
┌─────────────────┐
│  Icon: Thinking (outlined)
│  Color: Gray
│  BG: surfaceContainerHigh (0.5 alpha)
│  OnTap: Enable thinking
└─────────────────┘

On State:
┌─────────────────┐
│  Icon: Thinking (filled)
│  Color: Secondary
│  BG: Secondary (0.1 alpha)
│  OnTap: Disable thinking
└─────────────────┘
```

### Send Button States

```
Idle State:
┌────────────────────┐
│ Icon: Send (arrow) │
│ Color: OnPrimary   │
│ BG: Primary        │
│ OnTap: Send msg    │
│ Animation: none    │
└────────────────────┘
     │
     │ (message sent → generation starts)
     ↓
┌────────────────────┐
│ Transition:        │
│ Icon rotates 360°  │
│ Duration: 200ms    │
│ Curve: default     │
└────────────────────┘
     │
     ↓
Loading State:
┌────────────────────┐
│ Icon: Stop (⊗)     │
│ Color: OnError     │
│ BG: Error          │
│ OnTap: Stop gen.   │
│ Animation: none    │
└────────────────────┘
     │
     │ (generation complete)
     ↓
     Back to Idle
```

## Spacing Diagram

```
Button Spacing:
┌────────┬──┬────────┬──┬──────────┬────────┬────────┐
│ Media  │6px│ Mode   │6px│ Thinking │  8px   │ Send   │
│ [+]    │  │ [Agent] │  │ [Think]  │  gap   │ [Send] │
└────────┴──┴────────┴──┴──────────┴────────┴────────┘
```
