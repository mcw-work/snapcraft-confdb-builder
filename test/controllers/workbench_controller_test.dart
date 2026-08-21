import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/controllers/workbench_controller.dart';
import 'package:snapcraft_confdb_builder/models/command_task.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/services/assertion_service.dart';
import 'package:snapcraft_confdb_builder/services/confdb_assertion_builder.dart';
import 'package:snapcraft_confdb_builder/services/draft_file_service.dart';
import 'package:snapcraft_confdb_builder/services/store_schema_service.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

import '../support/fake_terminal_runner.dart';

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

  test('failed acknowledgement does not disable a current publish gate', () async {
    final storeRunner = FakeTerminalRunner()
      ..enqueue(const CommandResult.ok(stdout: _remoteSource));
    final acknowledgementRunner = FakeTerminalRunner()
      ..enqueue(const CommandResult(exitCode: 1, stderr: 'ack failed'));
    final controller = WorkbenchController(
      document: _document(
        artifact: SigningArtifact(
          keyName: 'brand-key',
          signedAssertion: 'signed',
          savedPath: '/tmp/weather.assert',
          createdAt: DateTime(2026),
        ),
      ),
      storeSchemaService: StoreSchemaService(runner: storeRunner),
      assertionService: AssertionService(runner: acknowledgementRunner),
    );
    controller.selectKey('brand-key');

    await controller.refreshPreflight();
    expect(controller.canPublish, isTrue);

    await controller.acknowledgeArtifact();

    expect(controller.canPublish, isTrue);
    expect(controller.commandTasks.last.kind, CommandTaskKind.ack);
    expect(controller.commandTasks.last.status, CommandTaskStatus.failed);
  });

  test('new-schema preflight permits publication with a selected key', () async {
    final runner = FakeTerminalRunner()
      ..enqueue(const CommandResult(exitCode: 1, stderr: 'no assertions found'));
    final controller = WorkbenchController(
      document: _document(),
      storeSchemaService: StoreSchemaService(runner: runner),
    );
    controller.selectKey('brand-key');

    await controller.refreshPreflight();

    expect(controller.preflightCurrent, isTrue);
    expect(controller.preflightRemote, isNull);
    expect(controller.canPublish, isTrue);
  });

  test('signs the canonical assertion and saves a draft through injected services', () async {
    final signedPath = '${Directory.systemTemp.path}/confdb-builder-test.assert';
    final draftPath = '${Directory.systemTemp.path}/confdb-builder-test.yaml';
    addTearDown(() async {
      final signedFile = File(signedPath);
      if (await signedFile.exists()) {
        await signedFile.delete();
      }
      final draftFile = File(draftPath);
      if (await draftFile.exists()) {
        await draftFile.delete();
      }
    });
    final signingRunner = FakeTerminalRunner()
      ..enqueue(const CommandResult.ok(stdout: 'type: confdb-schema\n\nsignature'));
    final controller = WorkbenchController(
      document: _document(),
      assertionBuilder: const ConfdbAssertionBuilder(),
      assertionService: AssertionService(runner: signingRunner),
      draftFileService: DraftFileService(preferences: _MemoryPreferences()),
    );
    controller.selectKey('brand-key');

    await controller.signArtifact(savedPath: signedPath);
    await controller.saveDraft(draftPath);

    expect(controller.document.artifact!.savedPath, signedPath);
    expect(signingRunner.calls.single.stdin, controller.canonicalUnsignedAssertion);
    expect(File(draftPath).existsSync(), isTrue);
  });
}

class _MemoryPreferences implements DraftPreferences {
  @override
  Future<String?> readLastDirectory() async => null;

  @override
  Future<void> writeLastDirectory(String directory) async {}
}

ConfdbSchemaDocument _document({SigningArtifact? artifact}) => ConfdbSchemaDocument(
  accountId: 'brand',
  name: 'weather',
  summary: 'Weather settings',
  storage: StorageNode.map(children: {'v1': StorageNode.map()}),
  artifact: artifact,
);

const _remoteSource = '''
type: confdb-schema
account-id: brand
name: weather
summary: Weather settings
body: |-
  {
    "storage": {
      "v1": {
        "type": "map",
        "schema": {}
      }
    }
  }
''';