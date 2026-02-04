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
