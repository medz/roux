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

  final segments = splitPath(path);
  final matchSegments = normalizeSegments(ctx, segments);

  var node = ctx.root;
  var unnamedParamIndex = 0;

  final paramsMap = <({int index, Pattern name, bool optional})>[];
  final paramsRegexp = <RegExp?>[];
  final keySegments = ctx.caseSensitive
      ? segments
      : segments.map((segment) => segment.toLowerCase()).toList();
  final routeKey = '$methodToken /${keySegments.join('/')}';

  for (var i = 0; i < segments.length; i++) {
    var segment = segments[i];
    var matchSegment = matchSegments[i];

    // Wildcard
    if (segment.startsWith('**')) {
      node = node.wildcard ??= Node<T>(key: '**');
      final parts = segment.split(':');
      final name = parts.length > 1 ? parts[1] : '_';
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

  final hasParams = paramsMap.isNotEmpty;
  node.methods ??= <String, List<MethodData<T>>>{};
  final bucket = node.methods!.putIfAbsent(
    methodToken,
    () => <MethodData<T>>[],
  );
  bucket.add(
    MethodData<T>(
      key: routeKey,
      data: requireData(data),
      paramsRegexp: paramsRegexp,
      paramsMap: hasParams ? paramsMap : null,
    ),
  );

  if (!hasParams) {
    final staticPath = '/${matchSegments.join('/')}';
    ctx.static[staticPath] = node;
  }
}
