import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/services/snapcraft_env.dart';

void main() {
  test('removes inherited Snapcraft store credentials', () {
    const environment = SnapcraftEnvironment();

    final result = environment.build({
      'HOME': '/home/dev',
      'SNAPCRAFT_STORE_AUTH': 'candid',
    });

    expect(result['HOME'], '/home/dev');
    expect(result, isNot(contains('SNAPCRAFT_STORE_AUTH')));
  });
}
