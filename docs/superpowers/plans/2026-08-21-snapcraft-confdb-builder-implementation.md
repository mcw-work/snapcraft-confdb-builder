# Snapcraft ConfDB Builder Implementation Plan

> **For agentic workers:** REQUIRED: Use the `subagent-driven-development` agent (recommended) or `executing-plans` agent to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `snapcraft-confdb-builder`, a standalone Linux Flutter/Yaru workbench for authoring, validating, signing, locally acknowledging, inspecting, comparing, and deliberately publishing `confdb-schema` assertions.

**Architecture:** The sibling app uses typed ConfDB models, a `WorkbenchController`, and injectable host-tool services. Structured edits are authoritative; Source parses into a temporary document and replaces active state only when parsing and structural validation succeed. Every host command yields a captured, cancellable `CommandTask`.

**Tech Stack:** Flutter/Dart 3, Yaru 10, yaml, process_run, file_selector, path_provider, shared_preferences, flutter_test, Linux desktop.

---

## Assumptions and Module Map

- Create the project at `../snapcraft-confdb-builder`; do not import or modify model-builder application code.
- Target Linux desktop and classic snap confinement because host `snap`, `snapcraft`, and the user's snap GPG keyring are orchestrated directly.
- `snapcraft` remains the Store authentication authority. Add `SNAPCRAFT_STORE_AUTH=candid` only when detected Snapcraft major version is at least 9.
- Inventory tries `snapcraft confdb-schemas <account-id>`, then `snapcraft list-confdb-schemas <account-id>` only for unknown-command output, never for auth/network/server failures.
- Source uses the Snapcraft editor format: metadata plus `views`, with `body: |-` holding JSON whose root contains `storage`. Preserve valid unknown metadata in `extraHeaders`.
- Save, Sign, refresh, copy, comparison, and startup never invoke `snap ack` or Store publication. Publication is always explicit.

| Path | Responsibility |
| --- | --- |
| `lib/models/confdb_schema_document.dart` | Document, revision, artifact, origin, dirty state. |
| `lib/models/storage_node.dart`, `lib/models/view_rule.dart` | Typed storage, constraints, views, rules, paths, access. |
| `lib/models/diagnostic.dart`, `lib/models/command_task.dart` | Diagnostics and command lifecycle/results. |
| `lib/services/confdb_source_codec.dart`, `confdb_assertion_builder.dart`, `confdb_validator.dart` | Source round-trip, signing input, validation. |
| `lib/services/schema_diff_service.dart`, `snapcraft_metadata_builder.dart` | Evolution comparison and consumer plug YAML. |
| `lib/services/terminal_runner.dart`, `host_env.dart`, `snapcraft_env.dart` | Cancellable processes and sanitized child environment. |
| `lib/services/account_service.dart`, `key_service.dart`, `store_schema_service.dart` | Account/key discovery and Store interaction. |
| `lib/services/assertion_service.dart`, `draft_file_service.dart`, `editor_bridge.dart` | Sign/ack, draft files, temporary editor bridge. |
| `lib/app/workbench_controller.dart`, `lib/pages/workbench_page.dart`, `lib/widgets/` | Workbench state and desktop UI. |

## Phase 1: Bootstrap and Domain

### Task 1: Create the sibling Yaru application

**Files:** Create `../snapcraft-confdb-builder/`; modify `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `README.md`, `snap/snapcraft.yaml`; create `lib/pages/workbench_page.dart` and `test/widget_test.dart`.

- [ ] **Step 1: Bootstrap repository**

```bash
cd /home/michael.croft-white@canonical.com/source
flutter create --platforms=linux --org com.canonical snapcraft-confdb-builder
cd snapcraft-confdb-builder
git init
git add .
git commit -m "chore: bootstrap Flutter ConfDB builder"
```

- [ ] **Step 2: Configure dependencies**

Set package name `snapcraft_confdb_builder`; add `yaru: ^10.2.0`, `yaru_icons: ^2.2.0`, `yaml: ^3.1.3`, `process_run: ^1.3.4+1`, `file_selector: ^1.0.3`, `path_provider: ^2.1.1`, and `shared_preferences: ^2.5.5`; retain `flutter_test` and use `flutter_lints: ^6.0.0`.

- [ ] **Step 3: TDD the shell**

```dart
testWidgets('starts workbench', (tester) async {
  await tester.pumpWidget(const ConfdbBuilderApp());
  expect(find.text('Snapcraft ConfDB Builder'), findsOneWidget);
  expect(find.text('Local drafts'), findsOneWidget);
  expect(find.text('Store schemas'), findsOneWidget);
});
```

Run `flutter test test/widget_test.dart`; expect failure. Implement `ConfdbBuilderApp` with `YaruTheme`, a titled `MaterialApp`, and `WorkbenchPage` containing those labels. Register `SIGINT` and `SIGTERM` cleanup through `KeyService.stopSnapGpgAgent()` with a three-second timeout. Run `flutter test test/widget_test.dart && flutter analyze`; expect pass.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml analysis_options.yaml lib/main.dart lib/pages/workbench_page.dart test/widget_test.dart README.md snap/snapcraft.yaml
git commit -m "feat: add ConfDB builder workbench shell"
```

### Task 2: Define immutable ConfDB models

**Files:** Create `lib/models/confdb_schema_document.dart`, `storage_node.dart`, `view_rule.dart`, `diagnostic.dart`, `command_task.dart`; test in `test/models/`.

- [ ] **Step 1: Write failing domain test**

```dart
test('creates versioned storage with matching writable rule', () {
  final document = ConfdbSchemaDocument.empty(
    accountId: 'brand-id', name: 'weather',
  ).copyWith(
    storage: StorageNode.map(children: {
      'v1': StorageNode.map(children: {
        'lat': StorageNode.number(minimum: -90, maximum: 90),
      }),
    }),
    views: [ConfdbView(name: 'admin', rules: [
      ConfdbRule(
        request: ConfdbPath.parse('weather.{key}'),
        storage: ConfdbPath.parse('v1.{key}'),
        access: ViewAccess.readWrite,
      ),
    ])],
  );
  expect(document.storage.children['v1']!.children['lat']!.kind, StorageKind.number);
  expect(document.views.single.rules.single.placeholders, {'key'});
});
```

- [ ] **Step 2: Implement and verify models**

Run the test and expect failure. Define `StorageKind { string, integer, number, boolean, map, array, any, alias }`; `StorageNode` with children/items/alias and `pattern`, `choices`, range, visibility, ephemeral, required, and unique-items constraints. Define placeholder-aware `ConfdbPath`; `ConfdbRule`; `ConfdbView`; `SchemaRevision`; `DraftOrigin`; `SigningArtifact`; `DiagnosticLocation`; and `CommandTask`. `ConfdbSchemaDocument` owns account/name/summary, storage/views, `extraHeaders`, latest remote, origin, dirty state, and nullable artifact. Use immutable values and `copyWith`.

```bash
flutter test test/models
flutter analyze
git add lib/models test/models
git commit -m "feat: define ConfDB schema domain models"
```

## Phase 2: Source, Validation, and Diff

### Task 3: Implement atomic Store-compatible source handling

**Files:** Create `lib/services/confdb_source_codec.dart`; test `test/services/confdb_source_codec_test.dart`.

- [ ] **Step 1: Write failing codec tests**

```dart
test('does not replace valid document with invalid source', () {
  final result = codec.applySource(weatherDocument, 'views: [broken');
  expect(result.document, same(weatherDocument));
  expect(result.diagnostics.single.code, 'source.invalid-yaml');
});

test('round-trips an unknown header', () {
  final parsed = codec.parse(validSourceWithCustomField);
  expect(parsed.document.extraHeaders['custom-field'], 'retained');
  expect(codec.encode(parsed.document), contains('custom-field: retained'));
});
```

- [ ] **Step 2: Implement and verify codec**

Parse with `loadYamlDocument`, recursively convert YAML collections, require `type: confdb-schema`, string account/name/summary, and JSON `body` containing `storage`; emit blockers `source.invalid-yaml`, `source.invalid-body-json`, or `source.missing-storage`. Preserve `revision`, `timestamp`, `views`, and unknown headers. Encode ordered `type`, `account-id`, `name`, `summary`, revision/timestamp, alphabetized extras, views, then `body`; body JSON uses two-space indentation. Return `SourceApplyResult(document, diagnostics, applied)` and set `applied` only with no blockers.

```bash
flutter test test/services/confdb_source_codec_test.dart
flutter analyze
git add lib/services/confdb_source_codec.dart test/services/confdb_source_codec_test.dart
git commit -m "feat: add atomic ConfDB source codec"
```

### Task 4: Build unsigned assertions and diagnostic rules

**Files:** Create `lib/services/confdb_assertion_builder.dart`, `confdb_validator.dart`; test `test/services/confdb_assertion_builder_test.dart`, `confdb_validator_test.dart`.

- [ ] **Step 1: Write failing tests**

```dart
test('reports publication blockers', () {
  final diagnostics = validator.validate(
    ConfdbSchemaDocument.empty(accountId: '', name: 'Bad_Name'),
  );
  expect(diagnostics.map((item) => item.code), containsAll([
    'schema.account-id-required',
    'schema.invalid-name',
    'schema.storage-required',
  ]));
});

test('reports unmatched placeholders and duplicate paths', () {
  final diagnostics = validator.validate(documentWithBadRules);
  expect(diagnostics.map((item) => item.code), contains('rule.placeholder-mismatch'));
  expect(diagnostics.map((item) => item.code), contains('rule.duplicate-request-path'));
});
```

- [ ] **Step 2: Implement and verify validation matrix**

Builder emits canonical codec ordering and rejects blockers. Validator blockers: invalid source; unsupported type/alias/constraint; missing account/name/storage; malformed path/access; unequal placeholders; duplicate `(view, request)` or storage mapping; unrepresentable constraint. Advisories: naming violations, no literal top-level `v<positive-integer>` prefix, overly broad writable mapping, and Task 5 evolution results. Each diagnostic owns `DiagnosticLocation`. Local save remains allowed with blockers; sign/publish do not.

```bash
flutter test test/services/confdb_assertion_builder_test.dart test/services/confdb_validator_test.dart
flutter analyze
git add lib/services/confdb_assertion_builder.dart lib/services/confdb_validator.dart test/services/confdb_assertion_builder_test.dart test/services/confdb_validator_test.dart
git commit -m "feat: validate and build ConfDB schema assertions"
```

### Task 5: Compare Store revisions and generate consumer snippets

**Files:** Create `lib/services/schema_diff_service.dart`, `snapcraft_metadata_builder.dart`; test matching files under `test/services/`.

- [ ] **Step 1: Write failing tests**

```dart
test('detects evolution risks', () {
  final result = diffService.compare(latestDocument, changedDocument);
  expect(result.diagnostics.map((item) => item.code), containsAll([
    'evolution.storage-removed', 'evolution.storage-type-changed',
    'evolution.access-reduced', 'evolution.field-now-required',
  ]));
});
```

- [ ] **Step 2: Implement, verify, and commit**

Flatten storage/rule maps in stable path order. Return `SchemaComparison(sourceDiff, diagnostics, changes)` with `--- remote` and `+++ draft` unified source output. Report removed/renamed paths, kind/constraint changes, reduced access, and optional-to-required as advisory. Generate consumer YAML with `interface: confdb`, `account`, `view: <schema>/<view>`, and `role: custodian` only when selected.

```bash
flutter test test/services/schema_diff_service_test.dart test/services/snapcraft_metadata_builder_test.dart
flutter analyze
git add lib/services/schema_diff_service.dart lib/services/snapcraft_metadata_builder.dart test/services/schema_diff_service_test.dart test/services/snapcraft_metadata_builder_test.dart
git commit -m "feat: compare revisions and generate ConfDB metadata"
```

## Phase 3: Host Services and CLI Integration

### Task 6: Implement process, account, and key service contracts

**Files:** Create `terminal_runner.dart`, `host_env.dart`, `snapcraft_env.dart`, `tool_locator.dart`, `account_service.dart`, `key_service.dart`, `test/support/fake_terminal_runner.dart`; test `test/services/terminal_runner_test.dart`, `account_service_test.dart`, `key_service_test.dart`.

- [ ] **Step 1: Write failing command-contract test**

```dart
test('uses candid auth for Snapcraft 9 and parses whoami', () async {
  runner.enqueue(const CommandResult.ok(stdout: 'email: dev@example.com\nid: brand-id\n'));
  final account = await service.currentAccount();
  expect(account.id, 'brand-id');
  expect(runner.calls.single.arguments, ['whoami']);
  expect(runner.calls.single.environment['SNAPCRAFT_STORE_AUTH'], 'candid');
});
```

- [ ] **Step 2: Implement and verify services**

Define `CommandRequest(executable, arguments, stdin, environment, workingDirectory, timeout)`, `CommandResult(exitCode, stdout, stderr, wasCancelled, duration)`, `TerminalRunner.run`, and `RunningCommand.cancel`. Strip `LD_LIBRARY_PATH`, `GTK_PATH`, `GIO_MODULE_DIR`, `LIBGL_DRIVERS_PATH`, `GDK_BACKEND`, and `LD_PRELOAD`. Cache Snapcraft version. `AccountService` runs exactly `snapcraft whoami`, parses `id:`, and maps login/auth errors to `account.not-authenticated`. `KeyService` runs `snap keys`, then failure-tolerant `snapcraft keys` to mark registered fingerprints.

```bash
flutter test test/services/terminal_runner_test.dart test/services/account_service_test.dart test/services/key_service_test.dart
flutter analyze
git add lib/services test/services test/support
git commit -m "feat: add host command and account services"
```

### Task 7: Implement signing and explicit local acknowledgement

**Files:** Create `lib/services/assertion_service.dart`, `draft_file_service.dart`; test `test/services/assertion_service_test.dart`, `draft_file_service_test.dart`.

- [ ] **Step 1: Write failing CLI test**

```dart
test('signs canonical input using selected key', () async {
  runner.enqueue(const CommandResult.ok(
    stdout: 'type: confdb-schema\nname: weather\n\nBASE64SIGNATURE\n',
  ));
  await service.sign(unsignedInput: 'type: confdb-schema\n', keyName: 'my-key');
  expect(runner.calls.single.arguments, ['sign', '-k', 'my-key']);
  expect(runner.calls.single.stdin, 'type: confdb-schema\n');
});
```

- [ ] **Step 2: Implement, verify, and commit**

Run `snap sign -k <key>` with unsigned input on stdin; require zero exit, `type: confdb-schema`, and nonempty blank-separated signature. Return `SigningArtifact`; save only to selector-chosen path. Run acknowledgement only as `snap ack <saved-file>` and return a distinct `CommandTaskKind.ack`; its failure never changes signing or Store status. Draft service persists UTF-8 YAML and `draft.lastDirectory`.

```bash
flutter test test/services/assertion_service_test.dart test/services/draft_file_service_test.dart
flutter analyze
git add lib/services/assertion_service.dart lib/services/draft_file_service.dart test/services/assertion_service_test.dart test/services/draft_file_service_test.dart
git commit -m "feat: sign and acknowledge ConfDB assertions"
```

### Task 8: Implement inventory, remote lookup, preflight, and editor bridge

**Files:** Create `lib/services/store_schema_service.dart`, `editor_bridge.dart`; test `test/services/store_schema_service_test.dart`, `editor_bridge_test.dart`.

- [ ] **Step 1: Write failing version-tolerant CLI tests**

```dart
test('uses legacy inventory only when preferred command is unknown', () async {
  runner.enqueue(const CommandResult(
    exitCode: 2, stdout: '', stderr: 'unknown command "confdb-schemas"',
  ));
  runner.enqueue(const CommandResult.ok(stdout: 'weather 7\n'));
  final rows = await service.inventory('brand-id');
  expect(runner.calls.map((call) => call.arguments), [
    ['confdb-schemas', 'brand-id'], ['list-confdb-schemas', 'brand-id'],
  ]);
  expect(rows.single, const StoreSchemaRow(name: 'weather', revision: '7'));
});

test('uses remote assertion lookup contract', () async {
  runner.enqueue(const CommandResult.ok(stdout: 'type: confdb-schema\n'));
  await service.fetchRemote(accountId: 'brand-id', name: 'weather');
  expect(runner.calls.single.arguments, [
    'known', '--remote', 'confdb-schema', 'account-id=brand-id', 'name=weather',
  ]);
});
```

- [ ] **Step 2: Implement exact integration and cleanup**

`StoreSchemaService.inventory` accepts JSON list/map and whitespace/table output as `StoreSchemaRow(name, revision)`; malformed rows give `store.inventory-unparseable`. Fallback is only for `unknown command`, `no such command`, or `invalid choice`. `fetchRemote` invokes exactly `snap known --remote confdb-schema account-id=<id> name=<name>`. `preflight` fetches remote, parses it, and returns comparison.

`EditorBridge.create` makes unique temporary `source.yaml` and a mode-`0700` executable `confdb-editor`:

```sh
#!/bin/sh
set -eu
cat "$CONFDB_EDITOR_SOURCE" > "$1"
```

Publication invokes process arguments `snapcraft edit-confdb-schema --key-name <key> <account-id> <name>` with `EDITOR=<temp>/confdb-editor` and `CONFDB_EDITOR_SOURCE=<temp>/source.yaml`. Delete temporary directory in `finally` after success, failure, cancellation, and timeout. Never interpolate these values into a shell string.

- [ ] **Step 3: Verify bridge cleanup and commit**

```dart
test('removes bridge after failed publish', () async {
  runner.enqueue(const CommandResult(exitCode: 1, stdout: '', stderr: 'upload rejected'));
  await expectLater(service.publish(accountId: 'brand-id', name: 'weather', keyName: 'my-key', source: source), throwsA(isA<StoreCommandException>()));
  expect(fileSystem.tempEntriesNamed('confdb-editor-'), isEmpty);
});
```

```bash
flutter test test/services/store_schema_service_test.dart test/services/editor_bridge_test.dart
flutter analyze
git add lib/services/store_schema_service.dart lib/services/editor_bridge.dart test/services/store_schema_service_test.dart test/services/editor_bridge_test.dart
git commit -m "feat: add ConfDB Store schema integration"
```

## Phase 4: Standalone Workbench and Gated Publication

### Task 9: Implement workbench transactions and hybrid UI

**Files:** Create `lib/app/workbench_controller.dart`, `lib/widgets/draft_sidebar.dart`, `store_schema_sidebar.dart`, `storage_tree_editor.dart`, `view_rule_editor.dart`, `source_editor.dart`, `diagnostics_panel.dart`, `command_task_panel.dart`, `inspector_panel.dart`; modify `lib/pages/workbench_page.dart`; test in `test/app/workbench_controller_test.dart` and `test/widgets/`.

- [ ] **Step 1: Write failing transaction and Source widget tests**

```dart
test('accepted edit dirties draft and invalidates artifacts', () {
  final controller = controllerWithSignedWeatherDocument();
  controller.updateSummary('Updated weather schema');
  expect(controller.document.isDirty, isTrue);
  expect(controller.document.artifact, isNull);
});

testWidgets('invalid Source cannot replace structured document', (tester) async {
  await tester.pumpWidget(testWorkbench());
  await tester.enterText(find.byKey(const Key('source-editor')), 'views: [broken');
  await tester.tap(find.text('Apply source'));
  await tester.pump();
  expect(find.text('Source could not be applied'), findsOneWidget);
  expect(find.byKey(const Key('storage-node-v1')), findsOneWidget);
});
```

- [ ] **Step 2: Implement and verify workbench**

`WorkbenchController` is a `ChangeNotifier` with document, local drafts, Store rows, diagnostics, task list, selected tab/view, and busy state. All accepted changes route through `replaceDocument`: mark dirty, clear signed artifact/tasks, recompute diagnostics, invalidate preflight fingerprint (`SHA-256(canonicalSource)`), notify. Invalid Source changes nothing. Dirty-open prompt offers Discard, Save, Cancel; Store copy creates local dirty draft only.

Use persistent navigation-rail-style Local drafts and independently refreshable Store schemas. Central tabs are exactly Schema, Views, Source, Validation, Publish. Use typed tree/rule editors, monospaced selectable source/output, `YaruSection`, Material icons, `StatusColors`, diagnostic navigation, inspector data, short busy overlay, and safe cancel through `RunningCommand.cancel`.

```bash
flutter test test/app/workbench_controller_test.dart test/widgets
flutter analyze
git add lib/app lib/pages lib/widgets test/app test/widgets
git commit -m "feat: add structured ConfDB authoring workbench"
```

### Task 10: Add publish preflight and typed confirmation

**Files:** Create `lib/widgets/publish_panel.dart`, `publish_confirmation_dialog.dart`, `schema_diff_view.dart`; modify controller/page; test `test/widgets/publish_panel_test.dart`, `publish_confirmation_dialog_test.dart`.

- [ ] **Step 1: Write failing publication-gate tests**

```dart
testWidgets('blockers disable publish after preflight', (tester) async {
  await tester.pumpWidget(testWorkbench(withBlockingDiagnostic: true));
  await tester.tap(find.text('Refresh preflight'));
  await tester.pump();
  expect(find.text('--- remote'), findsOneWidget);
  expect(find.byKey(const Key('publish-button')), isDisabled);
});

testWidgets('exact schema name enables confirmation', (tester) async {
  await tester.pumpWidget(testPublishPanel(schemaName: 'weather', publishable: true));
  await tester.tap(find.byKey(const Key('publish-button')));
  await tester.enterText(find.byKey(const Key('schema-name-confirmation')), 'Weather');
  await tester.pump();
  expect(find.byKey(const Key('confirm-publish-button')), isDisabled);
  await tester.enterText(find.byKey(const Key('schema-name-confirmation')), 'weather');
  await tester.pump();
  expect(find.byKey(const Key('confirm-publish-button')), isEnabled);
});
```

- [ ] **Step 2: Implement, verify, and commit**

Publish displays account, schema target, key, unsigned/signed outputs, saved path, explicit `Run snap ack`, remote assertion, structured changes, source diff, and validation. Sign needs zero blockers/key. Publish additionally needs preflight fingerprint equal to current document fingerprint. Confirmation invokes only `StoreSchemaService.publish`, then refreshes inventory and selected remote assertion. Failed ack never disables valid publish; failed publish preserves draft and signed artifact.

```bash
flutter test test/widgets/publish_panel_test.dart test/widgets/publish_confirmation_dialog_test.dart
flutter analyze
git add lib/widgets/publish_panel.dart lib/widgets/publish_confirmation_dialog.dart lib/widgets/schema_diff_view.dart lib/pages/workbench_page.dart lib/app/workbench_controller.dart test/widgets/publish_panel_test.dart test/widgets/publish_confirmation_dialog_test.dart
git commit -m "feat: add gated ConfDB schema publication"
```

## Phase 5: Packaging and Integration Checkpoint

### Task 11: Document, package, and test the full lifecycle

**Files:** Modify `README.md`, `snap/snapcraft.yaml`; test full `test/` suite.

- [ ] **Step 1: Document host setup and side effects**

Document `flutter pub get`, `flutter run -d linux`, `snapcraft`, classic local installation, `snap`, authenticated `snapcraft whoami`, local `snap keys`, registered key for publication, and graphical pinentry. Explain that drafts are ordinary YAML, `snap ack` mutates the local assertion database, and Store publication creates an immutable revision. Describe the temporary editor bridge and cleanup.

- [ ] **Step 2: Configure classic package and run automated validation**

Set snap name `snapcraft-confdb-builder`, Flutter part, and `confinement: classic`; include desktop entry/icon. Then run:

```bash
flutter test
flutter analyze
flutter build linux
git status --short
```

Expected: tests, analysis, and Linux build pass; only intended project changes appear.

- [ ] **Step 3: Perform manual integration checks**

1. Compare app account with `snapcraft whoami`; compare app keys/fingerprints with `snap keys` and registered state with `snapcraft keys`.
2. Refresh schemas; record installed Snapcraft version, successful inventory spelling, and a known name/revision.
3. Inspect that schema; confirm exact `snap known --remote confdb-schema account-id=<id> name=<name>` retrieval and that Copy to draft makes no Store change.
4. Build `v1` storage and matching `{key}` rule; verify structured editor, Source, unsigned assertion, and generated plug agree.
5. Enter invalid YAML and mismatched placeholders; confirm Source is unchanged and Save remains available while Sign/Publish are blocked.
6. On a ConfDB-enabled development system, sign, save, and explicitly acknowledge; confirm ack result is independent from publication state.
7. On a non-production test schema, preflight, inspect account/key/diff, type exact name, publish, and confirm refreshed inventory/remote assertion has new revision. Verify wrong confirmation cannot publish.

- [ ] **Step 4: Commit documentation and packaging**

```bash
git add README.md snap/snapcraft.yaml
git commit -m "docs: document ConfDB builder setup and publication workflow"
```

## Risks and Checkpoints

| Risk | Mitigation |
| --- | --- |
| Snapcraft command/output variation | Strict unknown-command fallback; fixture tests for JSON/table output; record installed version and output before release. |
| `edit-confdb-schema` requires executable `EDITOR` | Use unique mode-`0700` script path, not a command string; test cleanup on success, error, cancel, timeout. |
| Advanced source data loss | Preserve unknown headers in `extraHeaders`; Source remains escape hatch. |
| Ack and publication conflated | Separate command task kinds and state transitions. |
| Remote race | Bind preflight to canonical-source SHA-256 and invalidate on every accepted edit; exact typed target confirmation. |

## Plan Self-Review

- **Spec coverage:** The tasks cover bootstrap, standalone workbench, local/Store sidebars, hybrid editor, validation, signing, acknowledgement, inventory/retrieval/comparison, consumer metadata, temporary-editor publishing, confirmation, and manual checks.
- **Placeholder scan:** No deferred work markers are used; each phase includes concrete paths, tests, interfaces, commands, and expected outcomes.
- **Type consistency:** `ConfdbSchemaDocument`, `ConfdbSourceCodec`, `ConfdbValidator`, `StoreSchemaService`, `AssertionService`, `WorkbenchController`, `CommandTask`, and `StoreSchemaRow` are introduced before use.

Plan complete and saved to `docs/superpowers/plans/2026-08-21-snapcraft-confdb-builder-implementation.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using the `executing-plans` agent, batch execution with checkpoints.

Which approach?