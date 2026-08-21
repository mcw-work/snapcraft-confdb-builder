const Object _unsetTaskValue = Object();

enum CommandTaskKind { unknown, account, keys, sign, ack, inventory, fetchRemote, publish }

enum CommandTaskStatus { pending, running, succeeded, failed, cancelled }

class CommandTask {
  const CommandTask({
    required this.id,
    required this.kind,
    required this.status,
    required this.label,
    this.startedAt,
    this.completedAt,
    this.stdout = '',
    this.stderr = '',
    this.exitCode,
  });

  final String id;
  final CommandTaskKind kind;
  final CommandTaskStatus status;
  final String label;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String stdout;
  final String stderr;
  final int? exitCode;

  bool get isFinished => switch (status) {
        CommandTaskStatus.succeeded ||
        CommandTaskStatus.failed ||
        CommandTaskStatus.cancelled => true,
        CommandTaskStatus.pending || CommandTaskStatus.running => false,
      };

  CommandTask copyWith({
    CommandTaskKind? kind,
    CommandTaskStatus? status,
    String? label,
    Object? startedAt = _unsetTaskValue,
    Object? completedAt = _unsetTaskValue,
    String? stdout,
    String? stderr,
    Object? exitCode = _unsetTaskValue,
  }) {
    return CommandTask(
      id: id,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      label: label ?? this.label,
      startedAt: identical(startedAt, _unsetTaskValue)
          ? this.startedAt
          : startedAt as DateTime?,
      completedAt: identical(completedAt, _unsetTaskValue)
          ? this.completedAt
          : completedAt as DateTime?,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      exitCode: identical(exitCode, _unsetTaskValue)
          ? this.exitCode
          : exitCode as int?,
    );
  }
}