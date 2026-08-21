final RegExp _placeholderPattern = RegExp(r'^\{([A-Za-z][A-Za-z0-9_-]*)\}$');

class ConfdbPath {
  ConfdbPath(Iterable<String> segments) : segments = List.unmodifiable(segments);

  factory ConfdbPath.parse(String value) => ConfdbPath(value.split('.'));

  final List<String> segments;

  Set<String> get placeholders => Set.unmodifiable(
        segments
            .map(_placeholderName)
            .whereType<String>(),
      );

  static String? _placeholderName(String segment) =>
      _placeholderPattern.firstMatch(segment)?.group(1);

  @override
  String toString() => segments.join('.');
}

enum ViewAccess { read, readWrite }

class ConfdbRule {
  const ConfdbRule({
    required this.request,
    required this.storage,
    required this.access,
  });

  final ConfdbPath request;
  final ConfdbPath storage;
  final ViewAccess access;

  Set<String> get placeholders => Set.unmodifiable({
        ...request.placeholders,
        ...storage.placeholders,
      });

  ConfdbRule copyWith({
    ConfdbPath? request,
    ConfdbPath? storage,
    ViewAccess? access,
  }) {
    return ConfdbRule(
      request: request ?? this.request,
      storage: storage ?? this.storage,
      access: access ?? this.access,
    );
  }
}

class ConfdbView {
  ConfdbView({required this.name, Iterable<ConfdbRule> rules = const []})
      : rules = List.unmodifiable(rules);

  final String name;
  final List<ConfdbRule> rules;

  ConfdbView copyWith({String? name, Iterable<ConfdbRule>? rules}) {
    return ConfdbView(name: name ?? this.name, rules: rules ?? this.rules);
  }
}