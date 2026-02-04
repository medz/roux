import 'node.dart';

class RouterContext<T> {
  final Node<T> root;
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
