import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/services/key_service.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

import '../support/fake_terminal_runner.dart';

void main() {
  late FakeTerminalRunner runner;
  late KeyService service;

  setUp(() {
    runner = FakeTerminalRunner();
    service = KeyService(runner: runner);
  });

  test('combines local keys with registered Snapcraft fingerprints', () async {
    runner
      ..enqueue(
        const CommandResult.ok(
          stdout: 'Name          SHA3-384\ndefault       local-fingerprint\n',
        ),
      )
      ..enqueue(
        const CommandResult.ok(
          stdout: 'Name          SHA3-384\ndefault       local-fingerprint\n',
        ),
      );

    final keys = await service.listKeys();

    expect(runner.calls.map((call) => call.executable), ['snap', 'snapcraft']);
    expect(runner.calls.map((call) => call.arguments), [
      ['keys'],
      ['keys'],
    ]);
    expect(keys, [const SigningKey(name: 'default', fingerprint: 'local-fingerprint', isRegistered: true)]);
  });

  test('returns local keys when registered-key lookup fails', () async {
    runner
      ..enqueue(
        const CommandResult.ok(
          stdout: 'Name          SHA3-384\ndefault       local-fingerprint\n',
        ),
      )
      ..enqueue(const CommandResult(exitCode: 1, stderr: 'not logged in'));

    final keys = await service.listKeys();

    expect(keys.single.isRegistered, isFalse);
  });
}