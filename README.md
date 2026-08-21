# Snapcraft ConfDB Builder

A Linux desktop workbench for authoring and publishing Snapcraft ConfDB schema
assertions.

The application edits ordinary YAML draft files, so they can live alongside a
snap project and be reviewed, diffed, and versioned with Git. It uses the host
`snap` and `snapcraft` commands to inspect keys, acknowledge local assertions,
and publish schemas. It does not upload a schema until the user explicitly
confirms publication in the application.

## Flutter Development

Install the Flutter SDK and the Linux desktop build dependencies, then enable
Linux desktop support and run the application from a checkout. On Ubuntu or
Debian, install the native dependencies with:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

Then run:

```bash
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
```

Run the automated checks used by this project with:

```bash
flutter test
flutter analyze
flutter build linux
```

## Classic Snap Package

The package is a classic snap because it must run the host `snap` and
`snapcraft` commands and access the user's GPG keyring. Build and install it
locally with:

```bash
snapcraft pack
sudo snap install --classic snapcraft-confdb-builder_*.snap
snapcraft-confdb-builder
```

No custom desktop entry or icon is configured: this repository does not contain
desktop-entry or icon assets. Snapd creates the standard launcher from the
`snapcraft-confdb-builder` application declared in `snap/snapcraft.yaml`.

## Host Prerequisites

Install the host `snap` command and a current Snapcraft release before using
the packaged application. The application deliberately uses the host tools, so
they must be available on `PATH`:

```bash
snap version
snapcraft --version
snapcraft whoami
```

`snapcraft whoami` is a manual authentication check. Sign in with
`snapcraft login` if it reports that no account is authenticated; do not assume
that a local signing key implies Store access.

## Signing Keys and Pinentry

ConfDB assertions are signed by a local key and Store publication additionally
requires that key to be registered with the signed-in Snapcraft account. Inspect
the two states with:

```bash
snap keys
snapcraft keys
```

Create a local key when needed, then register it before publishing:

```bash
snap create-key confdb-builder
snapcraft register-key confdb-builder
```

Signing can prompt through GPG. On graphical desktops, install and configure a
graphical pinentry program, for example `pinentry-gtk-2`, and point
`~/.gnupg/gpg-agent.conf` at it:

```text
pinentry-program /usr/bin/pinentry-gtk-2
```

Reload the agent after changing that file with `gpgconf --kill gpg-agent`.
The key and account commands above are manual, user-authenticated operations;
they are not performed automatically by this project.

## Draft, Local, and Store Workflows

Use **Open**, **Save**, and **Save As** to manage draft `.yaml` files. Their
content is regular YAML rather than an application database format, so a team
can review it in a normal Git workflow.

The local signing path produces a signed assertion that can be acknowledged on
the current machine:

```bash
snap sign -k confdb-builder schema.assertion > schema.assert
sudo snap ack schema.assert
```

`snap ack` changes the local snap assertion database only. It is useful for
local testing but does not publish the schema or create a Store revision.

The application’s **Publish** action calls `snapcraft edit-confdb-schema` after
the user reviews the remote comparison and confirms the target account, schema,
and signing key. Store publishing creates a new immutable revision; it is a
separate operation from local acknowledgement and cannot amend a published
revision.

Snapcraft’s editing command requires an executable editor, while the workbench
owns the YAML source. During publication, the app creates a private temporary
editor bridge that copies the draft into Snapcraft’s editor file. The bridge and
its source are removed after the command finishes, succeeds, fails, or is
cancelled. This cleanup is temporary-file hygiene, not a replacement for
retaining the YAML draft in Git.
