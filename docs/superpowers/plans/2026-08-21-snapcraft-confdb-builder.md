# Snapcraft ConfDB Builder Implementation Plan

> **For agentic workers:** REQUIRED: Use the `subagent-driven-development` agent (recommended) or `executing-plans` agent to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `snapcraft-confdb-builder`, a standalone Linux Flutter/Yaru workbench for authoring, validating, signing, acknowledging, inspecting, comparing, and publishing `confdb-schema` assertions.

**Architecture:** The sibling app uses a typed ConfDB domain, an injected host-tool service platform, and a workbench controller. Source edits parse to a temporary document and replace active state only after structural validation succeeds.

**Tech Stack:** Flutter/Dart 3, Yaru 10, yaml, process_run, file_selector, path_provider, shared_preferences, flutter_test, Linux desktop.

---

## Scope and Assumptions

- Create the project at `../snapcraft-confdb-builder`; do not import application code from `ubuntu-core-model-builder` or modify its application files.
- Target Linux desktop and classic snap confinement because host `snap`, `snapcraft`, and the user's snap GPG keyring are orchestrated directly.
- `snapcraft` remains the Store authentication authority. Add `SNAPCRAFT_STORE_AUTH=candid` only when detected Snapcraft major version is at least 9.
- For Store inventory, first run `snapcraft confdb-schemas <account-id>`. Fall back to `snapcraft list-confdb-schemas <account-id>` only when the first result identifies an unknown command; do not fall back for authentication, network, or server failures.
- Source is the Snapcraft editor format: assertion metadata and `views`, with `body: |-` containing JSON whose root includes `storage`. Preserve syntactically valid unknown top-level values in `extraHeaders`.
- Save, Sign, refresh, copy, comparison, and startup never invoke `snap ack` or Store publication. Publication is always explicit.

## File Structure

All paths below are relative to the new `snapcraft-confdb-builder` repository.

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | Yaru bootstrap and shutdown cleanup. |
| `lib/app/workbench_controller.dart` | Workbench state, edit transactions, dirty/signature invalidation, and UI commands. |
| `lib/models/confdb_schema_document.dart` | Document, source metadata, revision, artifact, and draft origin. |
| `lib/models/storage_node.dart` | Typed recursive storage nodes and constraints. |
| `lib/models/view_rule.dart` | View, rule, access, and placeholder path models. |
| `lib/models/diagnostic.dart`, `lib/models/command_task.dart` | Diagnostic location/severity and command lifecycle/results. |
| `lib/services/terminal_runner.dart` | Injected cancellable process interface and production runner. |
| `lib/services/host_env.dart`, `lib/services/snapcraft_env.dart` | Sanitized host environment and Snapcraft version/auth environment. |
| `lib/services/tool_locator.dart`, `lib/services/account_service.dart`, `lib/services/key_service.dart` | Tool setup, `snapcraft whoami`, and `snap keys`. |
| `lib/services/draft_file_service.dart`, `lib/services/confdb_source_codec.dart` | Draft persistence and atomic Store-compatible YAML handling. |
| `lib/services/confdb_assertion_builder.dart`, `lib/services/confdb_validator.dart` | Canonical signing input and incremental diagnostics. |
| `lib/services/schema_diff_service.dart`, `lib/services/snapcraft_metadata_builder.dart` | Revision comparison and consumer plug snippets. |
| `lib/services/assertion_service.dart` | `snap sign`, artifact persistence, and explicit `snap ack`. |
| `lib/services/store_schema_service.dart`, `lib/services/editor_bridge.dart` | Inventory, remote lookup, preflight, and temporary-editor publication. |
| `lib/pages/workbench_page.dart`, `lib/widgets/*.dart` | Desktop shell, typed editors, diagnostics, inspector, diff, and confirmation UI. |
| `test/models/`, `test/services/`, `test/app/`, `test/widgets/` | Unit, service fake, controller, and widget coverage. |
| `README.md`, `snap/snapcraft.yaml` | Developer setup, user workflow, and classic snap package. |