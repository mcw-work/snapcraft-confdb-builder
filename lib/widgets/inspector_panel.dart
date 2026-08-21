import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import '../models/confdb_schema_document.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.document, this.fingerprint});
  final ConfdbSchemaDocument document;
  final String? fingerprint;
  @override
  Widget build(BuildContext context) => YaruSection(headline: const Text('Inspector'), child: ListView(children: [
    _row('Account', document.accountId), _row('Schema', document.name), _row('Origin', document.origin.kind.name), _row('Dirty', document.isDirty ? 'Yes' : 'No'), _row('Revision', document.revision?.value ?? '-'), _row('Fingerprint', fingerprint ?? 'Not calculated'),
  ]));
  Widget _row(String label, String value) => ListTile(title: Text(label), subtitle: SelectableText(value, style: const TextStyle(fontFamily: 'monospace')));
}