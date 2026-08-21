import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import 'confdb_source_codec.dart';
import 'confdb_validator.dart';

class AssertionBuildResult {
  const AssertionBuildResult({
    required this.unsignedInput,
    required this.diagnostics,
  });

  final String? unsignedInput;
  final List<Diagnostic> diagnostics;

  bool get canSign => unsignedInput != null;
}

class ConfdbAssertionBuilder {
  const ConfdbAssertionBuilder({
    this.validator = const ConfdbValidator(),
    this.codec = const ConfdbSourceCodec(),
  });

  final ConfdbValidator validator;
  final ConfdbSourceCodec codec;

  AssertionBuildResult build(ConfdbSchemaDocument document) {
    final diagnostics = validator.validate(document);
    if (diagnostics.any((diagnostic) => diagnostic.isBlocker)) {
      return AssertionBuildResult(unsignedInput: null, diagnostics: diagnostics);
    }
    return AssertionBuildResult(
      unsignedInput: codec.encode(document),
      diagnostics: diagnostics,
    );
  }
}