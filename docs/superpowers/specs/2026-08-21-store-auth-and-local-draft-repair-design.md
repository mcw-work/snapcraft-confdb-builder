# Store Authentication and Local Draft Repair Design

## Goal

Repair two installed-snap defects and release the repair as a distinguishable
snap version:

- The Store pane must use the same authenticated Snapcraft credential discovery
  as `snapcraft confdb-schemas` in the user's terminal.
- Local drafts must update one active in-session entry while editable fields
  change.

## Store Authentication

`SnapcraftEnvironment` will continue to remove a pre-existing
`SNAPCRAFT_STORE_AUTH` value from the inherited environment, but it will not set
`SNAPCRAFT_STORE_AUTH=candid` for Snapcraft 9 or later. Snapcraft will choose
its normal credential format and location.

The account, key, and Store-schema services will keep using the shared sanitized
environment. This prevents caller-specific credential behavior and makes the
application match the known-working command-line workflow.

## Local Draft Identity

`WorkbenchController` will retain an immutable private identity for its active
in-session draft. Replacing the document updates the local-draft entry linked to
that identity, even when account ID or schema name change. Opening a draft or
copying a Store schema establishes the active identity for that document.

The sidebar continues to receive `ConfdbSchemaDocument` values and no identifier
is exposed through its interface. The feature remains in-memory only; no
autosave, debounce, or persistent draft history is introduced.

## Release

Increase the application and snap version from `1.0.0` to `1.0.1`. Build a new
classic snap after focused tests, the full test suite, and static analysis pass.
Replace the installed local snap using the compatible remove-and-install
workflow, preserving Snapd's automatic pre-removal snapshot.

## Testing

- Extend Snapcraft environment tests to assert that a Snapcraft 9 environment
  does not inject `SNAPCRAFT_STORE_AUTH`.
- Add controller coverage proving repeated edits to account ID and schema name
  retain one Local drafts entry with the latest document values.
- Keep existing Store inventory command-contract coverage to ensure the Store
  pane still invokes `snapcraft confdb-schemas` without a positional account
  argument.