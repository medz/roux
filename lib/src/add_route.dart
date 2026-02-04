import '_router_utils.dart';
import '_utils.dart';
import 'node.dart';
import 'router.dart';

void addRoute<T>(RouterContext<T> ctx, String? method, String path, [T? data]) {
  final methodToken = normalizeMethod(ctx, method);
  path = normalizePatternPath(path);

  final segments = splitPath(path);
  final matchSegments = normalizeSegments(ctx, segments);

  var node = ctx.root;
  var unnamedParamIndex = 0;

  final paramsMap = <({int index, Pattern name, bool optional})>[];
  final paramsRegexp = <RegExp?>[];

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
