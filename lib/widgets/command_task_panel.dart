import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import '../models/command_task.dart';

class CommandTaskPanel extends StatelessWidget {
  const CommandTaskPanel({super.key, required this.tasks, required this.onCancel});
  final List<CommandTask> tasks;
  final ValueChanged<String> onCancel;
  @override
  Widget build(BuildContext context) => YaruSection(
    headline: const Text('Command tasks'),
    child: tasks.isEmpty ? const Center(child: Text('No commands run')) : ListView.builder(itemCount: tasks.length, itemBuilder: (context, index) { final task = tasks[index]; return ExpansionTile(leading: Icon(_icon(task.status)), title: Text(task.label), subtitle: Text(task.status.name), trailing: task.isFinished ? null : IconButton(tooltip: 'Cancel command', onPressed: () => onCancel(task.id), icon: const Icon(Icons.cancel_outlined)), children: [if (task.stdout.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: SelectableText(task.stdout, style: const TextStyle(fontFamily: 'monospace'))), if (task.stderr.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: SelectableText(task.stderr, style: const TextStyle(fontFamily: 'monospace')))]); }),
  );
  IconData _icon(CommandTaskStatus status) => switch (status) { CommandTaskStatus.succeeded => Icons.check_circle_outline, CommandTaskStatus.failed => Icons.error_outline, CommandTaskStatus.cancelled => Icons.cancel_outlined, CommandTaskStatus.pending || CommandTaskStatus.running => Icons.hourglass_empty };
}