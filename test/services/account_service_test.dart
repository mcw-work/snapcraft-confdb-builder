import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/services/account_service.dart';
import 'package:snapcraft_confdb_builder/services/snapcraft_env.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';
import 'package:snapcraft_confdb_builder/services/tool_locator.dart';

import '../support/fake_terminal_runner.dart';

void main() {
  late FakeTerminalRunner runner;
  late AccountService service;

  setUp(() {
    runner = FakeTerminalRunner();
    service = AccountService(
      runner: runner,
      snapcraftEnvironment: const SnapcraftEnvironment(majorVersion: 9),
    );
  });

  test('uses candid auth for Snapcraft 9 and parses whoami', () async {
    runner.enqueue(
      const CommandResult.ok(
        stdout: 'email: dev@example.com\nid: brand-id\n',
      ),
    );

    final account = await service.currentAccount();

    expect(account.id, 'brand-id');
    expect(runner.calls.single.executable, 'snapcraft');
    expect(runner.calls.single.arguments, ['whoami']);
    expect(
      runner.calls.single.environment['SNAPCRAFT_STORE_AUTH'],
      'candid',
    );
  });

  test('does not set candid auth before Snapcraft 9', () async {
    runner.enqueue(const CommandResult.ok(stdout: 'id: brand-id\n'));
    service = AccountService(
      runner: runner,
      snapcraftEnvironment: const SnapcraftEnvironment(majorVersion: 8),
    );

    await service.currentAccount();

    expect(runner.calls.single.environment, isNot(contains('SNAPCRAFT_STORE_AUTH')));
  });

  test('removes inherited candid auth before Snapcraft 9', () {
    const environment = SnapcraftEnvironment(majorVersion: 8);

    final values = environment.build({'SNAPCRAFT_STORE_AUTH': 'candid'});

    expect(values, isNot(contains('SNAPCRAFT_STORE_AUTH')));
  });

  test('caches the detected Snapcraft major version', () async {
    runner.enqueue(const CommandResult.ok(stdout: 'snapcraft 9.4.2\n'));
    final locator = ToolLocator(runner: runner);

    expect(await locator.snapcraftMajorVersion(), 9);
    expect(await locator.snapcraftMajorVersion(), 9);
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.arguments, ['--version']);
  });

  test('maps login failures to account.not-authenticated', () async {
    runner.enqueue(
      const CommandResult(exitCode: 1, stderr: 'You are not logged in.'),
    );

    await expectLater(
      service.currentAccount(),
      throwsA(
        isA<AccountServiceException>()
            .having((error) => error.code, 'code', 'account.not-authenticated'),
      ),
    );
  });

  test('rejects a successful response without an account id', () async {
    runner.enqueue(const CommandResult.ok(stdout: 'email: dev@example.com\n'));

    await expectLater(
      service.currentAccount(),
      throwsA(
        isA<AccountServiceException>()
            .having((error) => error.code, 'code', 'account.invalid-response'),
      ),
    );
  });
}