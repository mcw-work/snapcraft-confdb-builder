import '../models/confdb_schema_document.dart';

class SnapcraftMetadataBuilder {
  const SnapcraftMetadataBuilder();

  String buildConsumerPlug({
    required ConfdbSchemaDocument document,
    required String viewName,
    String? plugName,
    bool custodian = false,
  }) {
    if (!document.views.any((view) => view.name == viewName)) {
      throw ArgumentError.value(
        viewName,
        'viewName',
        'The selected view does not exist.',
      );
    }
    final name = plugName ?? viewName;
    if (name.isEmpty) {
      throw ArgumentError.value(
        plugName,
        'plugName',
        'The plug name must not be empty.',
      );
    }
    return [
      '$name:',
      '  interface: confdb',
      '  account: ${document.accountId}',
      '  view: ${document.name}/$viewName',
      if (custodian) '  role: custodian',
      '',
    ].join('\n');
  }
}
