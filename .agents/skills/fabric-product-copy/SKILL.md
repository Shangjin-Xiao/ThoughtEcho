---
name: fabric-product-copy
description: "Generate compelling product descriptions, feature-to-benefit value propositions, and landing page copy. Adapted from Daniel Miesslers Fabric framework (create_product_description & create_value_proposition). Use when writing feature intros, website copy, store descriptions, or marketing overviews."
---

# Fabric Product Copy & Value Proposition

Adapted from the open-source Fabric framework (28k+ stars), this skill transforms technical features into compelling, benefit-driven product copy.

## When to Use
- Drafting feature introductions for release notes or landing pages (`res/index.html`).
- Creating value proposition comparisons (e.g. ThoughtEcho vs traditional note apps).
- Writing product summaries for app stores, GitHub README, or product launch posts.

## Core Framework: Feature-to-Benefit Translation

Never describe a raw feature in isolation. Always map it to a user outcome:

| Technical Feature | Mechanism | User Outcome (Benefit) | Emotional Payoff |
| :--- | :--- | :--- | :--- |
| SQLite + MMKV local storage | No mandatory cloud account | 100% data ownership; zero tracking | Absolute peace of mind |
| WebDAV multi-device sync | End-to-end private server sync | Seamless notes across devices | Freedom without lock-in |
| Paper & Ink Theme | Custom typography + ruled lines | Physical stationery reading feel | Warm, intimate contemplation |
| On-device & Multi-AI | Switchable LLM providers | Tailored AI insights without lock-in | Thoughtful reflection partner |

## Output Structure

When generating product descriptions:
1. **One-Line Hook / Tagline**: Clear, memorable, zero buzzwords.
2. **The Problem & Friction**: What frustrates users with existing alternatives.
3. **The Solution (Value Pillars)**: 3-4 distinct pillars with bold benefit headers and concise explanations.
4. **Key Features Grid**: Bullet points pairing an active benefit with the enabling feature.
5. **Call to Action (CTA)**: Direct, low-friction next step.

## Negative Constraints (What to Avoid)
- No generic buzzwords: "revolutionary", "game-changing", "next-generation", "seamlessly empowers".
- No passive voice: Lead with action verbs ("Capture", "Organize", "Reflect", "Own").
- No wall of text: Keep paragraphs under 3 sentences with generous whitespace.
