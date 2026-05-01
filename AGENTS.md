# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Snapshot
- Flutter app for IoT electrical metrics visualization and history.
- State management: Riverpod (`flutter_riverpod`).
- Data ingest: MQTT (`mqtt_client`).
- Local persistence: SQLite via `sqflite`.
- Charts/export/alerts: `fl_chart`, `csv`, `pdf`, `printing`, `flutter_local_notifications`.

## Docs
- Start from [README.md](README.md). It is currently generic Flutter boilerplate.

## High-Value Commands
Run from repository root.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Common build targets:

```bash
flutter build apk
flutter build ios
flutter build windows
```

## Architecture Map
- Entry point: `lib/main.dart`.
- App shell and theme: `lib/src/app.dart`.
- Feature UI pages: `lib/src/ui/` (`dashboard`, `history`, `settings`).
- Domain/data layer: `lib/src/data/` (`metric_model`, `metric_repository`, `local_database`).
- Integration/services: `lib/src/services/` (`mqtt_service`, `alert_service`).
- State providers: `lib/src/providers/` (Riverpod providers for streams, persistence, alerts).

## Code Conventions In This Repo
- Prefer small, focused Riverpod providers in `lib/src/providers/`.
- Keep MQTT parsing/saving flow in providers/services, not inside widgets.
- Keep database access in repository/data layer (`MetricRepository`, `LocalDatabase`).
- UI text is mostly pt-BR; preserve existing language in user-facing strings.
- Lints come from `flutter_lints` via `analysis_options.yaml`.

## Important Runtime Behaviors
- Notifications are initialized in app startup (`AlertService.init()` from `lib/src/app.dart`).
- Alert listener is activated by reading `alertProvider` during app init.
- MQTT connection is user-triggered from settings page; dashboard watches stream providers.
- Metrics table is auto-created in local SQLite database (`emetrics.db`).

## Pitfalls And Guardrails
- Do not edit generated or transient folders such as `build/`, platform generated files, or `**/generated/` unless explicitly requested.
- Current widget test (`test/widget_test.dart`) is template-style and may not match current UI behavior.
- Avoid hardcoding new broker/topic values in UI logic; route through providers/services.
- Preserve platform compatibility (Android/iOS/Windows/Linux/macOS/web) when changing shared app code.

## Where To Add New Code
- New screens/components: under `lib/src/ui/<feature>/`.
- New data operations: `lib/src/data/`.
- External integration logic: `lib/src/services/`.
- Wiring/state orchestration: `lib/src/providers/`.

## Agent Working Style
- Make minimal, targeted changes.
- Run `flutter analyze` after edits when feasible.
- Add or update tests when changing behavior.
- If a requested change depends on environment-specific setup, document assumptions in the PR/chat response.
