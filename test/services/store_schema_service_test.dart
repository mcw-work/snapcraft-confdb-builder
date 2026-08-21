import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/command_task.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/services/snapcraft_env.dart';
import 'package:snapcraft_confdb_builder/services/store_schema_service.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

import '../support/fake_terminal_runner.dart';

void main() {
  late FakeTerminalRunner runner;
  late StoreSchemaService service;

  setUp(() {
    runner = FakeTerminalRunner();
    service = StoreSchemaService(runner: runner);
  });

  test('inventories JSON schema rows with the current Snapcraft command', () async {
    runner.enqueue(
      const CommandResult.ok(
        stdout:
            '[{"account-id":"brand","name":"weather","revision":"4","summary":"Weather settings"}]',
      ),
    );

    final result = await service.inventory('brand');

    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.executable, 'snapcraft');
    expect(runner.calls.single.arguments, ['confdb-schemas']);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.accountId, 'brand');
    expect(result.rows.single.name, 'weather');
    expect(result.rows.single.revision, '4');
    expect(result.rows.single.summary, 'Weather settings');
    expect(result.task.kind, CommandTaskKind.inventory);
    expect(result.task.status, CommandTaskStatus.succeeded);
    expect(result.diagnostics, isEmpty);
  });

  test('falls back only when the current inventory command is unknown', () async {
    runner.enqueue(
      const CommandResult(exitCode: 2, stderr: 'error: unknown command "confdb-schemas"'),
    );
    runner.enqueue(const CommandResult.ok(stdout: 'brand weather 4 Weather settings\n'));

    final result = await service.inventory('brand');

    expect(
      runner.calls.map((call) => call.arguments),
      [
        ['confdb-schemas'],
        ['list-confdb-schemas'],
      ],
    );
    expect(result.rows.single.name, 'weather');
  });

  test('parses all rows in the current Snapcraft table inventory', () async {
    runner.enqueue(const CommandResult.ok(stdout: _tableInventory));

    final result = await service.inventory('bpyPt7Qr2Qbui3MJMgyzZ3WaQkyj6OkU');

    expect(runner.calls.single.arguments, ['confdb-schemas']);
    expect(
      result.rows.map((row) => (row.accountId, row.name, row.revision)),
      [
        ('bpyPt7Qr2Qbui3MJMgyzZ3WaQkyj6OkU', 'landscape-client', '2'),
        ('bpyPt7Qr2Qbui3MJMgyzZ3WaQkyj6OkU', 'weather', '3'),
      ],
    );
  });

  test('does not fall back when inventory fails to authenticate', () async {
    runner.enqueue(const CommandResult(exitCode: 1, stderr: 'not authenticated'));

    final result = await service.inventory('brand');

    expect(runner.calls, hasLength(1));
    expect(result.rows, isEmpty);
    expect(result.task.status, CommandTaskStatus.failed);
  });

  test('reports a blocker when inventory rows cannot be parsed', () async {
    runner.enqueue(const CommandResult.ok(stdout: '[{"name": 1}]'));

    final result = await service.inventory('brand');

    expect(result.rows, isEmpty);
    expect(result.diagnostics.single.code, 'store.inventory-unparseable');
    expect(result.diagnostics.single.isBlocker, isTrue);
  });

  test('fetches and parses a remote schema with exact snap arguments', () async {
    runner.enqueue(const CommandResult.ok(stdout: _source));

    final result = await service.fetchRemote(accountId: 'brand', name: 'weather');

    expect(runner.calls.single.executable, 'snap');
    expect(
      runner.calls.single.arguments,
      [
        'known',
        '--remote',
        'confdb-schema',
        'account-id=brand',
        'name=weather',
      ],
    );
    expect(result.document.name, 'weather');
    expect(result.task.kind, CommandTaskKind.fetchRemote);
  });

  test('fetches remote schemas with the sanitized Snapcraft environment', () async {
    runner.enqueue(const CommandResult.ok(stdout: _source));
    service = StoreSchemaService(
      runner: runner,
      snapcraftEnvironment: const _FixedSnapcraftEnvironment(),
    );

    await service.fetchRemote(accountId: 'brand', name: 'weather');

    expect(runner.calls.single.environment, {'HOME': '/home/dev'});
  });

  test('preflight fetches the remote schema and compares it to the draft', () async {
    runner.enqueue(const CommandResult.ok(stdout: _source));
    final draft = ConfdbSchemaDocument(
      accountId: 'brand',
      name: 'weather',
      summary: 'Weather settings',
      storage: StorageNode.map(),
    );

    final result = await service.preflight(draft);

    expect(result.remote!.name, 'weather');
    expect(result.comparison!.hasChanges, isFalse);
    expect(result.task.kind, CommandTaskKind.fetchRemote);
  });

  test('preflight treats a missing remote schema as a new schema', () async {
    runner.enqueue(const CommandResult(exitCode: 1, stderr: 'no assertions found'));
    final draft = ConfdbSchemaDocument(
      accountId: 'brand',
      name: 'weather',
      summary: 'Weather settings',
      storage: StorageNode.map(),
    );

    final result = await service.preflight(draft);

    expect(result.isNewSchema, isTrue);
    expect(result.remote, isNull);
    expect(result.comparison, isNull);
  });
}

const _source = '''
type: confdb-schema
account-id: brand
name: weather
summary: Weather settings
revision: 4
body: |-
  {
    "storage": {}
  }
''';

const _tableInventory = '''
Account ID                         Name              Revision  When
bpyPt7Qr2Qbui3MJMgyzZ3WaQkyj6OkU  landscape-client  2         2026-08-20T10:00:00Z
bpyPt7Qr2Qbui3MJMgyzZ3WaQkyj6OkU  weather           3         2026-08-21T10:00:00Z
''';

class _FixedSnapcraftEnvironment extends SnapcraftEnvironment {
  const _FixedSnapcraftEnvironment();

  @override
  Map<String, String> build([Map<String, String>? hostEnvironment]) => const {
    'HOME': '/home/dev',
  };
}