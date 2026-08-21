import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/command_task.dart';
import 'package:snapcraft_confdb_builder/models/diagnostic.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';

void main() {
  test('retains typed storage constraints without sharing choices', () {
    final choices = <Object?>['metric', 'imperial'];
    final node = StorageNode.array(
      items: StorageNode.string(
        pattern: r'^[a-z]+$',
        choices: choices,
        visibility: StorageVisibility.secret,
        ephemeral: true,
        required: true,
      ),
      uniqueItems: true,
    );

    choices.add('changed');

    expect(node.kind, StorageKind.array);
    expect(node.items!.pattern, r'^[a-z]+$');
    expect(node.items!.choices, ['metric', 'imperial']);
    expect(node.items!.visibility, StorageVisibility.secret);
    expect(node.items!.ephemeral, isTrue);
    expect(node.items!.required, isTrue);
    expect(node.uniqueItems, isTrue);
  });

  test('identifies blockers at a structured location', () {
    const diagnostic = Diagnostic(
      code: 'schema.storage-required',
      message: 'Storage is required.',
      severity: DiagnosticSeverity.blocker,
      location: DiagnosticLocation(section: 'storage', path: 'v1.lat'),
    );

    expect(diagnostic.isBlocker, isTrue);
    expect(diagnostic.location!.path, 'v1.lat');
  });

  test('marks completed command tasks as finished', () {
    const pending = CommandTask(
      id: 'ack-1',
      kind: CommandTaskKind.ack,
      status: CommandTaskStatus.pending,
      label: 'Acknowledge assertion',
    );
    final finished = pending.copyWith(
      status: CommandTaskStatus.succeeded,
      exitCode: 0,
    );

    expect(pending.isFinished, isFalse);
    expect(finished.isFinished, isTrue);
    expect(finished.exitCode, 0);
  });
}