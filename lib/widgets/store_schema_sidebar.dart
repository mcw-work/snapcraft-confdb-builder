import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../services/store_schema_service.dart';

class StoreSchemaSidebar extends StatelessWidget {
  const StoreSchemaSidebar({super.key, required this.rows, required this.onCopy, required this.onRefresh});

  final List<StoreSchemaRow> rows;
  final ValueChanged<StoreSchemaRow> onCopy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => YaruSection(
    headline: Row(children: [const Expanded(child: Text('Store schemas')), IconButton(tooltip: 'Refresh Store schemas', onPressed: onRefresh, icon: const Icon(Icons.refresh))]),
    child: rows.isEmpty
        ? const Center(child: Text('No Store schemas loaded'))
        : ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(row.name),
                subtitle: Text('${row.accountId}  r${row.revision ?? '-'}'),
                trailing: const Icon(Icons.content_copy_outlined),
                onTap: () => onCopy(row),
              );
            },
          ),
  );
}