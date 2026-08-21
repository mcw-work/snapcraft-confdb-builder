import 'dart:collection';

import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

class FakeTerminalRunner implements TerminalRunner {
  final Queue<CommandResult> _results = Queue<CommandResult>();
  final List<CommandRequest> calls = [];

  void enqueue(CommandResult result) => _results.add(result);

  @override
  RunningCommand run(CommandRequest request) {
    calls.add(request);
    if (_results.isEmpty) {
      throw StateError('No result was queued for ${request.executable}.');
    }
    return FakeRunningCommand(_results.removeFirst());
  }
}

class FakeRunningCommand implements RunningCommand {
  FakeRunningCommand(this._result);

  CommandResult _result;

  @override
  Future<void> cancel() async {
    _result = _result.copyWith(wasCancelled: true);
  }

  @override
  Future<CommandResult> get result async => _result;
}