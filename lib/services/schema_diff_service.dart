import 'dart:convert';

import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../models/storage_node.dart';
import '../models/view_rule.dart';

enum SchemaChangeKind { added, removed, modified, renamed }

class SchemaChange {
  const SchemaChange({
    required this.kind,
    required this.subject,
    required this.path,
    this.previousPath,
  });

  final SchemaChangeKind kind;
  final String subject;
  final String path;
  final String? previousPath;
}

class SchemaComparison {
  const SchemaComparison({
    required this.changes,
    required this.diagnostics,
    required this.sourceDiff,
  });

  final List<SchemaChange> changes;
  final List<Diagnostic> diagnostics;
  final String sourceDiff;

  bool get hasChanges => changes.isNotEmpty;
  bool get hasBlockers => diagnostics.any((diagnostic) => diagnostic.isBlocker);
}

class SchemaDiffService {
  const SchemaDiffService();

  SchemaComparison compare({
    required ConfdbSchemaDocument remote,
    required ConfdbSchemaDocument draft,
  }) {
    final remoteStorage = _flattenStorage(remote.storage);
    final draftStorage = _flattenStorage(draft.storage);
    final remoteRules = _flattenRules(remote.views);
    final draftRules = _flattenRules(draft.views);
    final changes = <SchemaChange>[];
    final diagnostics = <Diagnostic>[];

    _compareStorage(
      remoteStorage,
      draftStorage,
      changes: changes,
      diagnostics: diagnostics,
    );
    _compareRules(
      remoteRules,
      draftRules,
      changes: changes,
      diagnostics: diagnostics,
    );

    changes.sort(
      (left, right) => _changeKey(left).compareTo(_changeKey(right)),
    );
    diagnostics.sort(
      (left, right) => _diagnosticKey(left).compareTo(_diagnosticKey(right)),
    );
    return SchemaComparison(
      changes: List.unmodifiable(changes),
      diagnostics: List.unmodifiable(diagnostics),
      sourceDiff: _buildSourceDiff(
        remoteStorage,
        draftStorage,
        remoteRules,
        draftRules,
      ),
    );
  }

  void _compareStorage(
    Map<String, _StorageEntry> remote,
    Map<String, _StorageEntry> draft, {
    required List<SchemaChange> changes,
    required List<Diagnostic> diagnostics,
  }) {
    final removedPaths =
        remote.keys.where((path) => !draft.containsKey(path)).toList()..sort();
    final addedPaths =
        draft.keys.where((path) => !remote.containsKey(path)).toList()..sort();
    final renamedRemotePaths = <String>{};
    final renamedDraftPaths = <String>{};

    for (final removedPath in removedPaths) {
      final replacementPath = addedPaths.cast<String?>().firstWhere(
        (candidate) =>
            candidate != null &&
            !renamedDraftPaths.contains(candidate) &&
            remote[removedPath]!.canonical == draft[candidate]!.canonical,
        orElse: () => null,
      );
      if (replacementPath != null) {
        renamedRemotePaths.add(removedPath);
        renamedDraftPaths.add(replacementPath);
        changes.add(
          SchemaChange(
            kind: SchemaChangeKind.renamed,
            subject: 'storage',
            path: replacementPath,
            previousPath: removedPath,
          ),
        );
        diagnostics.add(
          _storageDiagnostic(
            code: 'storage.renamed-path',
            path: removedPath,
            message:
                'Storage path $removedPath was renamed to $replacementPath.',
          ),
        );
      }
    }

    for (final path in removedPaths) {
      changes.add(
        SchemaChange(
          kind: SchemaChangeKind.removed,
          subject: 'storage',
          path: path,
        ),
      );
      diagnostics.add(
        _storageDiagnostic(
          code: 'storage.removed-path',
          path: path,
          message: 'Storage path $path was removed.',
        ),
      );
    }
    for (final path in addedPaths) {
      changes.add(
        SchemaChange(
          kind: SchemaChangeKind.added,
          subject: 'storage',
          path: path,
        ),
      );
    }

    for (final path in remote.keys.where(draft.containsKey)) {
      final previous = remote[path]!;
      final current = draft[path]!;
      if (previous.canonical == current.canonical) {
        continue;
      }
      changes.add(
        SchemaChange(
          kind: SchemaChangeKind.modified,
          subject: 'storage',
          path: path,
        ),
      );
      if (previous.node.kind != current.node.kind) {
        diagnostics.add(
          _storageDiagnostic(
            code: 'storage.kind-changed',
            path: path,
            message:
                'Storage path $path changed from ${previous.node.kind.name} to ${current.node.kind.name}.',
          ),
        );
      }
      if (previous.constraints != current.constraints) {
        diagnostics.add(
          _storageDiagnostic(
            code: 'storage.constraint-changed',
            path: path,
            message: 'Storage constraints changed at $path.',
          ),
        );
      }
      if (previous.node.required != true && current.node.required == true) {
        diagnostics.add(
          Diagnostic(
            code: 'storage.optional-to-required',
            message: 'Storage path $path changed from optional to required.',
            severity: DiagnosticSeverity.advisory,
            location: DiagnosticLocation(section: 'storage', path: path),
          ),
        );
      }
    }
  }

  void _compareRules(
    Map<String, _RuleEntry> remote,
    Map<String, _RuleEntry> draft, {
    required List<SchemaChange> changes,
    required List<Diagnostic> diagnostics,
  }) {
    for (final key in remote.keys.where((key) => !draft.containsKey(key))) {
      changes.add(
        SchemaChange(
          kind: SchemaChangeKind.removed,
          subject: 'rule',
          path: key,
        ),
      );
    }
    for (final key in draft.keys.where((key) => !remote.containsKey(key))) {
      changes.add(
        SchemaChange(kind: SchemaChangeKind.added, subject: 'rule', path: key),
      );
    }
    for (final key in remote.keys.where(draft.containsKey)) {
      final previous = remote[key]!;
      final current = draft[key]!;
      if (previous.access == current.access) {
        continue;
      }
      changes.add(
        SchemaChange(
          kind: SchemaChangeKind.modified,
          subject: 'rule',
          path: key,
        ),
      );
      if (previous.access == ViewAccess.readWrite &&
          current.access == ViewAccess.read) {
        diagnostics.add(
          Diagnostic(
            code: 'view.reduced-access',
            message:
                'View ${current.viewName} no longer grants write access for ${current.request}.',
            severity: DiagnosticSeverity.blocker,
            location: DiagnosticLocation(
              section: 'views',
              viewName: current.viewName,
            ),
          ),
        );
      }
    }
  }

  Map<String, _StorageEntry> _flattenStorage(StorageNode root) {
    final entries = <String, _StorageEntry>{};
    void visit(String path, StorageNode node) {
      if (path.isNotEmpty) {
        entries[path] = _StorageEntry(node);
      }
      final childNames = node.children.keys.toList()..sort();
      for (final childName in childNames) {
        visit(
          path.isEmpty ? childName : '$path.$childName',
          node.children[childName]!,
        );
      }
      if (node.items != null) {
        visit('$path[]', node.items!);
      }
    }

    visit('', root);
    return entries;
  }

  Map<String, _RuleEntry> _flattenRules(List<ConfdbView> views) {
    final entries = <String, _RuleEntry>{};
    for (final view in views) {
      for (final rule in view.rules) {
        final entry = _RuleEntry(view.name, rule);
        entries[entry.key] = entry;
      }
    }
    return entries;
  }

  String _buildSourceDiff(
    Map<String, _StorageEntry> remoteStorage,
    Map<String, _StorageEntry> draftStorage,
    Map<String, _RuleEntry> remoteRules,
    Map<String, _RuleEntry> draftRules,
  ) {
    final remoteLines = _sourceLines(remoteStorage, remoteRules);
    final draftLines = _sourceLines(draftStorage, draftRules);
    final removed = remoteLines.difference(draftLines).toList()..sort();
    final added = draftLines.difference(remoteLines).toList()..sort();
    if (removed.isEmpty && added.isEmpty) {
      return '--- remote\n+++ draft\n';
    }
    return '${[
      '--- remote',
      '+++ draft',
      '@@ schema @@',
      ...removed.map((line) => '- $line'),
      ...added.map((line) => '+ $line'),
    ].join('\n')}\n';
  }

  Set<String> _sourceLines(
    Map<String, _StorageEntry> storage,
    Map<String, _RuleEntry> rules,
  ) => {
    for (final entry in storage.entries)
      'storage ${entry.key}: ${entry.value.canonical}',
    for (final entry in rules.entries) 'view ${entry.value.canonical}',
  };

  Diagnostic _storageDiagnostic({
    required String code,
    required String path,
    required String message,
  }) => Diagnostic(
    code: code,
    message: message,
    severity: DiagnosticSeverity.blocker,
    location: DiagnosticLocation(section: 'storage', path: path),
  );

  String _changeKey(SchemaChange change) =>
      '${change.subject}|${change.path}|${change.kind.name}';

  String _diagnosticKey(Diagnostic diagnostic) =>
      '${diagnostic.code}|${diagnostic.location?.path ?? ''}|${diagnostic.location?.viewName ?? ''}';
}

class _StorageEntry {
  const _StorageEntry(this.node);

  final StorageNode node;

  String get canonical =>
      jsonEncode({'kind': node.kind.name, 'constraints': constraints});

  Map<String, Object?> get constraints => {
    if (node.alias != null) 'alias': node.alias,
    if (node.pattern != null) 'pattern': node.pattern,
    if (node.choices.isNotEmpty)
      'choices': (node.choices.map(jsonEncode).toList()..sort()),
    if (node.minimum != null) 'minimum': node.minimum,
    if (node.maximum != null) 'maximum': node.maximum,
    if (node.visibility != null) 'visibility': node.visibility!.name,
    if (node.ephemeral != null) 'ephemeral': node.ephemeral,
    if (node.required != null) 'required': node.required,
    if (node.uniqueItems != null) 'unique-items': node.uniqueItems,
  };
}

class _RuleEntry {
  const _RuleEntry(this.viewName, this.rule);

  final String viewName;
  final ConfdbRule rule;

  String get request => rule.request.toString();
  String get storage => rule.storage.toString();
  ViewAccess get access => rule.access;
  String get key => '$viewName|$request|$storage';
  String get canonical => '$viewName: $request -> $storage (${access.name})';
}
