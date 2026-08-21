# ConfDB Assertion Builder Design

## Summary

Build a standalone sibling Flutter application named
`snapcraft-confdb-builder`, for authoring and managing `confdb-schema`
assertions. The application will give developers a structured workbench for
creating schemas, validating them, signing locally, testing local import, and
creating or updating the account's Store schemas.

It will follow the visual and technical patterns of the existing Ubuntu Core
Model Builder: a Yaru desktop application, host-tool orchestration, clear
incremental validation, and an assertion review surface. It is a separate app
for now, but its non-ConfDB-specific service contracts will be intentionally
shaped for later extraction into a shared assertion platform.

## Goals

- Make the full ConfDB schema lifecycle usable without hand-editing temporary
  files for `snapcraft edit-confdb-schema`.
- Provide a guided editor that covers normal schema construction and preserves
  a source-editor escape hatch for advanced work.
- Catch syntax, structural, semantic, naming, and evolution issues before a
  Store upload.
- Let account owners inventory, inspect, compare, create, and update their
  existing Store schemas.
- Preserve developer ownership of drafts as normal YAML files that can live in
  Git repositories.
- Generate selected ConfDB plug declarations for consumer `snapcraft.yaml`
  files.
- Keep Store publication deliberate because it creates a new revision that is
  not editable in place.

## Non-Goals

- Generating or modifying custodian/observer hook implementation code.
- Mutating a snap project, deploying snaps, managing interface connections, or
  editing live ConfDB values.
- Calling a private Store API or maintaining Store authentication separately
  from the installed `snapcraft` tooling.
- Deleting Store schemas, background publishing, or automatic local
  acknowledgement.
- Sharing source code with the model builder in this stage.

## Product Shape

The application is a desktop workbench rather than a linear wizard. This suits
the repeated editing and comparison loop of ConfDB schema work while retaining
the model builder's desktop Yaru look and direct, reviewable workflows.

### Layout

The persistent left sidebar has two independently refreshable groups:

- **Local drafts**: user-selected YAML files with dirty-state indicators,
  create, open, save, save-as, import, and export actions.
- **Store schemas**: schemas owned by the authenticated account, showing schema
  name and latest known revision. A user can refresh, inspect a remote
  assertion, copy it into a local draft, or compare it to the active draft.

The central editor has the following tabs:

1. **Schema**: typed field tree for storage definitions.
2. **Views**: typed view and rule editor.
3. **Source**: editable Store-compatible schema source.
4. **Validation**: grouped diagnostics and navigation back to their owner.
5. **Publish**: signing, verification, local acknowledgement, Store comparison,
   and gated publication.

A contextual inspector shows the generated assertion input, selected Store
revision metadata, diagnostics, and command-task status when relevant.

### Visual Language

Use the established application vocabulary:

- `YaruTheme`, `YaruSection`, Material icons, restrained status colors, and
  desktop-width layout.
- Navigation-rail-style sidebar controls and clear enabled/disabled action
  states.
- Monospace, selectable surfaces for YAML, JSON assertion input, signed
  assertion output, command output, and revision diffs.
- Brief busy overlays with cancellation where a host process supports it.
- Existing-style inline blockers and snackbars/dialogs for actionable errors.

## Architecture

The app is divided into three layers.

### Workbench UI

Widgets render the workbench, draft/Store navigation, field tree, view/rule
tables, source editor, diagnostic list, publish preflight, and confirmation
dialogues. Widgets depend on view models and service interfaces rather than
process invocation directly.

### ConfDB Domain

ConfDB-specific code owns:

- `ConfdbSchemaDocument`: account identity, schema name, source metadata,
  storage schema, views, revision information, draft origin, and dirty state.
- Typed storage nodes for `string`, `int`, `number`, `bool`, `map`, `array`,
  `any`, and user-defined aliases; applicable constraints such as pattern,
  choices, range, visibility, ephemeral state, required fields, and array
  uniqueness.
- View/rule definitions including request paths, storage paths, placeholders,
  and read/read-write access.
- YAML parsing/serialization, conversion to the JSON input expected by
  `snap sign`, diagnostics, naming checks, and revision evolution comparison.

The structured editor is the normal editing path. The Source tab serializes the
same document and applies text only by parsing into a temporary document first;
the active document changes only when parsing and structural validation
succeed.

### Assertion Platform Services

Generic, future-extractable services provide:

- Tool discovery and cancellable terminal execution.
- Account discovery, key discovery, and signing-key selection.
- Source-file reading/writing and last-directory preferences.
- Assertion signing, artifact persistence, and signed-output checks.
- Local acknowledgement and command-result reporting.
- Store inventory, selected-assertion retrieval, and publish orchestration.

The model builder should later be able to consume these capabilities through a
shared package. Its model-specific editor and the ConfDB-specific editor remain
separate domain modules.

## Host Tool Integration

The app uses installed host tools rather than an undocumented API:

- `snapcraft whoami` obtains the current Store account.
- `snap keys` and existing key-management patterns discover local signing keys.
- `snapcraft` ConfDB listing support discovers account-owned Store schemas. The
  adapter supports the version-appropriate `confdb-schemas` or
  `list-confdb-schemas` command.
- `snap known --remote confdb-schema account-id=<id> name=<name>` retrieves a
  selected Store assertion for inspection and comparison.
- `snap sign -k <key>` signs locally generated assertion input.
- `snap ack <file>` is an explicit local verification action and may require
  host authorization.
- `snapcraft edit-confdb-schema --key-name <key> <account-id> <name>` creates
  or updates a Store schema.

For Store publication, a controlled temporary-editor bridge is used. The app
writes an executable editor helper into its runtime temporary directory and
sets `EDITOR` to that executable for `snapcraft edit-confdb-schema`. When
Snapcraft invokes it, the helper replaces the temporary source with the
preflighted document and exits successfully. The app captures stdout/stderr,
cleans up the temporary helper and source, then refreshes the Store inventory.
This honors Snapcraft's supported workflow without requiring the user to run a
separate terminal editor.

## Authoring And Validation

Validation runs incrementally and is visible in the Validation tab and at the
owning field/rule.

### Blocking Diagnostics

- Invalid YAML or source format.
- Unsupported storage types, aliases, or constraints.
- Missing account identity or schema name.
- Invalid view access mode, malformed request/storage mapping, unresolved
  placeholder pairing, or duplicate paths.
- Constraint combinations that cannot be converted to the assertion input.
- Missing signing key or malformed generated assertion data during signing.

### Advisory Diagnostics

- Schema, view, plug, request, and storage naming convention violations.
- Missing literal versioned storage prefixes such as `v1`.
- Overly broad writable views, including mappings that expose more storage than
  a request needs.
- Breaking or suspicious differences from the latest Store revision: renamed or
  removed storage paths, changed type/constraint, reduced access, and newly
  required fields.

Advisories never prevent saving a local draft. All blockers must be resolved to
sign or publish.

## Draft, Signing, And Publication Flow

1. A developer creates a new draft or opens a local YAML file.
2. Structured editor changes update the active document. Source edits first
   parse and validate into a temporary document; only accepted source replaces
   the active document.
3. Any accepted change invalidates prior signed and publication artifacts.
4. The developer saves the YAML draft in a project location suitable for Git.
5. The Publish tab builds and displays the unsigned assertion input, signs with
   the selected key, and makes the signed output reviewable/exportable.
6. The developer may explicitly run local `snap ack` after saving the signed
   assertion. A failed authorization or acknowledgement reports the exact
   command result without implying that Store publication failed.
7. Before publish, the app fetches the latest remote revision and shows a
   structured/source diff, validation result, account/schema target, and
   signing key.
8. Publish remains disabled until blockers pass. The developer must type the
   schema name in the confirmation dialog.
9. The editor bridge invokes `snapcraft edit-confdb-schema`; on success the app
   refreshes the inventory and shows the new revision.

Viewing a Store schema and copying it to a draft never mutate Store state.

## Generated Snapcraft Metadata

For a selected view, the workbench generates a focused YAML snippet for a
consumer snap's `snapcraft.yaml`:

- `interface: confdb`
- account ID
- `<schema>/<view>` reference
- `role: custodian` when a developer chooses the custodian declaration

The app does not generate hook implementation code. It can link a diagnostic
or information panel to the role expectations, but hooks stay in the consuming
snap project.

## Error Handling

- Command errors include an action-oriented summary and expandable stdout/stderr
  details.
- Missing host tools, authentication, keys, and experimental ConfDB support are
  surfaced as setup requirements with retry actions.
- Long-running host commands show progress and cancel where process termination
  is safe.
- The app never treats failed local `snap ack` as a failed Store upload or vice
  versa.
- Temporary editor bridge files are isolated per operation and removed in a
  `finally` path.

## Testing Strategy

### Unit Tests

- Storage/view document serialization and parsing.
- Assertion-input conversion and canonical ordering.
- Blocker/advisory validation rules.
- Naming checks and revision evolution diffing.
- Source-apply atomicity and signing-artifact invalidation.

### Service Tests

- Fake terminal runner verifies arguments, environment, temporary editor
  contract, parsed inventory, Store lookup, sign, acknowledge, and friendly
  error mapping.

### Widget Tests

- Field and rule changes display diagnostics and invalidate stale signatures.
- Invalid source cannot replace a valid document.
- Store preflight displays remote differences and blocks publication on errors.
- Typed schema-name confirmation gates publish.
- Draft and Store sidebar operations preserve unsaved-change behavior.

### Manual Integration Checklist

- Detect an authenticated `snapcraft` account and registered key.
- List schemas, retrieve a known remote revision, and copy it locally.
- Sign and acknowledge a draft on a ConfDB-enabled development system.
- Publish a controlled schema update and confirm the refreshed Store revision.

## Future Integration Boundary

The later combined application should extract an assertion workspace platform
covering account/key/tool services, source-file operations, signing and
verification artifacts, Store inventory rows, command task reporting, and
publish preflight. It should keep model-specific and ConfDB-specific document
models and editors separate.

This boundary avoids preemptively coupling two independent applications while
ensuring their common operational logic can be consolidated without redesign.