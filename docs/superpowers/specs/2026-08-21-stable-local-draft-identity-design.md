# Stable Local Draft Identity Design

## Goal

Keep Local drafts as a concise list of active in-session documents. Editing a
schema's account ID or name must update its existing Local drafts entry rather
than creating a new entry for each intermediate value.

## Current Behavior

`WorkbenchController._upsertLocalDraft` identifies a draft by its account ID and
schema name. Both fields are editable. As either value changes,
`replaceDocument` upserts a distinct entry, which turns normal typing into a
sidebar history of intermediate drafts.

## Design

The controller will assign every active in-session draft a private, immutable
identity. `replaceDocument` will update the Local drafts row associated with
that identity, regardless of changes to the schema's editable fields.

Opening a Local draft, copying a Store schema, and starting with the initial
empty document will establish an active draft identity. Saving a document keeps
the same identity and updates its Local drafts entry with the saved document.
The existing `localDrafts` and sidebar interfaces remain document-based and do
not expose the identity.

## Boundaries

This change does not add disk-backed autosave, debounce text events, retention
rules, or a new UI control. Local drafts remain in-memory workbench entries.

## Error Handling

No new asynchronous operations or user-visible errors are introduced. Existing
save and load errors retain their current handling.

## Testing

Add controller-level regression coverage that applies successive edits to a
document's name and account ID, then verifies that Local drafts contains one
entry whose values match the latest document. Cover opening a different draft
to ensure it intentionally establishes the active identity used for subsequent
edits.