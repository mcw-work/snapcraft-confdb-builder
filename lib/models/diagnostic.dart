enum DiagnosticSeverity { blocker, advisory }

class DiagnosticLocation {
  const DiagnosticLocation({
    this.section,
    this.path,
    this.viewName,
    this.ruleIndex,
  });

  final String? section;
  final String? path;
  final String? viewName;
  final int? ruleIndex;
}

class Diagnostic {
  const Diagnostic({
    required this.code,
    required this.message,
    required this.severity,
    this.location,
  });

  final String code;
  final String message;
  final DiagnosticSeverity severity;
  final DiagnosticLocation? location;

  bool get isBlocker => severity == DiagnosticSeverity.blocker;
}