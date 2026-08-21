const Object _unsetStorageValue = Object();

enum StorageKind { string, integer, number, boolean, map, array, any, alias }

enum StorageVisibility { public, secret }

class StorageNode {
  StorageNode._({
    required this.kind,
    Map<String, StorageNode> children = const {},
    this.items,
    this.alias,
    this.pattern,
    List<Object?> choices = const [],
    this.minimum,
    this.maximum,
    this.visibility,
    this.ephemeral,
    this.required,
    this.uniqueItems,
  })  : children = Map.unmodifiable(children),
        choices = List.unmodifiable(choices);

  factory StorageNode.string({
    String? pattern,
    List<Object?> choices = const [],
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.string,
      pattern: pattern,
      choices: choices,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  factory StorageNode.integer({
    int? minimum,
    int? maximum,
    List<Object?> choices = const [],
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.integer,
      minimum: minimum,
      maximum: maximum,
      choices: choices,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  factory StorageNode.number({
    num? minimum,
    num? maximum,
    List<Object?> choices = const [],
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.number,
      minimum: minimum,
      maximum: maximum,
      choices: choices,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  factory StorageNode.boolean({
    List<Object?> choices = const [],
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.boolean,
      choices: choices,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  factory StorageNode.map({
    Map<String, StorageNode> children = const {},
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.map,
      children: children,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  factory StorageNode.array({
    StorageNode? items,
    bool? uniqueItems,
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.array,
      items: items,
      uniqueItems: uniqueItems,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  factory StorageNode.any({
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.any,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  factory StorageNode.alias({
    required String alias,
    StorageVisibility? visibility,
    bool? ephemeral,
    bool? required,
  }) {
    return StorageNode._(
      kind: StorageKind.alias,
      alias: alias,
      visibility: visibility,
      ephemeral: ephemeral,
      required: required,
    );
  }

  final StorageKind kind;
  final Map<String, StorageNode> children;
  final StorageNode? items;
  final String? alias;
  final String? pattern;
  final List<Object?> choices;
  final num? minimum;
  final num? maximum;
  final StorageVisibility? visibility;
  final bool? ephemeral;
  final bool? required;
  final bool? uniqueItems;

  StorageNode copyWith({
    StorageKind? kind,
    Map<String, StorageNode>? children,
    Object? items = _unsetStorageValue,
    Object? alias = _unsetStorageValue,
    Object? pattern = _unsetStorageValue,
    List<Object?>? choices,
    Object? minimum = _unsetStorageValue,
    Object? maximum = _unsetStorageValue,
    Object? visibility = _unsetStorageValue,
    Object? ephemeral = _unsetStorageValue,
    Object? required = _unsetStorageValue,
    Object? uniqueItems = _unsetStorageValue,
  }) {
    return StorageNode._(
      kind: kind ?? this.kind,
      children: children ?? this.children,
      items: identical(items, _unsetStorageValue) ? this.items : items as StorageNode?,
      alias: identical(alias, _unsetStorageValue) ? this.alias : alias as String?,
      pattern: identical(pattern, _unsetStorageValue)
          ? this.pattern
          : pattern as String?,
      choices: choices ?? this.choices,
      minimum: identical(minimum, _unsetStorageValue)
          ? this.minimum
          : minimum as num?,
      maximum: identical(maximum, _unsetStorageValue)
          ? this.maximum
          : maximum as num?,
      visibility: identical(visibility, _unsetStorageValue)
          ? this.visibility
          : visibility as StorageVisibility?,
      ephemeral: identical(ephemeral, _unsetStorageValue)
          ? this.ephemeral
          : ephemeral as bool?,
      required: identical(required, _unsetStorageValue)
          ? this.required
          : required as bool?,
      uniqueItems: identical(uniqueItems, _unsetStorageValue)
          ? this.uniqueItems
          : uniqueItems as bool?,
    );
  }
}