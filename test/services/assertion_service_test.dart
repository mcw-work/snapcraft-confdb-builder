import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/command_task.dart';
import 'package:snapcraft_confdb_builder/services/assertion_service.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

import '../support/fake_terminal_runner.dart';

void main() {
  late FakeTerminalRunner runner;
  late AssertionService service;
  late Directory temporaryDirectory;

  setUp(() async {
    runner = FakeTerminalRunner();
    service = AssertionService(runner: runner);
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'assertion-service-',
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test(
    'signs an unsigned assertion and saves it only at the selected path',
    () async {
      final savedPath = '${temporaryDirectory.path}/schema.assert';
      const signedAssertion =
          'type: confdb-schema\naccount-id: brand\n\nAXNpZ25hdHVyZQ==\n';
      runner.enqueue(const CommandResult.ok(stdout: signedAssertion));

      final result = await service.sign(
        keyName: 'developer-key',
        unsignedAssertion: 'type: confdb-schema\naccount-id: brand\n',
        savedPath: savedPath,
      );

      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.executable, 'snap');
      expect(runner.calls.single.arguments, ['sign', '-k', 'developer-key']);
      expect(
        runner.calls.single.stdin,
        'type: confdb-schema\naccount-id: brand\n',
      );
      expect(result.artifact.keyName, 'developer-key');
      expect(result.artifact.signedAssertion, signedAssertion);
      expect(result.artifact.savedPath, savedPath);
      expect(result.task.kind, CommandTaskKind.sign);
      expect(result.task.status, CommandTaskStatus.succeeded);
      expect(await File(savedPath).readAsString(), signedAssertion);
      expect(await temporaryDirectory.list().length, 1);
    },
  );

  test('does not save an invalid signed assertion', () async {
    final savedPath = '${temporaryDirectory.path}/schema.assert';
    runner.enqueue(
      const CommandResult.ok(stdout: 'type: model\n\nsignature\n'),
    );

    await expectLater(
      service.sign(
        keyName: 'developer-key',
        unsignedAssertion: 'type: confdb-schema\n',
        savedPath: savedPath,
      ),
      throwsA(
        isA<AssertionServiceException>().having(
          (error) => error.code,
          'code',
          'assertion.invalid-signed-output',
        ),
      ),
    );

    expect(await File(savedPath).exists(), isFalse);
  });

  test(
    'returns a separate acknowledgement task without changing a signed file',
    () async {
      final savedFile = File('${temporaryDirectory.path}/schema.assert');
      await savedFile.writeAsString('signed assertion');
      runner.enqueue(const CommandResult.ok(stdout: 'acknowledged'));

      final result = await service.acknowledge(savedFile.path);

      expect(runner.calls.single.executable, 'snap');
      expect(runner.calls.single.arguments, ['ack', savedFile.path]);
      expect(result.task.kind, CommandTaskKind.ack);
      expect(result.task.status, CommandTaskStatus.succeeded);
      expect(await savedFile.readAsString(), 'signed assertion');
    },
  );

  test(
    'returns a failed acknowledgement task without changing a signed file',
    () async {
      final savedFile = File('${temporaryDirectory.path}/schema.assert');
      await savedFile.writeAsString('signed assertion');
      runner.enqueue(const CommandResult(exitCode: 1, stderr: 'not trusted'));

      final result = await service.acknowledge(savedFile.path);

      expect(result.task.status, CommandTaskStatus.failed);
      expect(result.task.stderr, 'not trusted');
      expect(await savedFile.readAsString(), 'signed assertion');
    },
  );
}
