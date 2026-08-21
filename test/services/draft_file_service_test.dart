import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/services/draft_file_service.dart';

void main() {
  late _FakeDraftPreferences preferences;
  late DraftFileService service;
  late Directory temporaryDirectory;

  setUp(() async {
    preferences = _FakeDraftPreferences();
    service = DraftFileService(preferences: preferences);
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'draft-file-service-',
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('writes UTF-8 YAML and persists the selected directory', () async {
    final path = '${temporaryDirectory.path}/schema.yaml';
    final document = _document(summary: 'Grüße, München');

    await service.write(document, path);

    expect(
      await File(path).readAsString(),
      contains('summary: "Grüße, München"'),
    );
    expect(preferences.lastDirectory, temporaryDirectory.path);
  });

  test('reads UTF-8 YAML and persists the source directory', () async {
    final path = '${temporaryDirectory.path}/schema.yaml';
    await File(path).writeAsString('''
type: confdb-schema
account-id: brand
name: weather
summary: "Grüße, München"
body: |-
  {"storage":{}}
''');

    final document = await service.read(path);

    expect(document.accountId, 'brand');
    expect(document.name, 'weather');
    expect(document.summary, 'Grüße, München');
    expect(preferences.lastDirectory, temporaryDirectory.path);
  });
}

ConfdbSchemaDocument _document({required String summary}) {
  return ConfdbSchemaDocument(
    accountId: 'brand',
    name: 'weather',
    summary: summary,
    storage: StorageNode.map(),
  );
}

class _FakeDraftPreferences implements DraftPreferences {
  String? lastDirectory;

  @override
  Future<String?> readLastDirectory() async => lastDirectory;

  @override
  Future<void> writeLastDirectory(String directory) async {
    lastDirectory = directory;
  }
}
