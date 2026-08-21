import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import '../models/diagnostic.dart';
import '../theme/status_colors.dart';

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({super.key, required this.diagnostics, required this.onNavigate});
  final List<Diagnostic> diagnostics;
  final ValueChanged<Diagnostic> onNavigate;
  @override
  Widget build(BuildContext context) => YaruSection(
    headline: Text('Diagnostics (${diagnostics.length})'),
    child: diagnostics.isEmpty ? const Center(child: Text('No validation issues')) : ListView.builder(itemCount: diagnostics.length, itemBuilder: (context, index) { final diagnostic = diagnostics[index]; return ListTile(leading: Icon(diagnostic.isBlocker ? Icons.error_outline : Icons.info_outline, color: diagnosticColor(context, diagnostic.severity)), title: Text(diagnostic.message), subtitle: Text(diagnostic.code), onTap: () => onNavigate(diagnostic)); }),
  );
}