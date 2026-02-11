import 'node.dart';

/// Opaque router handle that stores lookup structures.
///
/// Treat the fields as implementation details and use the top-level helpers
/// like `addRoute`, `findRoute`, `findAllRoutes`, and `removeRoute`.
///
/// [static] caches full static paths for O(1) exact matches.
/// [root] is the trie root for segmented traversal; each node also has its own
/// `static` map for child segments during trie walks.
class RouterContext<T> {
  final Node<T> root;

  /// Full static path cache for quick exact matches.
  final Map<String, Node<T>> static;

  /// Whether path matching is case-sensitive.
  final bool caseSensitive;

  /// Token representing "any method" registrations.
  final String anyMethodToken;

  /// Uppercased [anyMethodToken] used for normalization.
  final String anyMethodTokenNormalized;

  /// Cache for method token normalization to reduce repeated allocations.
  final Map<String, String> methodCache;

  /// Memoized findRoute results for [params] = true by method and path.
  final Map<String, Map<String, MatchedRoute<T>?>> findRouteCacheWithParams;

  /// Memoized findRoute results for [params] = false by method and path.
  final Map<String, Map<String, MatchedRoute<T>?>> findRouteCacheWithoutParams;

  /// Incremented on route mutations to invalidate cached lookups lazily.
  int mutationVersion;

  /// The mutation version the current caches are built for.
  int cacheVersion;

  RouterContext({
    required this.root,
    required this.static,
    required this.caseSensitive,
    required this.anyMethodToken,
    required this.methodCache,
    required this.findRouteCacheWithParams,
    required this.findRouteCacheWithoutParams,
    required this.mutationVersion,
    required this.cacheVersion,
  }) : anyMethodTokenNormalized = anyMethodToken.toUpperCase();
}

/// Creates a new [RouterContext].
///
/// When [caseSensitive] is false, path matching lowercases segments. The
/// [anyMethodToken] is the token used to register "any method" routes.
RouterContext<T> createRouter<T>({
  bool caseSensitive = true,
  String anyMethodToken = 'any',
}) {
  return RouterContext<T>(
    root: Node<T>(),
    static: <String, Node<T>>{},
    caseSensitive: caseSensitive,
    anyMethodToken: anyMethodToken,
    methodCache: <String, String>{},
    findRouteCacheWithParams: <String, Map<String, MatchedRoute<T>?>>{},
    findRouteCacheWithoutParams: <String, Map<String, MatchedRoute<T>?>>{},
    mutationVersion: 0,
    cacheVersion: 0,
  );
}
