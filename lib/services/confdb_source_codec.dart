import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../models/storage_node.dart';
import '../models/view_rule.dart';

class SourceApplyResult {
  const SourceApplyResult({
    required this.document,
    required this.diagnostics,
    required this.applied,
  });

  final ConfdbSchemaDocument? document;
  final List<Diagnostic> diagnostics;
  final bool applied;
}

class ConfdbSourceCodec {
  const ConfdbSourceCodec();

  SourceApplyResult applySource(ConfdbSchemaDocument activeDocument, String source) {
    final parsed = parse(source);
    if (parsed.applied) {
      return parsed;
    }
    return SourceApplyResult(
      document: activeDocument,
      diagnostics: parsed.diagnostics,
      applied: false,
    );
  }

  SourceApplyResult parse(String source) {
    final Object? decodedYaml;
    try {
      decodedYaml = loadYaml(source);
    } on YamlException catch (error) {
      return _blocked('source.invalid-yaml', 'Invalid YAML: ${error.message}');
    }

    if (decodedYaml is! YamlMap) {
      return _blocked('source.invalid-yaml', 'The source must be a YAML map.');
    }

    final metadata = _toDartMap(decodedYaml);
    final type = metadata.remove('type');
    final accountId = metadata.remove('account-id');
    final name = metadata.remove('name');
    final summary = metadata.remove('summary');
    final body = metadata.remove('body');
    final revision = metadata.remove('revision');
    final timestamp = metadata.remove('timestamp');
    final views = metadata.remove('views');

    if (type != 'confdb-schema' ||
        accountId is! String ||
        name is! String ||
        summary is! String ||
        body is! String) {
      return _blocked(
        'source.invalid-yaml',
        'Expected confdb-schema type and string account-id, name, summary, and body.',
      );
    }

    final Object? decodedBody;
    try {
      decodedBody = jsonDecode(body);
    } on FormatException catch (error) {
      return _blocked(
        'source.invalid-body-json',
        'Invalid JSON body: ${error.message}',
      );
    }

    if (decodedBody is! Map || decodedBody['storage'] is! Map) {
      return _blocked(
        'source.missing-storage',
        'The JSON body must contain a root storage map.',
      );
    }

    try {
      final parsedViews = _parseViews(views);
      final parsedRevision = _parseRevision(revision, timestamp);
      final document = ConfdbSchemaDocument(
        accountId: accountId,
        name: name,
        summary: summary,
        storage: _parseStorageMap(decodedBody['storage'] as Map),
        views: parsedViews,
        extraHeaders: metadata,
        revision: parsedRevision,
      );
      return SourceApplyResult(
        document: document,
        diagnostics: const [],
        applied: true,
      );
    } on FormatException catch (error) {
      return _blocked('source.invalid-yaml', error.message);
    }
  }

  String encode(ConfdbSchemaDocument document) {
    final lines = <String>[
      'type: confdb-schema',
      'account-id: ${_yamlScalar(document.accountId)}',
      'name: ${_yamlScalar(document.name)}',
      'summary: ${_yamlScalar(document.summary)}',
    ];
    final revision = document.revision;
    if (revision != null) {
      lines.add('revision: ${_yamlScalar(revision.value)}');
      if (revision.timestamp != null) {
        lines.add('timestamp: ${revision.timestamp!.toIso8601String()}');
      }
    }
    final extraHeaderKeys = document.extraHeaders.keys.toList()..sort();
    for (final key in extraHeaderKeys) {
      lines.add('$key: ${_yamlValue(document.extraHeaders[key])}');
    }
    lines.addAll(_encodeViews(document.views));
    lines.add('body: |-');
    final body = const JsonEncoder.withIndent('  ').convert({
      'storage': _encodeStorageMap(document.storage),
    });
    lines.addAll(body.split('\n').map((line) => '  $line'));
    return '${lines.join('\n')}\n';
  }

  SourceApplyResult _blocked(String code, String message) => SourceApplyResult(
        document: null,
        diagnostics: [
          Diagnostic(
            code: code,
            message: message,
            severity: DiagnosticSeverity.blocker,
          ),
        ],
        applied: false,
      );

  Map<String, Object?> _toDartMap(YamlMap map) => {
        for (final entry in map.entries) '${entry.key}': _toDartValue(entry.value),
      };

  Object? _toDartValue(Object? value) => switch (value) {
        YamlMap map => _toDartMap(map),
        YamlList list => list.map(_toDartValue).toList(),
        _ => value,
      };

  SchemaRevision? _parseRevision(Object? value, Object? timestamp) {
    if (value == null && timestamp == null) {
      return null;
    }
    if (value is! String && value is! num) {
      throw const FormatException('revision must be a string or number.');
    }
    if (timestamp != null && timestamp is! String) {
      throw const FormatException('timestamp must be a string.');
    }
    final parsedTimestamp = timestamp == null
      ? null
      : DateTime.tryParse(timestamp as String);
    if (timestamp != null && parsedTimestamp == null) {
      throw const FormatException('timestamp must be ISO-8601.');
    }
    return SchemaRevision(value: '$value', timestamp: parsedTimestamp);
  }

  List<ConfdbView> _parseViews(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is! Map<String, Object?>) {
      throw const FormatException('views must be a map.');
    }
    return [
      for (final entry in value.entries)
        ConfdbView(name: entry.key, rules: _parseRules(entry.value)),
    ];
  }

  List<ConfdbRule> _parseRules(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('each view must be a map.');
    }
    final rules = value['rules'];
    if (rules is! List<Object?>) {
      throw const FormatException('each view must contain rules.');
    }
    return [
      for (final rule in rules) _parseRule(rule),
    ];
  }

  ConfdbRule _parseRule(Object? value) {
    if (value is! Map<String, Object?> ||
        value['request'] is! String ||
        value['storage'] is! String ||
        value['access'] is! String) {
      throw const FormatException('each rule requires request, storage, and access.');
    }
    final access = switch (value['access']) {
      'read' => ViewAccess.read,
      'read-write' => ViewAccess.readWrite,
      _ => throw const FormatException('rule access must be read or read-write.'),
    };
    return ConfdbRule(
      request: ConfdbPath.parse(value['request'] as String),
      storage: ConfdbPath.parse(value['storage'] as String),
      access: access,
    );
  }

  StorageNode _parseStorageMap(Map storage) => StorageNode.map(
        children: {
          for (final entry in storage.entries)
            if (entry.key is String && entry.value is Map)
              entry.key as String: _parseStorageNode(entry.value as Map),
        },
      );

  StorageNode _parseStorageNode(Map value) {
    final type = value['type'];
    if (type is! String) {
      throw const FormatException('storage nodes require a type.');
    }
    return switch (type) {
      'string' => StorageNode.string(
          pattern: value['pattern'] as String?,
          choices: _choices(value['choices']),
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      'integer' => StorageNode.integer(
          minimum: value['minimum'] as int?,
          maximum: value['maximum'] as int?,
          choices: _choices(value['choices']),
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      'number' => StorageNode.number(
          minimum: value['minimum'] as num?,
          maximum: value['maximum'] as num?,
          choices: _choices(value['choices']),
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      'boolean' => StorageNode.boolean(
          choices: _choices(value['choices']),
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      'map' => StorageNode.map(
          children: _parseStorageChildren(value['schema']),
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      'array' => StorageNode.array(
          items: value['items'] is Map ? _parseStorageNode(value['items'] as Map) : null,
          uniqueItems: value['unique-items'] as bool?,
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      'any' => StorageNode.any(
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      'alias' => StorageNode.alias(
          alias: value['alias'] as String,
          visibility: _visibility(value),
          ephemeral: value['ephemeral'] as bool?,
          required: value['required'] as bool?,
        ),
      _ => throw FormatException('Unsupported storage type: $type.'),
    };
  }

  Map<String, StorageNode> _parseStorageChildren(Object? value) {
    if (value is! Map) {
      throw const FormatException('map storage nodes require schema.');
    }
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: _parseStorageNode(entry.value as Map),
    };
  }

  List<Object?> _choices(Object? value) => switch (value) {
        null => const [],
        List<Object?> choices => choices,
        _ => throw const FormatException('choices must be a list.'),
      };

  StorageVisibility? _visibility(Map value) {
    final visibility = value['visibility'];
    if (visibility == null) {
      return null;
    }
    return switch (visibility) {
      'public' => StorageVisibility.public,
      'secret' => StorageVisibility.secret,
      _ => throw const FormatException('visibility must be public or secret.'),
    };
  }

  Map<String, Object?> _encodeStorageMap(StorageNode storage) {
    if (storage.kind != StorageKind.map) {
      throw ArgumentError.value(storage, 'storage', 'Root storage must be a map.');
    }
    return {
      for (final entry in storage.children.entries)
        entry.key: _encodeStorageNode(entry.value),
    };
  }

  Map<String, Object?> _encodeStorageNode(StorageNode node) => {
        'type': node.kind.name,
        if (node.kind == StorageKind.map)
          'schema': {
            for (final entry in node.children.entries)
              entry.key: _encodeStorageNode(entry.value),
          },
        if (node.kind == StorageKind.array && node.items != null)
          'items': _encodeStorageNode(node.items!),
        if (node.kind == StorageKind.alias) 'alias': node.alias,
        if (node.pattern != null) 'pattern': node.pattern,
        if (node.choices.isNotEmpty) 'choices': node.choices,
        if (node.minimum != null) 'minimum': node.minimum,
        if (node.maximum != null) 'maximum': node.maximum,
        if (node.visibility != null) 'visibility': node.visibility!.name,
        if (node.ephemeral != null) 'ephemeral': node.ephemeral,
        if (node.required != null) 'required': node.required,
        if (node.uniqueItems != null) 'unique-items': node.uniqueItems,
      };

  List<String> _encodeViews(List<ConfdbView> views) {
    if (views.isEmpty) {
      return const [];
    }
    return [
      'views:',
      for (final view in views) ...[
        '  ${view.name}:',
        '    rules:',
        for (final rule in view.rules) ...[
          '      - request: ${rule.request}',
          '        storage: ${rule.storage}',
          '        access: ${rule.access == ViewAccess.read ? 'read' : 'read-write'}',
        ],
      ],
    ];
  }

    String _yamlScalar(String value) =>
      RegExp(r'^[A-Za-z0-9._/ -]+$').hasMatch(value) ? value : jsonEncode(value);

  String _yamlValue(Object? value) => switch (value) {
        String string => _yamlScalar(string),
        num() || bool() || null => '$value',
        _ => jsonEncode(value),
      };
}