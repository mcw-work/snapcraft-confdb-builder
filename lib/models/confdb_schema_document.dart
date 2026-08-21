import 'storage_node.dart';
import 'view_rule.dart';

const Object _unsetDocumentValue = Object();

class SchemaRevision {
  const SchemaRevision({required this.value, this.timestamp});

  final String value;
  final DateTime? timestamp;

  SchemaRevision copyWith({String? value, Object? timestamp = _unsetDocumentValue}) {
    return SchemaRevision(
      value: value ?? this.value,
      timestamp: identical(timestamp, _unsetDocumentValue)
          ? this.timestamp
          : timestamp as DateTime?,
    );
  }
}

enum DraftOriginKind { newDraft, localFile, storeCopy }

class DraftOrigin {
  const DraftOrigin._({required this.kind, this.path, this.remoteRevision});

  const DraftOrigin.newDraft() : this._(kind: DraftOriginKind.newDraft);

  const DraftOrigin.localFile(String path)
      : this._(kind: DraftOriginKind.localFile, path: path);

  const DraftOrigin.storeCopy({required String remoteRevision})
      : this._(
          kind: DraftOriginKind.storeCopy,
          remoteRevision: remoteRevision,
        );

  final DraftOriginKind kind;
  final String? path;
  final String? remoteRevision;
}

class SigningArtifact {
  const SigningArtifact({
    required this.keyName,
    required this.signedAssertion,
    required this.createdAt,
    this.savedPath,
  });

  final String keyName;
  final String signedAssertion;
  final DateTime createdAt;
  final String? savedPath;

  SigningArtifact copyWith({
    String? keyName,
    String? signedAssertion,
    DateTime? createdAt,
    Object? savedPath = _unsetDocumentValue,
  }) {
    return SigningArtifact(
      keyName: keyName ?? this.keyName,
      signedAssertion: signedAssertion ?? this.signedAssertion,
      createdAt: createdAt ?? this.createdAt,
      savedPath: identical(savedPath, _unsetDocumentValue)
          ? this.savedPath
          : savedPath as String?,
    );
  }
}

class ConfdbSchemaDocument {
  ConfdbSchemaDocument({
    required this.accountId,
    required this.name,
    required this.summary,
    required this.storage,
    Iterable<ConfdbView> views = const [],
    Map<String, Object?> extraHeaders = const {},
    this.revision,
    this.latestRemote,
    this.origin = const DraftOrigin.newDraft(),
    this.isDirty = false,
    this.artifact,
  })  : views = List.unmodifiable(views),
        extraHeaders = Map.unmodifiable(extraHeaders);

  factory ConfdbSchemaDocument.empty({
    required String accountId,
    required String name,
  }) {
    return ConfdbSchemaDocument(
      accountId: accountId,
      name: name,
      summary: '',
      storage: StorageNode.map(),
    );
  }

  final String accountId;
  final String name;
  final String summary;
  final StorageNode storage;
  final List<ConfdbView> views;
  final Map<String, Object?> extraHeaders;
  final SchemaRevision? revision;
  final SchemaRevision? latestRemote;
  final DraftOrigin origin;
  final bool isDirty;
  final SigningArtifact? artifact;

  ConfdbSchemaDocument copyWith({
    String? accountId,
    String? name,
    String? summary,
    StorageNode? storage,
    Iterable<ConfdbView>? views,
    Map<String, Object?>? extraHeaders,
    Object? revision = _unsetDocumentValue,
    Object? latestRemote = _unsetDocumentValue,
    DraftOrigin? origin,
    bool? isDirty,
    Object? artifact = _unsetDocumentValue,
  }) {
    return ConfdbSchemaDocument(
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      storage: storage ?? this.storage,
      views: views ?? this.views,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      revision: identical(revision, _unsetDocumentValue)
          ? this.revision
          : revision as SchemaRevision?,
      latestRemote: identical(latestRemote, _unsetDocumentValue)
          ? this.latestRemote
          : latestRemote as SchemaRevision?,
      origin: origin ?? this.origin,
      isDirty: isDirty ?? this.isDirty,
      artifact: identical(artifact, _unsetDocumentValue)
          ? this.artifact
          : artifact as SigningArtifact?,
    );
  }
}