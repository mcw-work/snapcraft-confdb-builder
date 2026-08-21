import 'dart:convert';

import '../models/command_task.dart';
import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import 'confdb_source_codec.dart';
import 'schema_diff_service.dart';
import 'terminal_runner.dart';

class StoreSchemaRow {
  const StoreSchemaRow({
    required this.accountId,
    required this.name,
    this.revision,
    this.summary,
  });

  final String accountId;
  final String name;
  final String? revision;
  final String? summary;
}

class StoreSchemaInventoryResult {
  const StoreSchemaInventoryResult({
    required this.rows,
    required this.diagnostics,
    required this.task,
  });

  final List<StoreSchemaRow> rows;
  final List<Diagnostic> diagnostics;
  final CommandTask task;
}

class RemoteSchemaResult {
  const RemoteSchemaResult({required this.document, required this.task});

  final ConfdbSchemaDocument document;
  final CommandTask task;
}

class StoreSchemaPreflightResult {
  const StoreSchemaPreflightResult({
    required this.remote,
    required this.comparison,
    required this.task,
  });

  final ConfdbSchemaDocument remote;
  final SchemaComparison comparison;
  final CommandTask task;
}

class StoreSchemaServiceException implements Exception {
  const StoreSchemaServiceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class StoreSchemaService {
  StoreSchemaService({
    required this.runner,
    this.codec = const ConfdbSourceCodec(),
    this.diffService = const SchemaDiffService(),
  });

  final TerminalRunner runner;
  final ConfdbSourceCodec codec;
  final SchemaDiffService diffService;

  Future<StoreSchemaInventoryResult> inventory(String accountId) async {
    final startedAt = DateTime.now();
    var result = await _runInventory('confdb-schemas', accountId);
    if (!result.succeeded && _isUnknownCommand(result)) {
      result = await _runInventory('list-confdb-schemas', accountId);
    }
    final task = _task(
      id: 'inventory-${startedAt.microsecondsSinceEpoch}',
      kind: CommandTaskKind.inventory,
      label: 'List ConfDB schemas',
      startedAt: startedAt,
      result: result,
    );
    if (!result.succeeded) {
      return StoreSchemaInventoryResult(
        rows: const [],
        diagnostics: const [],
        task: task,
      );
    }

    final rows = _parseInventory(result.stdout, accountId);
    if (rows == null) {
      return StoreSchemaInventoryResult(
        rows: const [],
        diagnostics: const [
          Diagnostic(
            code: 'store.inventory-unparseable',
            message: 'Snapcraft returned an unparseable ConfDB schema inventory.',
            severity: DiagnosticSeverity.blocker,
          ),
        ],
        task: task,
      );
    }
    return StoreSchemaInventoryResult(
      rows: List.unmodifiable(rows),
      diagnostics: const [],
      task: task,
    );
  }

  Future<RemoteSchemaResult> fetchRemote({
    required String accountId,
    required String name,
  }) async {
    final startedAt = DateTime.now();
    final result = await runner
        .run(
          CommandRequest(
            executable: 'snap',
            arguments: [
              'known',
              '--remote',
              'confdb-schema',
              'account-id=$accountId',
              'name=$name',
            ],
          ),
        )
        .result;
    final task = _task(
      id: 'fetch-remote-${startedAt.microsecondsSinceEpoch}',
      kind: CommandTaskKind.fetchRemote,
      label: 'Fetch remote ConfDB schema',
      startedAt: startedAt,
      result: result,
    );
    if (!result.succeeded) {
      throw StoreSchemaServiceException(
        'store.remote-fetch-failed',
        result.stderr,
      );
    }
    final parsed = codec.parse(result.stdout);
    if (!parsed.applied) {
      final diagnostic = parsed.diagnostics.first;
      throw StoreSchemaServiceException(
        'store.remote-unparseable',
        diagnostic.message,
      );
    }
    return RemoteSchemaResult(document: parsed.document!, task: task);
  }

  Future<StoreSchemaPreflightResult> preflight(
    ConfdbSchemaDocument draft,
  ) async {
    final remote = await fetchRemote(
      accountId: draft.accountId,
      name: draft.name,
    );
    return StoreSchemaPreflightResult(
      remote: remote.document,
      comparison: diffService.compare(remote: remote.document, draft: draft),
      task: remote.task,
    );
  }

  Future<CommandResult> _runInventory(String command, String accountId) => runner
      .run(
        CommandRequest(
          executable: 'snapcraft',
          arguments: [command, accountId],
        ),
      )
      .result;

  bool _isUnknownCommand(CommandResult result) => RegExp(
        r'unknown-command|unknown command|no such command|invalid choice',
      ).hasMatch('${result.stdout}\n${result.stderr}'.toLowerCase());

  List<StoreSchemaRow>? _parseInventory(String output, String accountId) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(trimmed);
      return _rowsFromJson(decoded, accountId);
    } on FormatException {
      // Fall through to the human-readable listing formats.
    }
    return _rowsFromTable(trimmed, accountId);
  }

  List<StoreSchemaRow>? _rowsFromJson(Object? value, String accountId) {
    final entries = switch (value) {
      List<Object?> rows => rows,
      Map<Object?, Object?> map when map['schemas'] is List<Object?> =>
        map['schemas'] as List<Object?>,
      Map<Object?, Object?> map when map['items'] is List<Object?> =>
        map['items'] as List<Object?>,
      Map<Object?, Object?> map when map.containsKey('name') => [map],
      Map<Object?, Object?> map => [
          for (final entry in map.entries)
            if (entry.key is String && entry.value is Map<Object?, Object?>)
              {'name': entry.key, ...entry.value as Map<Object?, Object?>},
        ],
      _ => null,
    };
    if (entries == null || entries.isEmpty && value is Map) {
      return null;
    }
    final rows = <StoreSchemaRow>[];
    for (final entry in entries) {
      if (entry is! Map<Object?, Object?>) {
        return null;
      }
      final name = entry['name'];
      final rowAccountId = entry['account-id'] ?? entry['accountId'] ?? accountId;
      final revision = entry['revision'];
      final summary = entry['summary'];
      if (name is! String || name.isEmpty || rowAccountId is! String) {
        return null;
      }
      if (revision != null && revision is! String && revision is! num) {
        return null;
      }
      if (summary != null && summary is! String) {
        return null;
      }
      rows.add(
        StoreSchemaRow(
          accountId: rowAccountId,
          name: name,
          revision: revision?.toString(),
          summary: summary as String?,
        ),
      );
    }
    return rows;
  }

  List<StoreSchemaRow>? _rowsFromTable(String output, String accountId) {
    final rows = <StoreSchemaRow>[];
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || RegExp(r'^[-=\s]+$').hasMatch(trimmed)) {
        continue;
      }
      final cells = trimmed.split(RegExp(r'\s{2,}|\t+'));
      final fields = cells.length == 1
          ? trimmed.split(RegExp(r'\s+'))
          : cells;
      if (fields.isEmpty ||
          (fields.first.toLowerCase().contains('account') &&
              fields.any((field) => field.toLowerCase() == 'name'))) {
        continue;
      }
      final hasAccountId = fields.length > 1 && fields.first == accountId;
      final nameIndex = hasAccountId ? 1 : 0;
      if (fields.length <= nameIndex || fields[nameIndex].isEmpty) {
        return null;
      }
      final revisionIndex = nameIndex + 1;
      final summaryIndex = revisionIndex + 1;
      rows.add(
        StoreSchemaRow(
          accountId: hasAccountId ? fields.first : accountId,
          name: fields[nameIndex],
          revision: fields.length > revisionIndex ? fields[revisionIndex] : null,
          summary: fields.length > summaryIndex
              ? fields.sublist(summaryIndex).join(' ')
              : null,
        ),
      );
    }
    return rows.isEmpty ? null : rows;
  }

  CommandTask _task({
    required String id,
    required CommandTaskKind kind,
    required String label,
    required DateTime startedAt,
    required CommandResult result,
  }) => CommandTask(
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