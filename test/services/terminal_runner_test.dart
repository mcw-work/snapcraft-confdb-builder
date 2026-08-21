import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/services/host_env.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

void main() {
  test('sanitizes only host variables that interfere with host tools', () {
    final environment = sanitizedHostEnvironment({
      'PATH': '/usr/bin',
      'DISPLAY': ':0',
      'LD_LIBRARY_PATH': '/snap/lib',
      'GTK_PATH': '/snap/gtk',
      'GIO_MODULE_DIR': '/snap/gio',
      'LIBGL_DRIVERS_PATH': '/snap/libgl',
      'GDK_BACKEND': 'wayland',
      'LD_PRELOAD': '/snap/preload.so',
    });

    expect(environment, {'PATH': '/usr/bin', 'DISPLAY': ':0'});
  });

  test('runs a request and returns captured output', () async {
    final runner = ProcessTerminalRunner();
    final command = runner.run(
      CommandRequest(executable: 'sh', arguments: ['-c', 'printf hello']),
    );

    final result = await command.result;

    expect(result.exitCode, 0);
    expect(result.stdout, 'hello');
    expect(result.stderr, isEmpty);
    expect(result.wasCancelled, isFalse);
    expect(result.duration, isNotNull);
  });

  test('cancels a running command', () async {
    final runner = ProcessTerminalRunner();
    final command = runner.run(
      CommandRequest(executable: 'sh', arguments: ['-c', 'sleep 10']),
    );

    await command.cancel();
    final result = await command.result;

    expect(result.wasCancelled, isTrue);
  });
}