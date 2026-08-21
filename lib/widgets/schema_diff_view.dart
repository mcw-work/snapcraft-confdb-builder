import 'package:flutter/material.dart';

import '../services/schema_diff_service.dart';

class SchemaDiffView extends StatelessWidget {
  const SchemaDiffView({super.key, required this.comparison});

  final SchemaComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final current = comparison;
    if (current == null) return const Text('Refresh preflight to compare the remote assertion.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Structured changes (${current.changes.length})', style: Theme.of(context).textTheme.titleSmall),
        for (final change in current.changes)
          ListTile(
            dense: true,
            leading: Icon(switch (change.kind) {
              SchemaChangeKind.added => Icons.add_circle_outline,
              SchemaChangeKind.removed => Icons.remove_circle_outline,
              SchemaChangeKind.modified => Icons.edit_outlined,
              SchemaChangeKind.renamed => Icons.drive_file_rename_outline,
            }),
            title: Text('${change.kind.name}: ${change.subject} ${change.path}'),
            subtitle: change.previousPath == null ? null : Text('Previously ${change.previousPath}'),
          ),
        const SizedBox(height: 8),
        Text('Source diff', style: Theme.of(context).textTheme.titleSmall),
        SelectableText(current.sourceDiff, key: const Key('source-diff'), style: const TextStyle(fontFamily: 'monospace')),
      ],
    );
  }
}