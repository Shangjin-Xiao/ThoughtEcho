---
name: fabric-improve-writing
description: "Polish and tighten text by removing AI filler (stop-slop), enhancing clarity, rhythm, and punchiness. Adapted from Fabric (improve_writing). Use when editing documentation, user guides, changelogs, articles, or UI descriptions."
---

# Fabric Improve Writing & Stop-Slop

Adapted from Daniel Miesslers Fabric framework (28k+ stars), this skill refines written text to maximize clarity, brevity, and natural human tone while ruthlessly purging AI clichés.

## When to Use
- Polishing user documentation (`docs/USER_MANUAL.md` or `res/user-guide.html`).
- Refining release notes, changelogs, or articles.
- Eliminating robotic or bloated expressions from user-facing copy.

## The "Stop-Slop" Blacklist (Purge on Sight)

Purge these AI writing habits:
- ❌ "In todays fast-paced world..." / "在当今快节奏的时代..."
- ❌ "It is worth noting that..." / "值得注意的是..."
- ❌ "Delve into...", "Unlock the power of...", "Beacon of...", "Tapestry of..."
- ❌ "不仅...而且...", "作为一款集...于一体的...", "为您带来前所未有的体验"
- ❌ Overusing redundant adjectives and adverbs ("extremely", "uniquely", "seamlessly").

## 5 Improvement Steps

1. **Cut the Bloat**: Remove opening filler sentences. Start with the core thought.
2. **Active Voice**: Convert passive constructions to active subjects and verbs.
3. **Vary Sentence Length**: Mix short, punchy sentences with balanced longer ones for natural rhythm.
4. **Concrete Examples**: Replace abstract generalities with concrete, visual specifics.
5. **Human Warmth**: Preserve genuine, thoughtful tone (especially for ThoughtEcho).
