import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../models/confdb_schema_document.dart';

class DraftSidebar extends StatelessWidget {
  const DraftSidebar({super.key, required this.drafts, required this.onOpen, required this.onRefresh});

  final List<ConfdbSchemaDocument> drafts;
  final ValueChanged<ConfdbSchemaDocument> onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => YaruSection(
    headline: Row(children: [const Expanded(child: Text('Local drafts')), IconButton(tooltip: 'Refresh local drafts', onPressed: onRefresh, icon: const Icon(Icons.refresh))]),
    child: drafts.isEmpty
        ? const Center(child: Text('No local drafts'))
        : ListView.builder(
            itemCount: drafts.length,
            itemBuilder: (context, index) {
              final draft = drafts[index];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(draft.name.isEmpty ? 'Untitled schema' : draft.name),
                subtitle: Text(draft.accountId),
                trailing: draft.isDirty ? const Icon(Icons.circle, size: 10) : null,
                onTap: () => onOpen(draft),
              );
            },
          ),
  );
}