import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/services/account_service.dart';
import 'package:snapcraft_confdb_builder/services/snapcraft_env.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

import '../support/fake_terminal_runner.dart';

void main() {
  late FakeTerminalRunner runner;
  late AccountService service;

  setUp(() {
    runner = FakeTerminalRunner();
    service = AccountService(
      runner: runner,
      snapcraftEnvironment: const SnapcraftEnvironment(),
    );
  });

  test('removes candid auth and parses whoami', () async {
    runner.enqueue(
      const CommandResult.ok(stdout: 'email: dev@example.com\nid: brand-id\n'),
    );

    final account = await service.currentAccount();

    expect(account.id, 'brand-id');
    expect(runner.calls.single.executable, 'snapcraft');
    expect(runner.calls.single.arguments, ['whoami']);
    expect(
      runner.calls.single.environment,
      isNot(contains('SNAPCRAFT_STORE_AUTH')),
    );
  });

  test('maps login failures to account.not-authenticated', () async {
    runner.enqueue(
      const CommandResult(exitCode: 1, stderr: 'You are not logged in.'),
    );

    await expectLater(
      service.currentAccount(),
      throwsA(
        isA<AccountServiceException>().having(
          (error) => error.code,
          'code',
          'account.not-authenticated',
        ),
      ),
    );
  });

  test('rejects a successful response without an account id', () async {
    runner.enqueue(const CommandResult.ok(stdout: 'email: dev@example.com\n'));

    await expectLater(
      service.currentAccount(),
      throwsA(
        isA<AccountServiceException>().having(
          (error) => error.code,
          'code',
          'account.invalid-response',
        ),
      ),
    );
  });
}
