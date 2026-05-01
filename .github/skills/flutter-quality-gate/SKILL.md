---
name: flutter-quality-gate
description: "Execute quality gate for Flutter changes. Use when asked to validate a change, finish a task, run checks, or before merge. Runs flutter pub get, flutter analyze, flutter test, and optional flutter build checks with concise failure triage."
argument-hint: "Optional scope, for example: dashboard, mqtt, settings, or changed files"
---

# Flutter Quality Gate

Run a consistent validation workflow before marking work as done.

## When To Use
- User asks to validate, review readiness, or finalize a change.
- You changed Dart or Flutter files and need confidence before handoff.
- You suspect regressions in Riverpod, MQTT flow, local database, or UI pages.

## Inputs
- Optional focus area from the user, such as dashboard, history, settings, mqtt, providers, or tests.
- If no focus is provided, validate the full project baseline.

## Procedure
1. Confirm context
- Work from repository root.
- Do not edit generated output folders like build unless explicitly requested.

2. Refresh dependencies
- Run:
```bash
flutter pub get
```

3. Static analysis
- Run:
```bash
flutter analyze
```
- If warnings or errors appear, fix issues related to the requested task first.
- Do not refactor unrelated areas unless necessary to unblock validation.

4. Execute tests
- Run:
```bash
flutter test
```
- If failing tests are unrelated and pre-existing, report them clearly as baseline issues.

5. Optional build smoke checks
- Run only when requested or when changes affect platform/build behavior.
```bash
flutter build apk
```
- For desktop or iOS specific work, run the relevant build target only.

6. Summarize outcome
- Report pass/fail per step.
- Include impacted files and concise root cause for failures.
- Provide next action options when checks fail.

## Failure Triage Rules
- Prioritize compile and analyzer errors over style warnings.
- Prefer minimal fixes with the smallest blast radius.
- Re-run only the failed step after each fix, then run the full gate once all failures are resolved.
- Stop after three unsuccessful fix attempts on the same issue and ask the user how to proceed.

## Repository Notes
- Project uses Riverpod, MQTT ingestion, and sqflite persistence.
- Existing test suite may include template tests that do not reflect current UI behavior.
- Keep user-facing text in pt-BR unless the user asks otherwise.
