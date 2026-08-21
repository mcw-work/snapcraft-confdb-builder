import 'dart:convert';
import 'dart:io';

import '../models/command_task.dart';
import 'host_env.dart';
import 'terminal_runner.dart';

class EditorPublishResult {
  const EditorPublishResult({required this.task});

  final CommandTask task;
}

class EditorBridge {
  EditorBridge({required this.runner, this.temporaryParent});

  final TerminalRunner runner;
  final Directory? temporaryParent;

  Future<EditorPublishResult> publish({
    required String keyName,
    required String accountId,
    required String name,
    required String source,
    Duration? timeout,
  }) async {
    final directory = await (temporaryParent ?? Directory.systemTemp).createTemp(
      'confdb-editor-',
    );
    try {
      final sourceFile = File('${directory.path}/source.yaml');
      final script = File('${directory.path}/copy-source.sh');
      await sourceFile.writeAsString(source, encoding: utf8);
      await script.writeAsString(
        '#!/bin/sh\ncp "\$CONFDB_EDITOR_SOURCE" "\$1"\n',
        encoding: utf8,
      );
      await Process.run('chmod', ['700', script.path]);

      final startedAt = DateTime.now();
      final result = await runner
          .run(
            CommandRequest(
              executable: 'snapcraft',
              arguments: [
                'edit-confdb-schema',
                '--key-name',
                keyName,
                accountId,
                name,
              ],
              environment: {
                ...sanitizedHostEnvironment(),
                'EDITOR': script.path,
                'CONFDB_EDITOR_SOURCE': sourceFile.path,
              },
              timeout: timeout,
            ),
          )
          .result;
      return EditorPublishResult(
        task: CommandTask(
          id: 'publish-${startedAt.microsecondsSinceEpoch}',
          kind: CommandTaskKind.publish,
          status: result.wasCancelled
              ? CommandTaskStatus.cancelled
              : result.succeeded
              ? CommandTaskStatus.succeeded
              : CommandTaskStatus.failed,
          label: 'Publish ConfDB schema',
          startedAt: startedAt,
          completedAt: startedAt.add(result.duration),
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode,
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }
}