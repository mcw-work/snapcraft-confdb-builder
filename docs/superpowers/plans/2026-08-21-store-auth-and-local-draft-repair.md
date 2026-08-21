# Store Authentication and Local Draft Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Store schema inventory in the installed snap and prevent Local drafts from multiplying when editable identifiers change.

**Architecture:** Snapcraft child processes inherit a sanitized host environment without imposing a credential format. `WorkbenchController` keeps a private stable ID for the active in-memory draft, allowing the visible `ConfdbSchemaDocument` to change while its Local drafts entry is updated in place.

**Tech Stack:** Flutter/Dart 3, flutter_test, Snapcraft 9, classic Snap packaging.

---

### Task 1: Preserve Snapcraft credential discovery

**Files:**
- Modify: `lib/services/snapcraft_env.dart`
- Create: `test/services/snapcraft_env_test.dart`

- [ ] **Step 1: Write the failing environment contract test**

```dart
test('does not impose a credential format for Snapcraft 9', () {
  final environment = const SnapcraftEnvironment(majorVersion: 9).build({
    'HOME': '/home/dev',
    'SNAPCRAFT_STORE_AUTH': 'candid',
  });

  expect(environment['HOME'], '/home/dev');
  expect(environment, isNot(contains('SNAPCRAFT_STORE_AUTH')));
});
```

- [ ] **Step 2: Run the test and observe the forced Candid failure**

Run: `/home/michael.croft-white@canonical.com/.cache/flutter/bin/flutter test test/services/snapcraft_env_test.dart`

Expected: FAIL because `SNAPCRAFT_STORE_AUTH` equals `candid`.

- [ ] **Step 3: Remove forced credential-format injection**

Replace the `build` implementation with:

```dart
Map<String, String> build([Map<String, String>? hostEnvironment]) {
  final environment = Map<String, String>.from(
    sanitizedHostEnvironment(hostEnvironment),
  );
  environment.remove('SNAPCRAFT_STORE_AUTH');
  return Map.unmodifiable(environment);
}
```

- [ ] **Step 4: Verify the environment and Store command contracts**

Run: `/home/michael.croft-white@canonical.com/.cache/flutter/bin/flutter test test/services/snapcraft_env_test.dart test/services/store_schema_service_test.dart`

Expected: PASS. The Store test continues to require `snapcraft confdb-schemas` without a positional account ID.

### Task 2: Give Local drafts stable active identity

**Files:**
- Modify: `lib/controllers/workbench_controller.dart`
- Modify: `test/controllers/workbench_controller_test.dart`

- [ ] **Step 1: Write a failing Local drafts identity regression**

```dart
test('updates one local draft when editable identifiers change', () {
  final controller = WorkbenchController(document: _document());

  controller.replaceDocument(controller.document.copyWith(name: 'w'));
  controller.replaceDocument(controller.document.copyWith(name: 'we'));
  controller.replaceDocument(
    controller.document.copyWith(accountId: 'opaqueStoreAccount'),
  );

  expect(controller.localDrafts, hasLength(1));
  expect(controller.localDrafts.single.name, 'we');
  expect(controller.localDrafts.single.accountId, 'opaqueStoreAccount');
});
```

- [ ] **Step 2: Run the controller test and observe duplicate rows**

Run: `/home/michael.croft-white@canonical.com/.cache/flutter/bin/flutter test test/controllers/workbench_controller_test.dart`

Expected: FAIL because `localDrafts` contains multiple entries.

- [ ] **Step 3: Track active draft identity separately from editable fields**

Add a private active identity and incrementing counter:

```dart
int _nextLocalDraftId = 0;
late int _activeLocalDraftId = _createLocalDraftId();
final Map<int, ConfdbSchemaDocument> _localDraftsById = {};

int _createLocalDraftId() => _nextLocalDraftId++;
```

Update `_upsertLocalDraft` to write the document to `_localDraftsById` under
`_activeLocalDraftId` and derive `_localDrafts` from its values. In
`openDocument`, assign `_activeLocalDraftId = _createLocalDraftId()` before
publishing the opened document. Keep `replaceDocument` and `markSaved` on the
current identity so typing and saving replace the active sidebar row.

- [ ] **Step 4: Verify controller behavior**

Run: `/home/michael.croft-white@canonical.com/.cache/flutter/bin/flutter test test/controllers/workbench_controller_test.dart`

Expected: PASS. Repeated name/account-ID edits retain exactly one Local drafts entry with latest values.

### Task 3: Publish repair release

**Files:**
- Modify: `pubspec.yaml`
- Modify: `snap/snapcraft.yaml`

- [ ] **Step 1: Increase application and snap versions**

Change `version: 1.0.0+1` in `pubspec.yaml` to `version: 1.0.1+1` and change
`version: '1.0.0'` in `snap/snapcraft.yaml` to `version: '1.0.1'`.

- [ ] **Step 2: Run full verification**

Run:

```bash
/home/michael.croft-white@canonical.com/.cache/flutter/bin/flutter test
/home/michael.croft-white@canonical.com/.cache/flutter/bin/flutter analyze
```

Expected: all tests pass and analyzer reports no issues.

- [ ] **Step 3: Commit and publish repair source**

```bash
git add lib/services/snapcraft_env.dart lib/controllers/workbench_controller.dart \
  test/services/snapcraft_env_test.dart test/controllers/workbench_controller_test.dart \
  pubspec.yaml snap/snapcraft.yaml
git commit -m "fix: restore Store auth and stable local drafts"
git push origin master
```

- [ ] **Step 4: Build and install the repair snap**

```bash
snapcraft pack
sudo snap remove snapcraft-confdb-builder
sudo snap install --classic --dangerous ./snapcraft-confdb-builder_1.0.1_amd64.snap
snap list snapcraft-confdb-builder
```

Expected: Snapcraft creates `snapcraft-confdb-builder_1.0.1_amd64.snap`; the installed snap reports version `1.0.1`.