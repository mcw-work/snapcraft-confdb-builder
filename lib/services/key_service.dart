import 'terminal_runner.dart';
import 'snapcraft_env.dart';

class SigningKey {
  const SigningKey({
    required this.name,
    required this.fingerprint,
    required this.isRegistered,
  });

  final String name;
  final String fingerprint;
  final bool isRegistered;

  @override
  bool operator ==(Object other) {
    return other is SigningKey &&
        other.name == name &&
        other.fingerprint == fingerprint &&
        other.isRegistered == isRegistered;
  }

  @override
  int get hashCode => Object.hash(name, fingerprint, isRegistered);
}

class KeyServiceException implements Exception {
  const KeyServiceException(this.code, this.message);

  final String code;
  final String message;
}

class KeyService {
  KeyService({
    required this.runner,
    this.snapcraftEnvironment = const SnapcraftEnvironment(),
  });

  final TerminalRunner runner;
  final SnapcraftEnvironment snapcraftEnvironment;

  Future<List<SigningKey>> listKeys() async {
    final localResult = await runner
        .run(CommandRequest(executable: 'snap', arguments: ['keys']))
        .result;
    if (!localResult.succeeded) {
      throw KeyServiceException('keys.list-failed', localResult.stderr);
    }

    final localKeys = _parseKeys(localResult.stdout);
    final registeredResult = await runner
        .run(
          CommandRequest(
            executable: 'snapcraft',
            arguments: ['keys'],
            environment: snapcraftEnvironment.build(),
          ),
        )
        .result;
    final registeredFingerprints = registeredResult.succeeded
        ? _parseKeys(registeredResult.stdout)
              .map((key) => key.fingerprint)
              .toSet()
        : <String>{};
    return localKeys
        .map(
          (key) => SigningKey(
            name: key.name,
            fingerprint: key.fingerprint,
            isRegistered: registeredFingerprints.contains(key.fingerprint),
          ),
        )
        .toList(growable: false);
  }

  List<_ParsedKey> _parseKeys(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.toLowerCase().startsWith('name'))
        .map((line) => line.split(RegExp(r'\s+')))
        .where((parts) => parts.length >= 2)
        .map((parts) => _ParsedKey(parts.first, parts.last))
        .toList(growable: false);
  }
}

class _ParsedKey {
  const _ParsedKey(this.name, this.fingerprint);

  final String name;
  final String fingerprint;
}