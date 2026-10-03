# E2E Test Infra: ThoughtEcho Thoughter AI Evaluation & Optimization

## Test Philosophy
- Requirement-driven, opaque-box and live headless probe execution.
- Deterministic invariants (Delta format, schema validity, memory physical separation, zero note leakage into memory db).
- Multi-tier coverage: Tier 1 Feature Coverage, Tier 2 Boundary & Corner, Tier 3 Cross-Feature Combinations, Tier 4 Real-World Application Scenarios, Tier 5 Adversarial & Multi-Model Cross-Comparison.

## Feature Inventory
| # | Feature | Source (Requirement) | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---------|----------------------|:------:|:------:|:------:|:------:|
| 1 | F1: Synthetic Dataset & Note Attribution | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ | ✓ |
| 2 | F2: Live Headless Probe Runner | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ | ✓ |
| 3 | F3: Core Note Ops & Tool Calling | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ | ✓ |
| 4 | F4: Long-Term Memory Boundary & Recall | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ | ✓ |
| 5 | F5: Original vs Excerpt Discrimination | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ | ✓ |
| 6 | F6: Multi-Model Cross-Comparison | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |
| 7 | F7: Prompt & Tool Optimization | ORIGINAL_REQUEST §R5 | 5 | 5 | ✓ | ✓ |

## Test Architecture
- Test runner: `flutter test test/live/...` and `flutter test test/unit/services/...`
- Multi-model switches: `TE_PROBE_MODEL` (`gemma4:31b`, `muse-spark-1.2-contributor-free`, `gemini-3.6-flash`, `gemini-3.7-flash`)
- Verification Assertions:
  - `_flagAttribution`: detects if model hallucinates excerpts as personal statements or vice-versa.
  - `_flagNoteContentLeakedIntoMemory`: verifies zero raw note text enters `agent_memory.db`.
  - `ProposalCheck.validate`: verifies Delta format, schema validity, and optimistic lock adherence.
- Transcript output directory: `build/agent-probe/<scenario>-<model>.md`

## Coverage Thresholds
- Tier 1: ≥5 test cases per feature (Happy-path tool calls and memory recalls)
- Tier 2: ≥5 boundary test cases (Duplicate tag names, empty searches, conflicting revisions, unauthored quotes, self-signed diaries)
- Tier 3: Pairwise cross-feature interactions (Memory update during note edit, tag search + web search synthesis)
- Tier 4: Realistic multi-turn conversation workflows (Reading notes -> synthesizing insights -> saving draft card -> updating user profile preferences)
- Tier 5: Multi-model bad case isolation & adversarial stress testing
