---
description: "Refactor Flutter code to the repository Riverpod pattern. Use when moving logic out of widgets into providers/services or improving state orchestration without changing behavior."
name: "Refactor Riverpod Pattern"
argument-hint: "Provide target files or feature area, expected behavior, and constraints"
agent: "agent"
---
Refactor the selected Flutter code to follow this repository Riverpod pattern.

Objectives:
- Move business logic from widgets to providers/services.
- Preserve behavior and user-facing text.
- Keep changes minimal and aligned with existing folder boundaries in lib/src.

Execution requirements:
1. Map current responsibilities across ui, providers, services, and data.
2. Propose and apply a minimal refactor plan.
3. Keep side effects and integrations out of widget build methods when possible.
4. Update or add tests relevant to the changed behavior when feasible.
5. Run validation with flutter analyze and flutter test.

Output requirements:
- summarize moved logic and resulting boundaries
- list changed files
- include validation outcomes
- call out any residual risks
