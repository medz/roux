import '_router_utils.dart';
import '_utils.dart';
import 'node.dart';
import 'router.dart';

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
  final methodToken = normalizeMethod(ctx, method);
  path = normalizePatternPath(path);
  final routeData = requireData(data);

  if (_isPlainStaticPattern(path)) {
    _addPlainStaticRoute(ctx, methodToken, path, routeData);
    return;
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
      node = node.wildcard ??= Node<T>(key: '**');
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
      node = node.param ??= Node<T>(key: '*');
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

    final staticNode = Node<T>(key: matchSegment);
    node.static ??= <String, Node<T>>{};
    node.static![matchSegment] = staticNode;
    node = staticNode;
  }

  final hasParams = paramsMap != null;
  node.methods ??= <String, List<MethodData<T>>>{};
  final bucket = node.methods!.putIfAbsent(
    methodToken,
    () => <MethodData<T>>[],
  );
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

bool _isPlainStaticPattern(String path) {
  return !path.contains(':') && !path.contains('*');
}

void _addPlainStaticRoute<T>(
  RouterContext<T> ctx,
  String methodToken,
  String path,
  T routeData,
) {
  final matchPath = normalizePath(ctx, path);
  final length = matchPath.length;
  var start = 1;
  var node = ctx.root;

  for (var i = 1; i <= length; i++) {
    if (i != length && matchPath.codeUnitAt(i) != 47) {
      continue;
    }
    if (i == length && start == i) {
      break;
    }

    final segment = matchPath.substring(start, i);
    var staticMap = node.static;
    if (staticMap == null) {
      final child = Node<T>(key: segment);
      staticMap = <String, Node<T>>{segment: child};
      node.static = staticMap;
      node = child;
    } else {
      node = staticMap[segment] ??= Node<T>(key: segment);
    }
    start = i + 1;
  }

  node.methods ??= <String, List<MethodData<T>>>{};
  final bucket = node.methods!.putIfAbsent(
    methodToken,
    () => <MethodData<T>>[],
  );
  bucket.add(MethodData<T>(data: routeData, paramsRegexp: const <RegExp?>[]));

  if (length > 1 && matchPath.codeUnitAt(length - 1) == 47) {
    ctx.static[matchPath.substring(0, length - 1)] = node;
  } else {
    ctx.static[matchPath] = node;
  }
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
