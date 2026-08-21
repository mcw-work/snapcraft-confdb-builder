import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/models/view_rule.dart';
import 'package:snapcraft_confdb_builder/services/confdb_assertion_builder.dart';
import 'package:snapcraft_confdb_builder/services/confdb_source_codec.dart';

void main() {
  const builder = ConfdbAssertionBuilder();

  final validDocument = ConfdbSchemaDocument(
    accountId: 'brand-id',
    name: 'weather',
    summary: 'Weather settings',
    extraHeaders: const {'authority-id': 'brand-id'},
    storage: StorageNode.map(
      children: {
        'v1': StorageNode.map(children: {'city': StorageNode.string()}),
      },
    ),
    views: [
      ConfdbView(
        name: 'admin',
        rules: [
          ConfdbRule(
            request: ConfdbPath.parse('weather.{key}'),
            storage: ConfdbPath.parse('v1.{key}'),
            access: ViewAccess.readWrite,
          ),
        ],
      ),
    ],
  );

  test('emits codec-canonical unsigned assertion input', () {
    final result = builder.build(validDocument);

    expect(result.canSign, isTrue);
    expect(result.diagnostics, isEmpty);
    expect(result.unsignedInput, const ConfdbSourceCodec().encode(validDocument));
  });

  test('rejects unsigned input when validation has blockers', () {
    final result = builder.build(
      ConfdbSchemaDocument.empty(accountId: '', name: 'Bad_Name'),
    );

    expect(result.canSign, isFalse);
    expect(result.unsignedInput, isNull);
    expect(
      result.diagnostics.map((item) => item.code),
      contains('schema.account-id-required'),
    );
  });
}