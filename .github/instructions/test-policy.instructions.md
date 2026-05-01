---
description: "Use when adding or modifying Flutter behavior, fixing bugs, refactoring providers/services, or preparing a merge. Defines test and validation policy for this repository."
name: "Flutter Test Policy"
applyTo: ["lib/**/*.dart", "test/**/*.dart"]
---
# Test Policy

## Goal
Keep behavior changes verifiable with minimal regression risk.

## Rules
- For behavior changes in lib, add or update at least one relevant test when feasible.
- Prefer focused widget or unit tests near the changed feature instead of broad snapshot-style tests.
- Keep test names descriptive and aligned with user-visible behavior.
- If pre-existing tests are failing and unrelated, do not silently fix unrelated scope; report baseline failures clearly.

## Validation Sequence
1. Run flutter analyze.
2. Run flutter test.
3. If platform-specific behavior changed, run one relevant build smoke check.

## Repository-Specific Notes
- Existing default template test may not represent current app behavior; update tests to match real flows.
- MQTT and persistence logic should be validated via provider/service-oriented tests where possible.
- Preserve pt-BR text expectations in assertions involving UI labels/messages.
