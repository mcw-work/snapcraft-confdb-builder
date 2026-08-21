import 'host_env.dart';
import 'tool_locator.dart';

class SnapcraftEnvironment {
  const SnapcraftEnvironment({this.majorVersion});

  final int? majorVersion;

  static Future<SnapcraftEnvironment> detect(ToolLocator locator) async {
    return SnapcraftEnvironment(majorVersion: await locator.snapcraftMajorVersion());
  }

  Map<String, String> build([Map<String, String>? hostEnvironment]) {
    final environment = Map<String, String>.from(
      sanitizedHostEnvironment(hostEnvironment),
    );
    environment.remove('SNAPCRAFT_STORE_AUTH');
    if ((majorVersion ?? 0) >= 9) {
      environment['SNAPCRAFT_STORE_AUTH'] = 'candid';
    }
    return Map.unmodifiable(environment);
  }
}