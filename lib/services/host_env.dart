import 'dart:io';

const _hostToolUnsafeVariables = {
  'LD_LIBRARY_PATH',
  'GTK_PATH',
  'GIO_MODULE_DIR',
  'LIBGL_DRIVERS_PATH',
  'GDK_BACKEND',
  'LD_PRELOAD',
};

Map<String, String> sanitizedHostEnvironment([Map<String, String>? source]) {
  final environment = Map<String, String>.from(source ?? Platform.environment);
  environment.removeWhere(
    (name, _) => _hostToolUnsafeVariables.contains(name),
  );
  return Map.unmodifiable(environment);
}