import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/command_task.dart';
import 'package:snapcraft_confdb_builder/services/editor_bridge.dart';
import 'package:snapcraft_confdb_builder/services/terminal_runner.dart';

import '../support/fake_terminal_runner.dart';

void main() {
  late _InspectingTerminalRunner runner;
  late Directory temporaryDirectory;
  late EditorBridge bridge;

  setUp(() async {
    runner = _InspectingTerminalRunner();
    temporaryDirectory = await Directory.systemTemp.createTemp('editor-bridge-');
    bridge = EditorBridge(runner: runner, temporaryParent: temporaryDirectory);
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('publishes through a source-copying editor script and removes temp files', () async {
    runner.enqueue(const CommandResult.ok(stdout: 'published'));

    final result = await bridge.publish(
      keyName: 'developer-key',
      accountId: 'brand',
      name: 'weather',
      source: 'type: confdb-schema\nname: weather\n',
    );

    expect(runner.calls, hasLength(1));
    final request = runner.calls.single;
    expect(request.executable, 'snapcraft');
    expect(
      request.arguments,
      ['edit-confdb-schema', '--key-name', 'developer-key', 'brand', 'weather'],
    );
    expect(request.environment['CONFDB_EDITOR_SOURCE'], isNotEmpty);
    expect(request.environment['EDITOR'], isNotEmpty);
    expect(runner.source, 'type: confdb-schema\nname: weather\n');
    expect(
      runner.script,
      '#!/bin/sh\ncp "\$CONFDB_EDITOR_SOURCE" "\$1"\n',
    );
    expect(runner.scriptMode, 0x1c0);
    expect(result.task.kind, CommandTaskKind.publish);
    expect(result.task.status, CommandTaskStatus.succeeded);
    expect(await temporaryDirectory.list().isEmpty, isTrue);
  });

  test('cleans its temporary directory when publishing fails', () async {
    runner.enqueue(const CommandResult(exitCode: 1, stderr: 'upload failed'));

    final result = await bridge.publish(
      keyName: 'developer-key',
      accountId: 'brand',
      name: 'weather',
      source: 'source',
    );

    expect(result.task.status, CommandTaskStatus.failed);
    expect(await temporaryDirectory.list().isEmpty, isTrue);
  });

  test('cleans its temporary directory after publishing is cancelled', () async {
    runner.enqueue(const CommandResult(exitCode: 130, wasCancelled: true));

    final result = await bridge.publish(
      keyName: 'developer-key',
      accountId: 'brand',
      name: 'weather',
      source: 'source',
    );

    expect(result.task.status, CommandTaskStatus.cancelled);
    expect(await temporaryDirectory.list().isEmpty, isTrue);
  });

  test('cleans its temporary directory when a timeout is requested', () async {
    runner.enqueue(const CommandResult(exitCode: 137, stderr: 'timed out'));

    await bridge.publish(
      keyName: 'developer-key',
      accountId: 'brand',
      name: 'weather',
      source: 'source',
      timeout: const Duration(seconds: 1),
    );

    expect(runner.calls.single.timeout, const Duration(seconds: 1));
    expect(await temporaryDirectory.list().isEmpty, isTrue);
  });
}

class _InspectingTerminalRunner extends FakeTerminalRunner {
  String? source;
  String? script;
  int? scriptMode;

  @override
  RunningCommand run(CommandRequest request) {
    final command = super.run(request);
    return _InspectingRunningCommand(command, request, this);
  }
}

class _InspectingRunningCommand implements RunningCommand {
  _InspectingRunningCommand(this._command, this._request, this._runner);

  final RunningCommand _command;
  final CommandRequest _request;
  final _InspectingTerminalRunner _runner;

  @override
  Future<void> cancel() => _command.cancel();

  @override
  Future<CommandResult> get result async {
    final sourcePath = _request.environment['CONFDB_EDITOR_SOURCE']!;
    final scriptPath = _request.environment['EDITOR']!;
    _runner.source = await File(sourcePath).readAsString();
    _runner.script = await File(scriptPath).readAsString();
    _runner.scriptMode = (await FileStat.stat(scriptPath)).mode & 0x1ff;
    return _command.result;
  }
}