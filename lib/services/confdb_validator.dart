import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../models/storage_node.dart';
import '../models/view_rule.dart';
import 'confdb_source_codec.dart';

class ConfdbValidator {
  const ConfdbValidator();

  List<Diagnostic> validate(ConfdbSchemaDocument document) {
    final diagnostics = <Diagnostic>[];
    _validateSchema(document, diagnostics);
    _validateStorage(document.storage, diagnostics, const []);
    _validateViews(document, diagnostics);
    return List.unmodifiable(diagnostics);
  }

  List<Diagnostic> validateSource(String source) {
    final result = const ConfdbSourceCodec().parse(source);
    if (result.applied) {
      return validate(result.document!);
    }
    return List.unmodifiable([
      for (final diagnostic in result.diagnostics)
        Diagnostic(
          code: diagnostic.code,
          message: diagnostic.message,
          severity: diagnostic.severity,
          location: const DiagnosticLocation(section: 'source'),
        ),
    ]);
  }

  void _validateSchema(
    ConfdbSchemaDocument document,
    List<Diagnostic> diagnostics,
  ) {
    if (document.accountId.trim().isEmpty) {
      _add(
        diagnostics,
        code: 'schema.account-id-required',
        message: 'An account ID is required.',
        location: const DiagnosticLocation(section: 'schema', path: 'account-id'),
      );
    } else if (!_isIdentifier(document.accountId)) {
      _add(
        diagnostics,
        code: 'schema.invalid-account-id',
        message: 'The account ID must use lowercase letters, digits, and hyphens.',
        location: const DiagnosticLocation(section: 'schema', path: 'account-id'),
      );
    }

    if (!_isIdentifier(document.name)) {
      _add(
        diagnostics,
        code: 'schema.invalid-name',
        message: 'The schema name must use lowercase letters, digits, and hyphens.',
        location: const DiagnosticLocation(section: 'schema', path: 'name'),
      );
      _add(
        diagnostics,
        code: 'schema.naming-violation',
        message: 'Use a lowercase, hyphen-separated schema name.',
        severity: DiagnosticSeverity.advisory,
        location: const DiagnosticLocation(section: 'schema', path: 'name'),
      );
    }

    if (document.storage.kind != StorageKind.map ||
        document.storage.children.isEmpty) {
      _add(
        diagnostics,
        code: 'schema.storage-required',
        message: 'Storage must be a non-empty root map.',
        location: const DiagnosticLocation(section: 'storage'),
      );
    } else if (!document.storage.children.keys.any(_isVersionRoot)) {
      _add(
        diagnostics,
        code: 'storage.version-root-missing',
        message: 'Add a literal top-level version root such as v1.',
        severity: DiagnosticSeverity.advisory,
        location: const DiagnosticLocation(section: 'storage'),
      );
    }
  }

  void _validateStorage(
    StorageNode node,
    List<Diagnostic> diagnostics,
    List<String> path,
  ) {
    final location = DiagnosticLocation(section: 'storage', path: path.join('.'));
    if (node.kind == StorageKind.alias) {
      _add(
        diagnostics,
        code: 'storage.unsupported-alias',
        message: 'Aliases cannot be represented in a confdb-schema assertion.',
        location: location,
      );
    }
    if (node.kind == StorageKind.any) {
      _add(
        diagnostics,
        code: 'storage.unsupported-type',
        message: 'The any storage type cannot be represented in a confdb-schema assertion.',
        location: location,
      );
    }
    if (node.minimum != null && node.maximum != null && node.minimum! > node.maximum!) {
      _add(
        diagnostics,
        code: 'storage.unrepresentable-constraint',
        message: 'The minimum cannot be greater than the maximum.',
        location: location,
      );
    }
    if (node.pattern != null) {
      try {
        RegExp(node.pattern!);
      } on FormatException {
        _add(
          diagnostics,
          code: 'storage.unrepresentable-constraint',
          message: 'The string pattern is not a valid regular expression.',
          location: location,
        );
      }
    }
    if (!_choicesMatchKind(node)) {
      _add(
        diagnostics,
        code: 'storage.unsupported-constraint',
        message: 'Choices must use values compatible with the storage type.',
        location: location,
      );
    }
    if (node.kind == StorageKind.array && node.items == null) {
      _add(
        diagnostics,
        code: 'storage.unrepresentable-constraint',
        message: 'Array storage requires an item schema.',
        location: location,
      );
    }
    for (final entry in node.children.entries) {
      if (!_isIdentifier(entry.key)) {
        _add(
          diagnostics,
          code: 'storage.naming-violation',
          message: 'Storage names should use lowercase letters, digits, and hyphens.',
          severity: DiagnosticSeverity.advisory,
          location: DiagnosticLocation(
            section: 'storage',
            path: [...path, entry.key].join('.'),
          ),
        );
      }
      _validateStorage(entry.value, diagnostics, [...path, entry.key]);
    }
    if (node.items != null) {
      _validateStorage(node.items!, diagnostics, [...path, 'items']);
    }
  }

  void _validateViews(
    ConfdbSchemaDocument document,
    List<Diagnostic> diagnostics,
  ) {
    for (final view in document.views) {
      if (!_isIdentifier(view.name)) {
        _add(
          diagnostics,
          code: 'view.naming-violation',
          message: 'View names should use lowercase letters, digits, and hyphens.',
          severity: DiagnosticSeverity.advisory,
          location: DiagnosticLocation(section: 'views', viewName: view.name),
        );
      }
      final requests = <String>{};
      final storageMappings = <String>{};
      for (var index = 0; index < view.rules.length; index++) {
        final rule = view.rules[index];
        final location = DiagnosticLocation(
          section: 'views',
          viewName: view.name,
          ruleIndex: index,
        );
        _validateRulePaths(rule, diagnostics, location);
        if (!_samePlaceholders(rule.request.placeholders, rule.storage.placeholders)) {
          _add(
            diagnostics,
            code: 'rule.placeholder-mismatch',
            message: 'Request and storage paths must use the same placeholders.',
            location: location,
          );
        }
        final request = rule.request.toString();
        if (!requests.add(request)) {
          _add(
            diagnostics,
            code: 'rule.duplicate-request-path',
            message: 'Each request path can appear only once in a view.',
            location: location,
          );
        }
        final storage = rule.storage.toString();
        if (!storageMappings.add(storage)) {
          _add(
            diagnostics,
            code: 'rule.duplicate-storage-mapping',
            message: 'Each storage mapping can appear only once in a view.',
            location: location,
          );
        }
        if (rule.access == ViewAccess.readWrite && _isBroadWritableRule(rule)) {
          _add(
            diagnostics,
            code: 'rule.overly-broad-writable-mapping',
            message: 'Writable rules should target a specific field or placeholder.',
            severity: DiagnosticSeverity.advisory,
            location: location,
          );
        }
      }
    }
  }

  void _validateRulePaths(
    ConfdbRule rule,
    List<Diagnostic> diagnostics,
    DiagnosticLocation location,
  ) {
    if (!_isValidPath(rule.request) || !_isValidPath(rule.storage)) {
      _add(
        diagnostics,
        code: 'rule.malformed-path',
        message: 'Request and storage paths must contain valid dot-separated segments.',
        location: location,
      );
    }
    if (rule.request.segments.any((segment) =>
        !_isPlaceholder(segment) && !_isIdentifier(segment))) {
      _add(
        diagnostics,
        code: 'rule.request-naming-violation',
        message: 'Request path literals should use lowercase letters, digits, and hyphens.',
        severity: DiagnosticSeverity.advisory,
        location: location,
      );
    }
    if (rule.storage.segments.any((segment) =>
        !_isPlaceholder(segment) && !_isIdentifier(segment))) {
      _add(
        diagnostics,
        code: 'rule.storage-naming-violation',
        message: 'Storage path literals should use lowercase letters, digits, and hyphens.',
        severity: DiagnosticSeverity.advisory,
        location: location,
      );
    }
  }

  bool _choicesMatchKind(StorageNode node) => switch (node.kind) {
    StorageKind.string => node.choices.every((choice) => choice is String),
    StorageKind.integer => node.choices.every((choice) => choice is int),
    StorageKind.number => node.choices.every((choice) => choice is num),
    StorageKind.boolean => node.choices.every((choice) => choice is bool),
    _ => node.choices.isEmpty,
  };

  bool _isBroadWritableRule(ConfdbRule rule) =>
      rule.request.placeholders.isEmpty && rule.storage.placeholders.isEmpty;

    bool _samePlaceholders(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  bool _isValidPath(ConfdbPath path) =>
      path.segments.isNotEmpty &&
      path.segments.every((segment) => _isIdentifier(segment) || _isPlaceholder(segment));

  bool _isPlaceholder(String value) =>
      RegExp(r'^\{[A-Za-z][A-Za-z0-9_-]*\}$').hasMatch(value);

  bool _isIdentifier(String value) =>
      RegExp(r'^[a-z](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(value);

  bool _isVersionRoot(String value) => RegExp(r'^v[1-9][0-9]*$').hasMatch(value);

  void _add(
    List<Diagnostic> diagnostics, {
    required String code,
    required String message,
    required DiagnosticLocation location,
    DiagnosticSeverity severity = DiagnosticSeverity.blocker,
  }) {
    diagnostics.add(
      Diagnostic(
        code: code,
        message: message,
        severity: severity,
        location: location,
      ),
    );
  }
}