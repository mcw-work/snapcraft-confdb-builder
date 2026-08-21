import 'terminal_runner.dart';

class ToolLocator {
  ToolLocator({required this.runner});

  final TerminalRunner runner;
  int? _snapcraftMajorVersion;
  bool _hasSnapcraftVersion = false;

  Future<int?> snapcraftMajorVersion() async {
    if (_hasSnapcraftVersion) {
      return _snapcraftMajorVersion;
    }
    _hasSnapcraftVersion = true;
    final result = await runner
        .run(CommandRequest(executable: 'snapcraft', arguments: ['--version']))
        .result;
    if (!result.succeeded) {
      return null;
    }
    _snapcraftMajorVersion = _parseMajorVersion(result.stdout);
    return _snapcraftMajorVersion;
  }

  int? _parseMajorVersion(String output) {
    final match = RegExp(r'\b(\d+)(?:\.\d+)+\b').firstMatch(output);
    return match == null ? null : int.parse(match.group(1)!);
  }
}