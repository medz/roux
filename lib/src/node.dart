typedef ParamsIndexMap = List<({int index, Pattern name, bool optional})>;

/// Result returned from route lookup.
///
/// [data] is the value associated with the matched route.
/// [params] contains extracted parameters when the route uses `:name`, `*`,
/// or `**` segments.
class MatchedRoute<T> {
  /// Data associated with the matched route.
  final T data;

  /// Extracted parameters for the match, if any.
  ///
  /// Named params use their names. Unnamed `*` segments are `_0`, `_1`, ...;
  /// `**` uses `_` unless a name is provided (e.g. `**:path`).
  final Map<String, String>? params;

  const MatchedRoute(this.data, [this.params]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MatchedRoute<T> &&
        other.data == data &&
        _mapEquals(other.params, params);
  }

  @override
  int get hashCode => Object.hash(data, _mapHash(params));
}

bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
  if (a == null || b == null) {
    return a == b;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _mapHash(Map<String, String>? map) {
  if (map == null) {
    return 0;
  }
  var hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}

class MethodData<T> {
  final String key;
  final T data;
  final ParamsIndexMap? paramsMap;
  final List<RegExp?> paramsRegexp;

  MethodData({
    required this.key,
    required this.data,
    required this.paramsRegexp,
    this.paramsMap,
  });
}

class Node<T> {
  final String key;

  Map<String, Node<T>>? static;
  Node<T>? param;
  Node<T>? wildcard;

  bool hasRegexParam;

  Map<String, List<MethodData<T>>>? methods;

  Node({
    required this.key,
    this.static,
    this.param,
    this.wildcard,
    this.hasRegexParam = false,
    this.methods,
  });
}
