import 'node.dart';

/// Router context holding lookup structures.
///
/// [static] caches full static paths for O(1) exact matches.
/// [root] is the trie root for segmented traversal; each node also has its own
/// `static` map for child segments during trie walks.
class RouterContext<T> {
  final Node<T> root;

  /// Full static path cache for quick exact matches.
  final Map<String, Node<T>> static;
  final bool caseSensitive;
  final String anyMethodToken;
  final String anyMethodTokenNormalized;

  RouterContext({
    required this.root,
    required this.static,
    required this.caseSensitive,
    required this.anyMethodToken,
  }) : anyMethodTokenNormalized = anyMethodToken.toUpperCase();
}

RouterContext<T> createRouter<T>({
  bool caseSensitive = true,
  String anyMethodToken = 'any',
}) {
  return RouterContext<T>(
    root: Node<T>(key: ''),
    static: <String, Node<T>>{},
    caseSensitive: caseSensitive,
    anyMethodToken: anyMethodToken,
  );
}
