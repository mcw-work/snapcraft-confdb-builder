import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/diagnostic.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/models/view_rule.dart';
import 'package:snapcraft_confdb_builder/services/schema_diff_service.dart';

void main() {
  const service = SchemaDiffService();

  test('produces a stable unified diff for equivalent map order', () {
    final remote = schema(
      storageChildren: {
        'v1': StorageNode.map(
          children: {
            'city': StorageNode.string(),
            'country': StorageNode.string(),
          },
        ),
      },
    );
    final draft = schema(
      storageChildren: {
        'v1': StorageNode.map(
          children: {
            'country': StorageNode.string(),
            'city': StorageNode.string(),
          },
        ),
      },
    );

    final comparison = service.compare(remote: remote, draft: draft);

    expect(comparison.changes, isEmpty);
    expect(comparison.diagnostics, isEmpty);
    expect(comparison.sourceDiff, '--- remote\n+++ draft\n');
  });

  test('reports removed and renamed storage paths', () {
    final remote = schema(
      storageChildren: {
        'v1': StorageNode.map(children: {'city': StorageNode.string()}),
      },
    );
    final draft = schema(
      storageChildren: {
        'v1': StorageNode.map(children: {'location': StorageNode.string()}),
      },
    );

    final comparison = service.compare(remote: remote, draft: draft);

    expect(
      comparison.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll(['storage.removed-path', 'storage.renamed-path']),
    );
    expect(
      comparison.diagnostics
          .where((diagnostic) => diagnostic.code == 'storage.removed-path')
          .single
          .location
          ?.path,
      'v1.city',
    );
    expect(comparison.sourceDiff, contains('- storage v1.city'));
    expect(comparison.sourceDiff, contains('+ storage v1.location'));
  });

  test('reports storage compatibility changes and required advisories', () {
    final remote = schema(
      storageChildren: {
        'v1': StorageNode.map(
          children: {'limit': StorageNode.integer(minimum: 0)},
        ),
      },
    );
    final draft = schema(
      storageChildren: {
        'v1': StorageNode.map(
          children: {'limit': StorageNode.string(required: true)},
        ),
      },
    );

    final comparison = service.compare(remote: remote, draft: draft);

    expect(
      comparison.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll([
        'storage.kind-changed',
        'storage.constraint-changed',
        'storage.optional-to-required',
      ]),
    );
    expect(
      comparison.diagnostics
          .firstWhere(
            (diagnostic) => diagnostic.code == 'storage.optional-to-required',
          )
          .severity,
      DiagnosticSeverity.advisory,
    );
  });

  test('reports reduced view access', () {
    final remote = schema(
      rules: [
        ConfdbRule(
          request: ConfdbPath.parse('weather.{key}'),
          storage: ConfdbPath.parse('v1.{key}'),
          access: ViewAccess.readWrite,
        ),
      ],
    );
    final draft = schema(
      rules: [
        ConfdbRule(
          request: ConfdbPath.parse('weather.{key}'),
          storage: ConfdbPath.parse('v1.{key}'),
          access: ViewAccess.read,
        ),
      ],
    );

    final comparison = service.compare(remote: remote, draft: draft);

    expect(
      comparison.diagnostics.map((diagnostic) => diagnostic.code),
      contains('view.reduced-access'),
    );
  });
}

ConfdbSchemaDocument schema({
  Map<String, StorageNode>? storageChildren,
  Iterable<ConfdbRule> rules = const [],
}) => ConfdbSchemaDocument(
  accountId: 'brand-id',
  name: 'weather',
  summary: 'Weather settings',
  storage: StorageNode.map(
    children: storageChildren ?? {'v1': StorageNode.map()},
  ),
  views: [ConfdbView(name: 'admin', rules: rules)],
);
