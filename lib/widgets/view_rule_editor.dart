import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../models/view_rule.dart';

class ViewRuleEditor extends StatefulWidget {
  const ViewRuleEditor({super.key, required this.views, required this.selectedViewName, required this.onSelected, required this.onChanged});
  final List<ConfdbView> views;
  final String? selectedViewName;
  final ValueChanged<String?> onSelected;
  final ValueChanged<List<ConfdbView>> onChanged;
  @override
  State<ViewRuleEditor> createState() => _ViewRuleEditorState();
}

class _ViewRuleEditorState extends State<ViewRuleEditor> {
  final _name = TextEditingController();
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final selected = widget.views.cast<ConfdbView?>().firstWhere((view) => view?.name == widget.selectedViewName, orElse: () => null);
    return YaruSection(headline: const Text('Views and rules'), child: Column(children: [
      Row(children: [Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'View name'), onSubmitted: (_) => _addView())), IconButton(tooltip: 'Add view', onPressed: _addView, icon: const Icon(Icons.add))]),
      if (widget.views.isNotEmpty) DropdownButton<String>(isExpanded: true, value: selected?.name, hint: const Text('Select a view'), items: [for (final view in widget.views) DropdownMenuItem(value: view.name, child: Text(view.name))], onChanged: widget.onSelected),
      if (selected == null) const Expanded(child: Center(child: Text('Add and select a view to edit rules.'))) else ...[
        Expanded(child: ListView(children: [for (var index = 0; index < selected.rules.length; index++) _ruleRow(selected, index)])),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _addRule(selected), icon: const Icon(Icons.add), label: const Text('Add rule'))),
      ],
    ]));
  }
  Widget _ruleRow(ConfdbView view, int index) {
    final rule = view.rules[index];
    return ListTile(title: Row(children: [
      Expanded(child: TextFormField(initialValue: rule.request.toString(), decoration: const InputDecoration(labelText: 'Request'), onChanged: (value) => _update(view, index, rule.copyWith(request: ConfdbPath.parse(value))))),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(initialValue: rule.storage.toString(), decoration: const InputDecoration(labelText: 'Storage'), onChanged: (value) => _update(view, index, rule.copyWith(storage: ConfdbPath.parse(value))))),
      const SizedBox(width: 8),
      DropdownButton<ViewAccess>(value: rule.access, items: const [DropdownMenuItem(value: ViewAccess.read, child: Text('read')), DropdownMenuItem(value: ViewAccess.readWrite, child: Text('read-write'))], onChanged: (access) => _update(view, index, rule.copyWith(access: access))),
      IconButton(tooltip: 'Remove rule', onPressed: () { final rules = [...view.rules]..removeAt(index); _replace(view.copyWith(rules: rules)); }, icon: const Icon(Icons.delete_outline)),
    ]));
  }
  void _addView() { final name = _name.text.trim(); if (name.isEmpty || widget.views.any((view) => view.name == name)) return; widget.onChanged([...widget.views, ConfdbView(name: name)]); widget.onSelected(name); _name.clear(); }
  void _addRule(ConfdbView view) => _replace(view.copyWith(rules: [...view.rules, ConfdbRule(request: ConfdbPath.parse('${view.name}.{key}'), storage: ConfdbPath.parse('v1.{key}'), access: ViewAccess.read)]));
  void _update(ConfdbView view, int index, ConfdbRule rule) { final rules = [...view.rules]..[index] = rule; _replace(view.copyWith(rules: rules)); }
  void _replace(ConfdbView replacement) => widget.onChanged([for (final view in widget.views) if (view.name == replacement.name) replacement else view]);
}