import '_router_utils.dart';
import '_utils.dart';
import 'node.dart';
import 'router.dart';

/// Removes a route for [method] and [path].
///
/// If [path] is null, removes all routes registered for [method]. When [method]
/// is null or empty, the any-method token is used.
void removeRoute<T>(RouterContext<T> ctx, String? method, String? path) {
  clearFindRouteCaches(ctx);
  final methodToken = normalizeMethod(ctx, method);

  if (path == null) {
    _removeAll(ctx.root, methodToken);
    for (final entry in ctx.static.entries.toList()) {
      _removeMethodFromNode(entry.value, methodToken);
      if (_isEmptyNode(entry.value)) {
        ctx.static.remove(entry.key);
      }
    }
    return;
  }

  path = normalizePatternPath(path);
  final matchPath = normalizePath(ctx, path);
  if (_isPlainStaticPath(path)) {
    _removeStaticRoute(ctx, methodToken, matchPath);
    return;
  }

  final segments = splitPath(matchPath);
  _remove(ctx.root, methodToken, segments, 0);
}

void _remove<T>(
  Node<T> node,
  String methodToken,
  List<String> segments,
  int index,
) {
  if (index == segments.length) {
    _removeMethodFromNode(node, methodToken);
    return;
  }

  var segment = segments[index];

  // Param
  if (segment == '*') {
    if (node.param != null) {
      _remove(node.param!, methodToken, segments, index + 1);
      if (_isEmptyNode(node.param!)) {
        node.param = null;
      }
    }
    return;
  }

  // Wildcard
  if (segment.startsWith('**')) {
    if (node.wildcard != null) {
      _remove(node.wildcard!, methodToken, segments, index + 1);
      if (_isEmptyNode(node.wildcard!)) {
        node.wildcard = null;
      }
    }
    return;
  }

  // Param (named)
  if (segment.contains(':')) {
    if (node.param != null) {
      _remove(node.param!, methodToken, segments, index + 1);
      if (_isEmptyNode(node.param!)) {
        node.param = null;
      }
    }
    return;
  }

  // Static (including escaped stars)
  if (segment == r'\*') {
    segment = '*';
  } else if (segment == r'\*\*') {
    segment = '**';
  }

  final childNode = node.static?[segment];
  if (childNode != null) {
    _remove(childNode, methodToken, segments, index + 1);
    if (_isEmptyNode(childNode)) {
      node.static!.remove(segment);
      if (node.static!.isEmpty) {
        node.static = null;
      }
    }
  }
}

bool _removeAll<T>(Node<T> node, String methodToken) {
  _removeMethodFromNode(node, methodToken);

  if (node.param != null && _removeAll(node.param!, methodToken)) {
    node.param = null;
  }
  if (node.wildcard != null && _removeAll(node.wildcard!, methodToken)) {
    node.wildcard = null;
  }
  if (node.static != null) {
    for (final entry in node.static!.entries.toList()) {
      if (_removeAll(entry.value, methodToken)) {
        node.static!.remove(entry.key);
      }
    }
    if (node.static!.isEmpty) {
      node.static = null;
    }
  }

  return _isEmptyNode(node);
}

bool _isEmptyNode<T>(Node<T> node) {
  return node.singleMethodBucket == null &&
      node.methods == null &&
      node.static == null &&
      node.param == null &&
      node.wildcard == null;
}

bool _isPlainStaticPath(String path) {
  return !path.contains(':') && !path.contains('*');
}

void _removeStaticRoute<T>(
  RouterContext<T> ctx,
  String methodToken,
  String normalizedPath,
) {
  final staticPath = normalizeStaticCachePath(normalizedPath);
  final node = ctx.static[staticPath];
  if (node == null) {
    return;
  }

  _removeMethodFromNode(node, methodToken);
  if (_isEmptyNode(node)) {
    ctx.static.remove(staticPath);
  }
}

void _removeMethodFromNode<T>(Node<T> node, String methodToken) {
  final methods = node.methods;
  if (methods != null) {
    if (!methods.containsKey(methodToken)) {
      return;
    }

    methods.remove(methodToken);
    if (methods.isEmpty) {
      node.methods = null;
      return;
    }

    if (methods.length == 1) {
      final entry = methods.entries.first;
      node.singleMethodToken = entry.key;
      node.singleMethodBucket = entry.value;
      node.methods = null;
    }
    return;
  }

  if (node.singleMethodToken == methodToken) {
    node.singleMethodToken = null;
    node.singleMethodBucket = null;
  }
}
