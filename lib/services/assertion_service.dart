import 'dart:convert';
import 'dart:io';

import '../models/command_task.dart';
import '../models/confdb_schema_document.dart';
import 'terminal_runner.dart';

class AssertionServiceException implements Exception {
  const AssertionServiceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class AssertionSigningResult {
  const AssertionSigningResult({required this.artifact, required this.task});

  final SigningArtifact artifact;
  final CommandTask task;
}

class AssertionAcknowledgementResult {
  const AssertionAcknowledgementResult({required this.task});

  final CommandTask task;
}

class AssertionService {
  AssertionService({required this.runner});

  final TerminalRunner runner;

  Future<AssertionSigningResult> sign({
    required String keyName,
    required String unsignedAssertion,
    required String savedPath,
  }) async {
    final startedAt = DateTime.now();
    final result = await runner
        .run(
          CommandRequest(
            executable: 'snap',
            arguments: ['sign', '-k', keyName],
            stdin: unsignedAssertion,
          ),
        )
        .result;
    final task = _task(
      id: 'sign-${startedAt.microsecondsSinceEpoch}',
      kind: CommandTaskKind.sign,
      label: 'Sign ConfDB assertion',
      startedAt: startedAt,
      result: result,
    );
    if (!result.succeeded) {
      throw AssertionServiceException('assertion.sign-failed', result.stderr);
    }
    if (!_isSignedConfdbAssertion(result.stdout)) {
      throw const AssertionServiceException(
        'assertion.invalid-signed-output',
        'snap sign did not return a signed confdb-schema assertion.',
      );
    }

    await File(savedPath).writeAsString(result.stdout, encoding: utf8);
    return AssertionSigningResult(
      artifact: SigningArtifact(
        keyName: keyName,
        signedAssertion: result.stdout,
        createdAt: DateTime.now(),
        savedPath: savedPath,
      ),
      task: task,
    );
  }

  Future<AssertionAcknowledgementResult> acknowledge(String savedPath) async {
    final startedAt = DateTime.now();
    final result = await runner
        .run(CommandRequest(executable: 'snap', arguments: ['ack', savedPath]))
        .result;
    return AssertionAcknowledgementResult(
      task: _task(
        id: 'ack-${startedAt.microsecondsSinceEpoch}',
        kind: CommandTaskKind.ack,
        label: 'Acknowledge ConfDB assertion',
        startedAt: startedAt,
        result: result,
      ),
    );
  }

  bool _isSignedConfdbAssertion(String output) {
    if (!RegExp(r'(^|\n)type:\s*confdb-schema\s*(\n|$)').hasMatch(output)) {
      return false;
    }
    final separator = RegExp(r'\r?\n[ \t]*\r?\n').firstMatch(output);
    return separator != null &&
        output.substring(separator.end).trim().isNotEmpty;
  }

  CommandTask _task({
    required String id,
    required CommandTaskKind kind,
    required String label,
    required DateTime startedAt,
    required CommandResult result,
  }) {
    return CommandTask(
      id: id,
      kind: kind,
      status: result.wasCancelled
          ? CommandTaskStatus.cancelled
          : result.succeeded
          ? CommandTaskStatus.succeeded
          : CommandTaskStatus.failed,
      label: label,
      startedAt: startedAt,
      completedAt: startedAt.add(result.duration),
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
    );
  }
}
