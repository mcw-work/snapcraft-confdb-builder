import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'host_env.dart';

class CommandRequest {
  CommandRequest({
    required this.executable,
    List<String> arguments = const [],
    this.stdin,
    Map<String, String>? environment,
    this.workingDirectory,
    this.timeout,
  })  : arguments = List.unmodifiable(arguments),
        environment = Map.unmodifiable(environment ?? const {});

  final String executable;
  final List<String> arguments;
  final String? stdin;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration? timeout;
}

class CommandResult {
  const CommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.wasCancelled = false,
    this.duration = Duration.zero,
  });

  const CommandResult.ok({
    this.stdout = '',
    this.stderr = '',
    this.duration = Duration.zero,
  }) : exitCode = 0,
       wasCancelled = false;

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool wasCancelled;
  final Duration duration;

  bool get succeeded => exitCode == 0 && !wasCancelled;

  CommandResult copyWith({
    int? exitCode,
    String? stdout,
    String? stderr,
    bool? wasCancelled,
    Duration? duration,
  }) {
    return CommandResult(
      exitCode: exitCode ?? this.exitCode,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      wasCancelled: wasCancelled ?? this.wasCancelled,
      duration: duration ?? this.duration,
    );
  }
}

abstract interface class TerminalRunner {
  RunningCommand run(CommandRequest request);
}

abstract interface class RunningCommand {
  Future<CommandResult> get result;

  Future<void> cancel();
}

class ProcessTerminalRunner implements TerminalRunner {
  @override
  RunningCommand run(CommandRequest request) {
    final startedAt = Stopwatch()..start();
    final process = Process.start(
      request.executable,
      request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment.isEmpty
          ? sanitizedHostEnvironment()
          : request.environment,
    );
    return _ProcessRunningCommand(process, request, startedAt);
  }
}

class _ProcessRunningCommand implements RunningCommand {
  _ProcessRunningCommand(this._process, this._request, this._stopwatch)
    : _result = Completer<CommandResult>();

  final Future<Process> _process;
  final CommandRequest _request;
  final Stopwatch _stopwatch;
  final Completer<CommandResult> _result;
  Process? _startedProcess;
  bool _wasCancelled = false;
  bool _hasStarted = false;

  @override
  Future<CommandResult> get result {
    _start();
    return _result.future;
  }

  @override
  Future<void> cancel() async {
    _wasCancelled = true;
    final process = await _process;
    _startedProcess = process;
    process.kill();
  }

  void _start() {
    if (_hasStarted) {
      return;
    }
    _hasStarted = true;
    unawaited(_collectResult());
  }

  Future<void> _collectResult() async {
    try {
      final process = await _process;
      _startedProcess = process;
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final timeout = _request.timeout;
      final timer = timeout == null
          ? null
          : Timer(timeout, () => _startedProcess?.kill());
      final exitCode = await process.exitCode;
      timer?.cancel();
      _stopwatch.stop();
      _result.complete(
        CommandResult(
          exitCode: exitCode,
          stdout: await stdout,
          stderr: await stderr,
          wasCancelled: _wasCancelled,
          duration: _stopwatch.elapsed,
        ),
      );
    } on ProcessException catch (error) {
      _stopwatch.stop();
      _result.complete(
        CommandResult(
          exitCode: 127,
          stderr: error.message,
          wasCancelled: _wasCancelled,
          duration: _stopwatch.elapsed,
        ),
      );
    }
  }
}