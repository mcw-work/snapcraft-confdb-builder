import 'package:flutter/material.dart';

import '../controllers/workbench_controller.dart';
import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../widgets/command_task_panel.dart';
import '../widgets/diagnostics_panel.dart';
import '../widgets/draft_sidebar.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/source_editor.dart';
import '../widgets/storage_tree_editor.dart';
import '../widgets/store_schema_sidebar.dart';
import '../widgets/view_rule_editor.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, this.controller});
  final WorkbenchController? controller;
  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  late final WorkbenchController _controller = widget.controller ?? WorkbenchController();
  late final bool _ownsController = widget.controller == null;
  @override
  void dispose() { if (_ownsController) _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Snapcraft ConfDB Builder'), actions: [if (_controller.document.isDirty) const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Center(child: Text('Unsaved changes')))]),
      body: Stack(children: [
        Row(children: [
          SizedBox(width: 230, child: DraftSidebar(drafts: _controller.localDrafts, onOpen: _openDraft, onRefresh: () => _controller.replaceLocalDrafts(_controller.localDrafts))),
          const VerticalDivider(width: 1),
          Expanded(child: _center()),
          const VerticalDivider(width: 1),
          SizedBox(width: 260, child: Column(children: [
            Expanded(child: StoreSchemaSidebar(rows: _controller.storeRows, onCopy: _controller.copyStoreRow, onRefresh: () => _controller.refreshStore(_controller.document.accountId))),
            Expanded(child: InspectorPanel(document: _controller.document, fingerprint: _controller.canonicalSourceFingerprint)),
            Expanded(child: CommandTaskPanel(tasks: _controller.commandTasks, onCancel: _controller.cancelCommand)),
          ])),
        ]),
        if (_controller.isBusy) const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x22000000), child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))))))
      ]),
    ),
  );

  Widget _center() => DefaultTabController(
    length: WorkbenchTab.values.length,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        TabBar(isScrollable: true, onTap: (index) => _controller.selectTab(WorkbenchTab.values[index]), tabs: const [Tab(text: 'Schema'), Tab(text: 'Views'), Tab(text: 'Source'), Tab(text: 'Validation'), Tab(text: 'Publish')]),
        const SizedBox(height: 12), Expanded(child: _tabBody()),
      ]),
    ),
  );

  Widget _tabBody() => switch (_controller.selectedTab) {
    WorkbenchTab.schema => _schemaEditor(),
    WorkbenchTab.views => ViewRuleEditor(views: _controller.document.views, selectedViewName: _controller.selectedViewName, onSelected: _controller.selectView, onChanged: (views) => _controller.replaceDocument(_controller.document.copyWith(views: views))),
    WorkbenchTab.source => Column(children: [
      Expanded(child: SourceEditor(source: _controller.source, onApply: _controller.applySource)),
      if (_controller.diagnostics.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(height: 110, child: DiagnosticsPanel(diagnostics: _controller.diagnostics, onNavigate: _navigateDiagnostic)),
      ],
    ]),
    WorkbenchTab.validation => DiagnosticsPanel(diagnostics: _controller.diagnostics, onNavigate: _navigateDiagnostic),
    WorkbenchTab.publish => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [FilledButton.icon(onPressed: _controller.cacheCanonicalSourceFingerprint, icon: const Icon(Icons.fingerprint), label: const Text('Calculate source fingerprint')), const SizedBox(height: 16), Expanded(child: DiagnosticsPanel(diagnostics: _controller.diagnostics, onNavigate: _navigateDiagnostic))]),
  };

  Widget _schemaEditor() => Column(children: [
    _field('Account ID', _controller.document.accountId, (value) => _replaceSchema(accountId: value)),
    _field('Schema name', _controller.document.name, (value) => _replaceSchema(name: value)),
    _field('Summary', _controller.document.summary, (value) => _replaceSchema(summary: value)),
    const SizedBox(height: 12), Expanded(child: StorageTreeEditor(storage: _controller.document.storage, onChanged: (storage) => _controller.replaceDocument(_controller.document.copyWith(storage: storage)))),
  ]);
  Widget _field(String label, String value, ValueChanged<String> onChanged) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextFormField(initialValue: value, decoration: InputDecoration(labelText: label), onChanged: onChanged));
  void _replaceSchema({String? accountId, String? name, String? summary}) => _controller.replaceDocument(_controller.document.copyWith(accountId: accountId, name: name, summary: summary));
  void _navigateDiagnostic(Diagnostic diagnostic) { final section = diagnostic.location?.section; _controller.selectTab(switch (section) {'source' => WorkbenchTab.source, 'views' => WorkbenchTab.views, _ => WorkbenchTab.schema}); _controller.selectView(diagnostic.location?.viewName); }
  Future<void> _openDraft(ConfdbSchemaDocument draft) async {
    if (!_controller.document.isDirty) { _controller.openDocument(draft); return; }
    final decision = await showDialog<_OpenDecision>(context: context, builder: (context) => AlertDialog(title: const Text('Save changes?'), content: const Text('The current draft has unsaved changes.'), actions: [TextButton(onPressed: () => Navigator.pop(context, _OpenDecision.cancel), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, _OpenDecision.discard), child: const Text('Discard')), FilledButton(onPressed: () => Navigator.pop(context, _OpenDecision.save), child: const Text('Save'))]));
    if (decision == null || decision == _OpenDecision.cancel) return;
    if (decision == _OpenDecision.save) _controller.markSaved();
    _controller.openDocument(draft);
  }
}
enum _OpenDecision { discard, save, cancel }