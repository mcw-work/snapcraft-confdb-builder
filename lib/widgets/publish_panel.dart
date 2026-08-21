import 'package:flutter/material.dart';

import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../services/schema_diff_service.dart';
import 'publish_confirmation_dialog.dart';
import 'schema_diff_view.dart';

class PublishPanel extends StatelessWidget {
  const PublishPanel({
    super.key,
    required this.document,
    required this.selectedKeyName,
    required this.diagnostics,
    required this.remote,
    required this.comparison,
    required this.preflightCurrent,
    required this.onRefreshPreflight,
    required this.onRunAck,
    required this.onPublish,
  });

  final ConfdbSchemaDocument document;
  final String? selectedKeyName;
  final List<Diagnostic> diagnostics;
  final ConfdbSchemaDocument? remote;
  final SchemaComparison? comparison;
  final bool preflightCurrent;
  final VoidCallback onRefreshPreflight;
  final VoidCallback onRunAck;
  final VoidCallback onPublish;

  bool get _hasBlockers => diagnostics.any((diagnostic) => diagnostic.isBlocker) || (comparison?.hasBlockers ?? false);
  bool get _canSign => !_hasBlockers && (selectedKeyName?.isNotEmpty ?? false);
  bool get _canPublish => _canSign && preflightCurrent;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      Text('Publication', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      _detail('Account', document.accountId),
      _detail('Schema target', document.name),
      _detail('Selected key', selectedKeyName ?? 'No key selected'),
      _detail('Preflight', preflightCurrent ? 'Current source' : 'Refresh required'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: onRefreshPreflight, icon: const Icon(Icons.refresh), label: const Text('Refresh preflight')),
        OutlinedButton.icon(onPressed: document.artifact?.savedPath == null ? null : onRunAck, icon: const Icon(Icons.verified_outlined), label: const Text('Run snap ack')),
        FilledButton.icon(
          key: const Key('publish-button'),
          onPressed: _canPublish ? () => _confirmPublish(context) : null,
          icon: const Icon(Icons.publish_outlined),
          label: const Text('Publish schema'),
        ),
      ]),
      const Divider(height: 32),
      Text('Remote assertion', style: Theme.of(context).textTheme.titleSmall),
      SelectableText(remote == null ? 'No remote assertion loaded.' : '${remote!.accountId}/${remote!.name} revision ${remote!.revision?.value ?? 'unknown'}'),
      const SizedBox(height: 12),
      SchemaDiffView(comparison: comparison),
      const SizedBox(height: 12),
      Text('Validation state: ${_hasBlockers ? 'Blocked' : 'Ready'}'),
      const Divider(height: 32),
      Text('Unsigned assertion', style: Theme.of(context).textTheme.titleSmall),
      SelectableText(_unsignedAssertion, style: const TextStyle(fontFamily: 'monospace')),
      const SizedBox(height: 12),
      Text('Signed assertion', style: Theme.of(context).textTheme.titleSmall),
      SelectableText(document.artifact?.signedAssertion ?? 'Not signed', style: const TextStyle(fontFamily: 'monospace')),
      _detail('Saved path', document.artifact?.savedPath ?? 'Not saved'),
    ],
  );

  String get _unsignedAssertion => 'account-id: ${document.accountId}\nname: ${document.name}\nsummary: ${document.summary}';

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text('$label: $value'),
  );

  void _confirmPublish(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => PublishConfirmationDialog(
        schemaName: document.name,
        onConfirm: () {
          Navigator.pop(context);
          onPublish();
        },
      ),
    );
  }
}