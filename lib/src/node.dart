typedef ParamsIndexMap = List<({int index, Pattern name, bool optional})>;

class MatchedRoute<T> {
  final T data;
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
