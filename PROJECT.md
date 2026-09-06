# Project: ThoughtEcho Thoughter AI Evaluation and Optimization

## Architecture
- **AI Core Agent (`AgentService`)**: Native tool execution loop with stream reasoning distribution, context pruning, history compression, untrusted input wrapping, and proposal artifact generation.
- **Agent Tools Suite (`lib/services/agent_tools/`)**: 11 dedicated tools (`explore_notes`, `get_note_detail`, `get_tags`, `get_location_weather`, `session_search`, `recall`, `web_search`, `web_fetch`, `propose_note_create`, `propose_note_edit`, `remember`).
- **Memory Subsystem (`AgentMemoryService`)**: Physically isolated `agent_memory.db` with facts and profile tables, in-place supersede updates, anti-injection `<user_profile>` wrapping, and strict boundary isolation (never storing raw note content).
- **Proposal & Safe Execution (`NoteProposalApplier`)**: Non-destructive draft card generation with `document_revision` optimistic lock checking and delta/plain text consistency validation.
- **Headless Live Probe Harness (`test/live/`)**: Headless runner executing against live LLMs (`gemma4:31b`, `muse-spark-1.2-contributor-free`, `gemini-3.6-flash`/`3.7-flash`), logging structured transcripts to `build/agent-probe/` and enforcing programmatic invariants.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | F1: Synthetic Realistic Benchmark Dataset | Generate 100% synthetic, zero-privacy dataset with unauthored originals, author-signed originals, famous excerpts (Sherry Turkle, Seneca, etc.), and multi-tag scenarios | M1 | R1 / Survey |
| 2 | F2: Live Probe Harness & Test Automation | Headless test harness in `test/live/` supporting multi-model execution, automated invariant assertions (`_flagAttribution`, `_flagNoteContentLeakedIntoMemory`, `ProposalCheck`) | M1 | R2 / Survey |
| 3 | F3: Core Note Ops & Tool Calling Evaluation | Evaluate note creation, rich text modification, search, and multi-turn interaction accuracy with `gemma4:31b` | M2 | R2 / Survey |
| 4 | F4: Long-Term Memory & Boundary Evaluation | Verify `AgentMemoryService` cross-session recall, preference updates (supersede), and boundary compliance (zero note leakage into `agent_memory.db`) | M2 | R3 / Survey |
| 5 | F5: Original vs Excerpt Discrimination Evaluation | Verify model's ability to distinguish third-party excerpts from personal reflections/unauthored originals and author-signed user originals | M2 | R3 / Survey |
| 6 | F6: Multi-Model Cross-Comparison & Bad Case Attribution | Cross-compare `gemma4:31b`, `muse-spark-1.2-contributor-free`, and `gemini-3.6-flash`/`gemini-3.7-flash` to isolate prompt/code bugs vs model limits | M2 | R4 / Survey |
| 7 | F7: Target Code & Prompt/Tool Optimization | Optimize system prompts, tool schemas, and error messages in `lib/services/agent_tools/` and `lib/pages/thoughter/` | M3 | R5 / Survey |
| 8 | F8: Regression Verification & E2E Validation | Re-run live probe suites and unit/integration tests to guarantee all bad cases resolved and no regressions introduced | M4 | R5 / Survey |
| 9 | F9: Accessible Evaluation & Optimization Report | Deliver clear, non-technical evaluation and optimization report comparing before and after performance | M5 | R6 / Survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Synthetic Benchmark Dataset & Probe Harness Setup | Formulate synthetic test suite fixtures, seed databases, and probe test runner configurations | none | IN_PROGRESS |
| M2 | Multi-Model Live Evaluation & Bad Case Attribution | Execute live probe evaluation on `gemma4:31b`, cross-evaluate with Muse/Gemini, catalog and attribute Bad Cases | M1 | PLANNED |
| M3 | Prompt & Agent Tool Definitions Optimization | Refine system prompts, tool descriptions, error messages, and memory instructions in `lib/services/agent_tools/` and `lib/services/agent_service.dart` | M2 | PLANNED |
| M4 | Regression Verification & Adversarial Gating | Re-run full test suites and probes across all models, verify zero regressions, pass adversarial checks | M3 | PLANNED |
| M5 | Evaluation & Optimization Reporting | Synthesize results, metrics, and before/after comparisons into comprehensive, accessible final report | M4 | PLANNED |

## Interface Contracts
### `AgentProbe` ↔ `AgentService`
- Configuration: `AgentProbeConfig` passing endpoint, apiKey, model name, and timeout.
- State: In-memory SQLite (`DatabaseService`), isolated `AgentMemoryService`, mocked secure storage.
- Probe Execution: `probe.runScenario(prompt, bindingNoteId, expectTools)` returning `ProbeTranscript`.

### `AgentService` ↔ `AgentTools`
- Tool Schema: `AgentTool.name`, `AgentTool.description`, `AgentTool.parameters`.
- Invocations: `AgentTool.execute(arguments)` -> `Future<String>` (wrapped in `TruncatingAgentTool`).
- Error Signaling: Standardized exception strings guiding the LLM to inspect parameters or re-read state.

### `AgentMemoryService` ↔ `AgentService`
- Profile Injection: `renderProfileBlock()` -> `<user_profile>` tags in user data message.
- Recall/Remember: Key-value facts and profile facts with unique integer IDs, strict exclusion of raw note bodies.

## Code Layout
- `lib/services/agent_service.dart`: Main agent prompt construction, loop execution, and error handling.
- `lib/services/agent_tools/`: Tool definitions (`explore_notes_tool.dart`, `remember_tool.dart`, `recall_tool.dart`, `propose_note_create_tool.dart`, `propose_note_edit_tool.dart`, etc.).
- `lib/services/agent_memory_service.dart`: Memory database operations, search, profile management, and supersede logic.
- `lib/models/quote_model.dart`: Attribution kind calculation (`excerpt` vs `original`).
- `test/live/`: Live probe test suites (`agent_probe.dart`, `agent_memory_live_test.dart`, `agent_high_frequency_live_test.dart`, `agent_self_correction_live_test.dart`, `agent_richtext_live_test.dart`).
- `test/unit/services/`: Unit test suites for agent loop, memory, and tools.
