import 'snapcraft_env.dart';
import 'terminal_runner.dart';

class SnapcraftAccount {
  const SnapcraftAccount({required this.id, this.email});

  final String id;
  final String? email;
}

class AccountServiceException implements Exception {
  const AccountServiceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class AccountService {
  AccountService({
    required this.runner,
    required this.snapcraftEnvironment,
  });

  final TerminalRunner runner;
  final SnapcraftEnvironment snapcraftEnvironment;

  Future<SnapcraftAccount> currentAccount() async {
    final result = await runner
        .run(
          CommandRequest(
            executable: 'snapcraft',
            arguments: ['whoami'],
            environment: snapcraftEnvironment.build(),
          ),
        )
        .result;
    if (!result.succeeded) {
      final message = '${result.stdout}\n${result.stderr}'.toLowerCase();
      if (RegExp(r'not\s+(logged in|authenticated)|login|authenticat')
          .hasMatch(message)) {
        throw const AccountServiceException(
          'account.not-authenticated',
          'Snapcraft is not authenticated.',
        );
      }
      throw AccountServiceException('account.command-failed', result.stderr);
    }

    final values = _parseFields(result.stdout);
    final id = values['id'];
    if (id == null || id.isEmpty) {
      throw const AccountServiceException(
        'account.invalid-response',
        'Snapcraft did not return an account id.',
      );
    }
    return SnapcraftAccount(id: id, email: values['email']);
  }

  Map<String, String> _parseFields(String output) {
    final fields = <String, String>{};
    for (final line in output.split('\n')) {
      final match = RegExp(r'^\s*([^:]+):\s*(.*?)\s*$').firstMatch(line);
      if (match != null) {
        fields[match.group(1)!.trim().toLowerCase()] = match.group(2)!;
      }
    }
    return fields;
  }
}