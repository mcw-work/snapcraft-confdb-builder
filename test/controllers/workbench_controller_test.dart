import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/controllers/workbench_controller.dart';
import 'package:snapcraft_confdb_builder/models/command_task.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';

void main() {
  test('replaceDocument invalidates derived publishing state', () {
    final controller = WorkbenchController(
      document: _document(
        artifact: SigningArtifact(
          keyName: 'brand-key',
          signedAssertion: 'signed',
          createdAt: DateTime(2026),
        ),
      ),
    );
    controller.recordCommandTask(
      const CommandTask(
        id: 'sign-1',
        kind: CommandTaskKind.sign,
        status: CommandTaskStatus.succeeded,
        label: 'Sign ConfDB assertion',
      ),
    );
    controller.cacheCanonicalSourceFingerprint();

    controller.replaceDocument(_document());

    expect(controller.document.isDirty, isTrue);
    expect(controller.document.artifact, isNull);
    expect(controller.commandTasks, isEmpty);
    expect(controller.canonicalSourceFingerprint, isNull);
    expect(controller.diagnostics, isEmpty);
  });
}

ConfdbSchemaDocument _document({SigningArtifact? artifact}) => ConfdbSchemaDocument(
  accountId: 'brand',
  name: 'weather',
  summary: 'Weather settings',
  storage: StorageNode.map(children: {'v1': StorageNode.map()}),
  artifact: artifact,
);