import '_router_utils.dart';
import '_utils.dart';
import 'node.dart';
import 'router.dart';

void removeRoute<T>(RouterContext<T> ctx, String? method, String? path) {
  final methodToken = normalizeMethod(ctx, method);

  if (path == null) {
    _removeAll(ctx.root, methodToken);
    return;
  }

  path = normalizePatternPath(path);
  final matchPath = normalizePath(ctx, path);
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
    if (node.methods != null && node.methods!.containsKey(methodToken)) {
      node.methods!.remove(methodToken);
      if (node.methods!.isEmpty) {
        node.methods = null;
      }
    }
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
  if (node.methods != null && node.methods!.containsKey(methodToken)) {
    node.methods!.remove(methodToken);
    if (node.methods!.isEmpty) {
      node.methods = null;
    }
  }

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
  return node.methods == null &&
      node.static == null &&
      node.param == null &&
      node.wildcard == null;
}
