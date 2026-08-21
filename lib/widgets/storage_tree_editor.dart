import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../models/storage_node.dart';

class StorageTreeEditor extends StatefulWidget {
  const StorageTreeEditor({super.key, required this.storage, required this.onChanged});

  final StorageNode storage;
  final ValueChanged<StorageNode> onChanged;

  @override
  State<StorageTreeEditor> createState() => _StorageTreeEditorState();
}

class _StorageTreeEditorState extends State<StorageTreeEditor> {
  final _name = TextEditingController();
  StorageKind _kind = StorageKind.string;

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => YaruSection(
    headline: const Text('Storage'),
    child: Column(children: [
      Expanded(child: ListView(children: [
        const ListTile(leading: Icon(Icons.account_tree_outlined), title: Text('storage')),
        for (final entry in widget.storage.children.entries) _nodeTile(entry.key, entry.value),
      ])),
      const Divider(),
      Row(children: [
        Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Node name'), onSubmitted: (_) => _add())),
        const SizedBox(width: 8),
        DropdownButton<StorageKind>(value: _kind, items: [for (final kind in StorageKind.values) DropdownMenuItem(value: kind, child: Text(kind.name))], onChanged: (kind) => setState(() => _kind = kind!)),
        IconButton(tooltip: 'Add storage node', onPressed: _add, icon: const Icon(Icons.add)),
      ]),
    ]),
  );

  Widget _nodeTile(String name, StorageNode node) => ExpansionTile(
    key: Key('storage-node-$name'),
    leading: Icon(node.kind == StorageKind.map ? Icons.folder_outlined : Icons.data_object_outlined),
    title: Text(name), subtitle: Text(node.kind.name),
    trailing: IconButton(tooltip: 'Remove $name', onPressed: () => _remove(name), icon: const Icon(Icons.delete_outline)),
    children: [
      if (node.kind == StorageKind.map) for (final child in node.children.entries) ListTile(contentPadding: const EdgeInsets.only(left: 48, right: 16), title: Text(child.key), subtitle: Text(child.value.kind.name)) else ListTile(title: Text('Type: ${node.kind.name}')),
    ],
  );

  void _add() {
    final name = _name.text.trim();
    if (name.isEmpty || widget.storage.children.containsKey(name)) return;
    widget.onChanged(widget.storage.copyWith(children: {...widget.storage.children, name: _forKind(_kind)}));
    _name.clear();
  }

  void _remove(String name) { final children = {...widget.storage.children}..remove(name); widget.onChanged(widget.storage.copyWith(children: children)); }

  StorageNode _forKind(StorageKind kind) => switch (kind) {
    StorageKind.string => StorageNode.string(), StorageKind.integer => StorageNode.integer(), StorageKind.number => StorageNode.number(), StorageKind.boolean => StorageNode.boolean(), StorageKind.map => StorageNode.map(), StorageKind.array => StorageNode.array(items: StorageNode.string()), StorageKind.any => StorageNode.any(), StorageKind.alias => StorageNode.alias(alias: 'target'),
  };
}