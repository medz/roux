import '_router_utils.dart';
import '_utils.dart';
import 'node.dart';
import 'router.dart';

const _pendingRoutesFlushThreshold = 3072 * 3;

/// Registers a route pattern on [ctx] for [method].
///
/// The [path] supports:
/// - static segments: `/users`
/// - named params: `/users/:id`
/// - embedded params: `/files/:name.:ext`
/// - single-segment wildcards: `*`
/// - multi-segment wildcards: `**` or `**:path`
///
/// `**` can match an empty remainder; `**:name` requires at least one segment.
/// Escape literal `:` or `*` with a backslash, for example
/// `/static\\:path/\\*/\\*\\*`.
///
/// If [T] is non-nullable, [data] is required.
void addRoute<T>(RouterContext<T> ctx, String? method, String path, [T? data]) {
  markFindRouteCacheDirty(ctx);
  final routeData = requireData(data);
  ctx.pendingRoutes
    ..add(method)
    ..add(path)
    ..add(routeData);

  if (ctx.pendingRoutes.length >= _pendingRoutesFlushThreshold) {
    materializePendingRoutes(ctx);
  }
}

void materializePendingRoutes<T>(RouterContext<T> ctx) {
  final pendingRoutes = ctx.pendingRoutes;
  if (pendingRoutes.isEmpty) {
    return;
  }

  for (var i = 0; i < pendingRoutes.length; i += 3) {
    _addRouteToTrie(
      ctx,
      pendingRoutes[i] as String?,
      pendingRoutes[i + 1] as String,
      pendingRoutes[i + 2] as T,
    );
  }
  pendingRoutes.clear();
}

void _addRouteToTrie<T>(
  RouterContext<T> ctx,
  String? method,
  String path,
  T routeData,
) {
  final methodToken = normalizeMethod(ctx, method);
  path = normalizePatternPath(path);

  switch (_classifyPatternPath(path)) {
    case _PatternPathKind.plainStatic:
      _addPlainStaticRoute(ctx, methodToken, path, routeData);
      return;
    case _PatternPathKind.simpleParam:
      _addSimpleParamRoute(ctx, methodToken, path, routeData);
      return;
    case _PatternPathKind.complex:
      break;
  }

  final segments = splitPath(path);
  final matchSegments = normalizeSegments(ctx, segments);

  var node = ctx.root;
  var unnamedParamIndex = 0;

  List<({int index, Pattern name, bool optional})>? paramsMap;
  var paramsRegexp = const <RegExp?>[];

  for (var i = 0; i < segments.length; i++) {
    var segment = segments[i];
    var matchSegment = matchSegments[i];

    // Wildcard
    if (segment.startsWith('**')) {
      node = node.wildcard ??= Node<T>();
      final parts = segment.split(':');
      final name = parts.length > 1 ? parts[1] : '_';
      paramsMap ??= <({int index, Pattern name, bool optional})>[];
      paramsMap.add((
        index: -(i + 1),
        name: name,
        optional: segment.length == 2,
      ));
      break;
    }

    // Param
    if (segment == '*' || segment.contains(':')) {
      if (segment == ':') {
        final child = node.static?[segment];
        if (child != null) {
          node = child;
          continue;
        }

        final staticNode = Node<T>();
        node.static ??= <String, Node<T>>{};
        node.static![segment] = staticNode;
        node = staticNode;
        continue;
      }
      node = node.param ??= Node<T>();
      paramsMap ??= <({int index, Pattern name, bool optional})>[];
      if (segment == '*') {
        paramsMap.add((
          index: i,
          name: '_${unnamedParamIndex++}',
          optional: true,
        ));
      } else if (segment.contains(':', 1)) {
        // Treat any additional ':' after the first as embedded params
        // (e.g. /files/:name.:ext). This is intentional even if it also
        // matches segments like a:b.
        final regexp = getParamRegexp(ctx, segment);
        if (paramsRegexp.isEmpty) {
          paramsRegexp = <RegExp?>[];
        }
        setParamRegexp(paramsRegexp, i, regexp);
        node.hasRegexParam = true;
        paramsMap.add((index: i, name: regexp, optional: false));
      } else {
        paramsMap.add((index: i, name: segment.substring(1), optional: false));
      }
      continue;
    }

    // Static
    if (segment == r'\*') {
      matchSegment = '*';
      matchSegments[i] = matchSegment;
    } else if (segment == r'\*\*') {
      matchSegment = '**';
      matchSegments[i] = matchSegment;
    }

    final child = node.static?[matchSegment];
    if (child != null) {
      node = child;
      continue;
    }

    final staticNode = Node<T>();
    node.static ??= <String, Node<T>>{};
    node.static![matchSegment] = staticNode;
    node = staticNode;
  }

  final hasParams = paramsMap != null;
  final bucket = getOrCreateMethodBucket(node, methodToken);
  bucket.add(
    MethodData<T>(
      data: routeData,
      paramsRegexp: paramsRegexp,
      paramsMap: paramsMap,
    ),
  );

  if (!hasParams) {
    ctx.static[_buildStaticCachePath(ctx, path, matchSegments)] = node;
  }
}

enum _PatternPathKind { plainStatic, simpleParam, complex }

_PatternPathKind _classifyPatternPath(String path) {
  var sawParam = false;

  for (var i = 0; i < path.length; i++) {
    final code = path.codeUnitAt(i);
    if (code == 42) {
      // '*'
      return _PatternPathKind.complex;
    }
    if (code != 58) {
      continue;
    }

    sawParam = true;
    if (i == 0 || path.codeUnitAt(i - 1) != 47) {
      return _PatternPathKind.complex;
    }
    if (i + 1 >= path.length || path.codeUnitAt(i + 1) == 47) {
      return _PatternPathKind.complex;
    }

    i += 1;
    for (; i < path.length && path.codeUnitAt(i) != 47; i++) {
      final innerCode = path.codeUnitAt(i);
      if (innerCode == 58 || innerCode == 42) {
        return _PatternPathKind.complex;
      }
    }
  }

  return sawParam ? _PatternPathKind.simpleParam : _PatternPathKind.plainStatic;
}

void _addPlainStaticRoute<T>(
  RouterContext<T> ctx,
  String methodToken,
  String path,
  T routeData,
) {
  final staticPath = normalizeStaticCachePath(normalizePath(ctx, path));
  final node = ctx.static[staticPath] ??= Node<T>();
  final bucket = getOrCreateMethodBucket(node, methodToken);
  bucket.add(MethodData<T>(data: routeData, paramsRegexp: const <RegExp?>[]));
}

void _addSimpleParamRoute<T>(
  RouterContext<T> ctx,
  String methodToken,
  String path,
  T routeData,
) {
  final length = path.length;
  var start = 1;
  var segmentIndex = 0;
  var node = ctx.root;

  final paramsMap = <({int index, Pattern name, bool optional})>[];

  for (var i = 1; i <= length; i++) {
    if (i != length && path.codeUnitAt(i) != 47) {
      continue;
    }
    if (i == length && start == i) {
      break;
    }

    if (path.codeUnitAt(start) == 58) {
      node = node.param ??= Node<T>();
      paramsMap.add((
        index: segmentIndex,
        name: path.substring(start + 1, i),
        optional: false,
      ));
    } else {
      final staticMap = node.static;
      if (staticMap != null) {
        final existingKey = _findExistingStaticKey(
          staticMap,
          path,
          start,
          i,
          ctx.caseSensitive,
        );
        if (existingKey != null) {
          node = staticMap[existingKey]!;
          start = i + 1;
          segmentIndex += 1;
          continue;
        }
      }

      final segment = path.substring(start, i);
      final matchSegment = ctx.caseSensitive ? segment : segment.toLowerCase();
      if (staticMap != null) {
        final child = staticMap[matchSegment];
        if (child != null) {
          node = child;
        } else {
          final staticNode = Node<T>();
          staticMap[matchSegment] = staticNode;
          node = staticNode;
        }
      } else {
        final staticNode = Node<T>();
        node.static ??= <String, Node<T>>{};
        node.static![matchSegment] = staticNode;
        node = staticNode;
      }
    }

    start = i + 1;
    segmentIndex += 1;
  }

  final bucket = getOrCreateMethodBucket(node, methodToken);
  bucket.add(
    MethodData<T>(
      data: routeData,
      paramsRegexp: const <RegExp?>[],
      paramsMap: paramsMap,
    ),
  );
}

String? _findExistingStaticKey<T>(
  Map<String, Node<T>> staticMap,
  String path,
  int start,
  int end,
  bool caseSensitive,
) {
  if (staticMap.isEmpty || staticMap.length > 4) {
    return null;
  }

  final length = end - start;
  for (final key in staticMap.keys) {
    if (key.length != length) {
      continue;
    }

    var matched = true;
    for (var i = 0; i < length; i++) {
      var code = path.codeUnitAt(start + i);
      if (!caseSensitive && code >= 65 && code <= 90) {
        code += 32;
      }
      if (key.codeUnitAt(i) != code) {
        matched = false;
        break;
      }
    }

    if (matched) {
      return key;
    }
  }
  return null;
}

String _buildStaticCachePath<T>(
  RouterContext<T> ctx,
  String path,
  List<String> matchSegments,
) {
  if (!path.contains(r'\*')) {
    final normalizedPath = normalizePath(ctx, path);
    if (normalizedPath.length > 1 &&
        normalizedPath.codeUnitAt(normalizedPath.length - 1) == 47) {
      return normalizedPath.substring(0, normalizedPath.length - 1);
    }
    return normalizedPath;
  }
  return '/${matchSegments.join('/')}';
}
