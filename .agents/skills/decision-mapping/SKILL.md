---
name: decision-mapping
description: Turn a loose idea into a sequenced map of investigation tickets, then drive them to resolution one at a time.
disable-model-invocation: true
---

This skill is invoked when a loose idea requires more than one agent session to turn into a plan. It creates a stateful decision map in a markdown file, and drives the user through a sequence of tickets to resolve the open questions - which may require either prototyping, research or grilling.

## The Decision Map

The decision map is a single compact Markdown file, one per planning effort, git-tracked alongside the project. It is the canonical artifact — the **whole map is loaded as context into every session**, so it must stay compact.

Assets created during tickets should be linked to from the map, not duplicated within it.

### Structure

Entries ("tickets"), each its own section keyed by a short dash-case slug that
reads as a mini-title (e.g. `relational-db`, `auth-strategy`, `cache-layer`) —
terse enough to stay token-efficient, and unique within the map.

```markdown
## relational-db: Relational Or Non-Relational Database?

Blocked by: <slug>, <slug>
Status: open | in-progress | resolved
Type: Research | Prototype | Grilling

### Question

<question-here>

### Answer

<answer-here>
```

The slug is the canonical id, used in every `Blocked by` edge and prose
reference; the title after the colon is optional. A ticket
is **unblocked** when every ticket in its `Blocked by` list is `resolved`. A
session **claims** its ticket by setting `Status: in-progress` and saving the map
before any work, so concurrent sessions skip it.

Each ticket must be sized to one 100K token agent session.

## Ticket Types

There are three types of tickets:

- **Research**: Reading documentation, third-party API's, or local resources like knowledge bases. Creates a markdown summary as an asset. Use this when knowledge outside the current working directory is required.
- **Prototype**: Writing UI or logic code to test a hypothesis, or to explore a design space. Uses the /prototype skill. Creates a prototype as an asset. Use this when "how should it look" or "how should it behave" is the key question.
- **Grilling**: Conversation with the agent. Uses the /grilling and /domain-modeling skills. Asks one question at a time. The default case.

## Fog of war

The map is _deliberately_ incomplete beyond the frontier. Your job is to investigate the frontier, and to resolve tickets in order to push the frontier forward. Push back the fog of war, one node at a time — until the path to the finish line is clear and no tickets remain.

## Invocation

Two branches. Either way, **every session ends with a [Handoff](#handoff)** — never resolve more than one ticket per session.

### Create the map

User invokes with a loose idea.

1. Run a `/grilling` and `/domain-modeling` session to surface the open decisions. Ask one question at a time.
2. Write a new decision map — mostly fog, frontier identified, trivially-decidable entries resolved inline.
3. Handoff. Map-building is one session's work; do not also resolve tickets.

### Work through the map

User invokes with a path to an existing map. A ticket slug is **optional** — without one, you pick the next decision, not the user.

1. Load the **whole map** as context.
2. Choose the ticket. If the user named one, use it. Otherwise pick the first `open` ticket in document order that is [unblocked](#structure). [Claim it](#structure): set `Status: in-progress` and save before any work.
3. Resolve it, invoking skills as needed. If in doubt, use `/grilling` and `/domain-modeling`.
4. Record the answer in the ticket's body and set `Status: resolved`.
5. Add newly-discovered tickets with correct `Blocked by` edges. If the decisions made invalidate other parts of the map, update or delete those nodes.
6. Handoff.

The user may run unblocked tickets in parallel, so expect other agents to be editing the map in their own sessions.

## Handoff

End every session by clearing the context and opening one or more fresh sessions. Close with a **Next steps** block the user can copy-paste. Two cases:

**Open tickets remain.** List the currently-unblocked tickets, then give two copy-paste options: a bare command for one session (you pick the next ticket), and one pinned command per unblocked ticket for running them in parallel. Paste one line per fresh window — opening one, some, or all of them.

> **Next steps** — 3 tickets unblocked: `auth-strategy`, `cache-layer`, `rate-limits`.
> Clear the context, then open fresh sessions.
>
> **One session** — resolves the next unblocked ticket:
> ```
> Invoke /decision-mapping with the map at <path>.
> ```
>
> **Parallel** — paste one line per window, up to all 3:
> ```
> Invoke /decision-mapping with the map at <path>, ticket auth-strategy.
> Invoke /decision-mapping with the map at <path>, ticket cache-layer.
> Invoke /decision-mapping with the map at <path>, ticket rate-limits.
> ```

**No open tickets remain.** The fog is pushed back far enough that the path to the finish line is clear — the map is done. (The initial grilling may also surface no fog at all, in which case there was never a map to build.) Recommend implementing directly, or using `/to-prd` to schedule a multi-session implementation.
