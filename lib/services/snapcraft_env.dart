import 'host_env.dart';

class SnapcraftEnvironment {
  const SnapcraftEnvironment();

  Map<String, String> build([Map<String, String>? hostEnvironment]) {
    final environment = Map<String, String>.from(
      sanitizedHostEnvironment(hostEnvironment),
    );
    environment.remove('SNAPCRAFT_STORE_AUTH');
    return Map.unmodifiable(environment);
  }
}
