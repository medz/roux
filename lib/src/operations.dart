// ignore_for_file: public_member_api_docs

import 'model.dart';
import 'path.dart';
import 'segment_program.dart';

Iterable<List<String>> _patterns(String path, {bool expandedPath = false}) {
  Iterable<List<String>> expand(List<String> paths) =>
      paths.expand((next) => _patterns(next, expandedPath: true));
  if (path.contains('{')) {
    if (!expandedPath) path = '/${normalizedSegments(path).join('/')}';
    var start = -1, depth = 0;
    for (final token in _syntax.allMatches(path)) {
      final unit = token[0];
      if (unit == '(') {
        depth++;
      } else if (unit == ')' && depth > 0) {
        depth--;
      } else if (unit == '{' && depth == 0 && start < 0) {
        start = token.start;
      } else if (unit == '}' && depth == 0 && start >= 0) {
        final body = path.substring(start + 1, token.start), end = token.end;
        final optional = path.startsWith('?', end);
        final repeat = path.startsWith('+', end) || path.startsWith('*', end);
        if (repeat && body.contains('/')) {
          throw FormatException('Unsupported group repetition across segments');
        }
        final after = optional ? end + 1 : end;
        return expand([
          path.replaceRange(start, after, repeat ? '(?:$body)' : body),
          if (optional) path.replaceRange(start, after, ''),
        ]);
      }
    }
    if (start >= 0) throw FormatException('Unclosed group in route: $path');
    expandedPath = true;
  }
  path = encodeEscapes(path);
  final parts = expandedPath
      ? (path.split('/')..removeAt(0))
      : normalizedSegments(path);
  if (expandedPath && parts.lastOrNull == '') parts.removeLast();
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty) continue;
    final last = part.codeUnitAt(part.length - 1);
    if (last != 63 && last != 43 && last != 42) continue; // ?, +, *
    final m = _modifierRx.firstMatch(part);
    if (m == null) continue;
    parts[i] = last == 63 ? m[1]! : '**${_restName.stringMatch(part)}';
    final included = '/${parts.join('/')}';
    if (last == 43) return expand([included]);
    parts.removeAt(i);
    return expand([included, '/${parts.join('/')}']);
  }
  return [parts];
}

// dart format off
void addRoute<T>(RouterNode<T> root, bool caseSensitive, String method, String path, T data) {// dart format on
  for (final segments in _patterns(path)) {
    var node = root;
    final route = RouteData(method, data);
    List<Object>? params;
    var nextCapture = 0, unnamedIndex = 0;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];

      final key = _literalKey(segment, caseSensitive);
      if (key != null) {
        final children = node.statics ??= RouterNode<T>(key);
        node = children[key] ?? children.addSibling(RouterNode<T>(key));
        continue;
      }
      final rest = segment.startsWith('**');
      node = rest
          ? (node.wildcard ??= RouterNode<T>())
          : (node.param ??= RouterNode<T>());
      final Object capture;
      if (rest) {
        final optional = segment == '**';
        final name = optional ? '_' : segment.substring(3);
        if (!_isName(name)) {
          throw FormatException('Invalid wildcard param name: $path');
        }
        capture = Wildcard(i, normalizeUnnamedGroupKey(name), optional, true);
      } else if (segment == '*') {
        capture = Wildcard(i, '${unnamedIndex++}', true, false);
      } else if (segment.startsWith(':') && _isName(segment, 1)) {
        capture = normalizeUnnamedGroupKey(segment.substring(1));
      } else {
        final (pattern, next) = compileSegmentPattern(
          segment,
          caseSensitive,
          unnamedIndex,
        );
        capture = route.lastConstraint = pattern;
        route.constraintDepth = i + 1;
        unnamedIndex = next;
      }
      final plan = params ??= [];
      if (i > nextCapture && capture is! Wildcard) plan.add(i - nextCapture);
      plan.add(capture);
      nextCapture = i + 1;
      if (rest) break;
    }

    if (params != null) route.params = params.toList(growable: false);
    final methods = node.methods ??= route;
    final first = methods[method] ?? methods.addSibling(route);
    if (!identical(first, route)) {
      (first.alternatives ??= RouteBucket<T>(first)).add(route);
    }
  }
}

// dart format off
RouteMatch<T>? findRoute<T>(RouterNode<T> node, bool caseSensitive, String method, List<String> segments, [int index = 0]) {// dart format on
  while (index < segments.length) {
    final child = node.staticChild(segments[index++], caseSensitive);
    final param = node.param, wildcard = node.wildcard;
    if (child != null && param != null) {
      final match = findRoute(child, caseSensitive, method, segments, index);
      if (match != null) return match;
    }
    final next = param ?? child;
    if (next == null) {
      return wildcard == null ? null : _select(wildcard, method, segments);
    }
    if (wildcard != null) {
      return findRoute(next, caseSensitive, method, segments, index) ??
          _select(wildcard, method, segments);
    }
    node = next;
  }
  return _select(node, method, segments) ??
      _select(node.param, method, segments, optionalTail: true) ??
      _select(node.wildcard, method, segments, optionalTail: true);
}

// dart format off
RouteMatch<T>? _select<T>(RouterNode<T>? node, String method, List<String> segments, {bool optionalTail = false}) {// dart format on
  final first = node?.methods?.forMethod(method);
  if (first == null) return null;
  final routes = first.alternatives?.candidates(segments);
  if (routes == null || routes.length == 1) {
    return (routes?.first ?? first).match(segments, optionalTail: optionalTail);
  }
  RouteMatch<T>? best;
  var bestDepth = -1;
  for (final route in routes) {
    final depth = route.constraintDepth;
    if (depth <= bestDepth) continue;
    final found = route.match(segments, optionalTail: optionalTail);
    if (found == null) continue;
    if (route.params.isEmpty || depth == segments.length) return found;
    best = found;
    bestDepth = depth;
  }
  return best;
}

// dart format off
List<RouteMatch<T>> findAllRoutes<T>(RouterNode<T> root, bool caseSensitive, String method, String path, bool includeAny) {// dart format on
  final segments = normalizedSegments(path);
  final matches = <RouteMatch<T>>[];

  void append(RouteData<T>? first, bool optionalTail) {
    if (first == null) return;
    final routes = first.alternatives?.routes;
    for (var i = 0; i < (routes?.length ?? 1); i++) {
      final route = routes == null ? first : routes[i];
      if (route.match(segments, allowPartial: true, optionalTail: optionalTail)
          case final found?) {
        matches.add(found);
      }
    }
  }

  void collect(RouterNode<T>? child, {bool optionalTail = false}) {
    final methods = child?.methods;
    if (methods == null) return;
    if (includeAny && method.isNotEmpty) append(methods[''], optionalTail);
    append(methods[method] ?? (includeAny ? null : methods['']), optionalTail);
  }

  void visit(RouterNode<T>? node, int index) {
    while (node != null) {
      collect(node.wildcard);
      if (index == segments.length) {
        collect(node.param, optionalTail: true);
        collect(node);
        return;
      }
      final child = node.staticChild(segments[index++], caseSensitive);
      final param = node.param;
      if (param != null && child != null) visit(param, index);
      node = child ?? param;
    }
  }

  visit(root, 0);
  return matches;
}

// dart format off
bool removeRoute<T>(RouterNode<T> root, bool caseSensitive, String method, String path) {// dart format on
  var removed = false;
  for (final segments in _patterns(path)) {
    if (_remove(root, method, segments, 0, caseSensitive)) removed = true;
  }
  return removed;
}

// dart format off
bool _remove<T>(RouterNode<T> node, String method, List<String> segments, int index, bool caseSensitive) {// dart format on
  if (index == segments.length) {
    final methods = node.methods;
    if (methods?[method] == null) return false;
    node.methods = methods!.without(method);
    return true;
  }

  final segment = segments[index];
  final key = _literalKey(segment, caseSensitive);
  final wildcard = key == null && segment.startsWith('**');
  final child = switch (key) {
    final value? => node.statics?[value],
    null => wildcard ? node.wildcard : node.param,
  };
  if (child == null) return false;
  final removed = _remove(child, method, segments, index + 1, caseSensitive);
  if (!child.isEmpty) return removed;
  if (key != null) {
    node.statics = node.statics!.without(key);
  } else if (wildcard) {
    node.wildcard = null;
  } else {
    node.param = null;
  }

  return removed;
}

final _syntax = RegExp(r'\\[\s\S]|[(){}*]');
final _regexSyntax = RegExp(
  r'\\[\s\S]?|\[(?:\\[\s\S]|[^\]\\])*(?:\]|\\?$)|[()]',
);
String? _literalKey(String segment, bool sensitive) {
  var escaped = false;
  for (var i = 0; i < segment.length; i++) {
    final c = segment.codeUnitAt(i);
    if (c == 58 || c == 40 || (c == 42 && !escaped)) return null;
    escaped = c == 92 && !escaped;
  }
  final value = segment == r'\*' || segment == r'\*\*'
      ? segment.replaceAll(r'\', '')
      : decodeEscaped(segment);
  return sensitive ? value : value.toLowerCase();
}

final _name = RegExp(r'[A-Za-z_][\w-]*');
final _segmentTokens = RegExp(':(${_name.pattern})|[:(*]|([^:*]+)');
bool _isName(String text, [int start = 0]) =>
    _name.matchAsPrefix(text, start)?.end == text.length;

final _restName = RegExp(r':[\w-]+');
final _modifierRx = RegExp(r'^(.*:[\w-]+(?:\([^)]*\))?)([?+*])$');

// dart format off
(SegmentPattern, int) compileSegmentPattern(String segment, bool caseSensitive, int unnamedIndex) {// dart format on
  final regex = StringBuffer();
  final captures = <CaptureGroup>[];
  final useNames = segment.contains('(?<');
  CaptureGroup group(String? name, int index) => CaptureGroup(
    name ?? '$unnamedGroupPrefix${unnamedIndex++}',
    useNames ? null : index,
  );
  CaptureGroup? outer;
  var cursor = 0;
  var tokens = 0;
  var plainParams = 0;
  var head = '';
  String? separator;

  while (cursor < segment.length) {
    tokens++;
    final token = _segmentTokens.matchAsPrefix(segment, cursor)!;
    cursor = token.end;
    if (token[2] case final text?) {
      final literal = decodeEscaped(text);
      if (tokens == 1) head = literal;
      if (tokens == 2 &&
          (caseSensitive || literal.toLowerCase() == literal.toUpperCase())) {
        separator = literal;
      }
      regex.write(RegExp.escape(literal));
      continue;
    }
    final part = token[0]!;
    if (part == ':') throw FormatException('Invalid param name: $segment');
    final named = token[1];
    var position = captures.length + 1;
    outer = group(named, position);
    if (named == null) captures.add(outer);
    var body = r'[^/]+';
    if (part == '*') {
      body = r'[^/]*';
    } else if (part == '(' || segment.startsWith('(', cursor)) {
      var copied = (part == '(' ? token.start : cursor) + 1, depth = 0;
      StringBuffer? rewritten;
      cursor = -1;
      for (final mark in _regexSyntax.allMatches(segment, copied)) {
        if (mark[0] == '(') {
          depth++;
          if (segment.startsWith('?', mark.end)) continue;
          final inner = group(null, ++position);
          captures.add(inner);
          (rewritten ??= StringBuffer())
            ..write(segment.substring(copied, mark.end))
            ..write('?<${inner.name}>');
          copied = mark.end;
        } else if (mark[0] == ')' && depth-- == 0) {
          final tail = segment.substring(copied, mark.start);
          body = rewritten == null ? tail : (rewritten..write(tail)).toString();
          cursor = mark.end;
          break;
        }
      }
      if (cursor < 0) {
        throw FormatException('Unclosed regex in route: $segment');
      }
    } else {
      plainParams++;
    }
    regex.write('(?<${outer.name}>$body)');
    if (tokens == 1) head = body;
    if (named != null) captures.add(outer);
  }

  if (tokens == 1) outer?.index = 0;
  final split = tokens == 3 && plainParams == 2 ? separator : null;
  return (
    SegmentPattern(regex.toString(), head, caseSensitive, captures, split),
    unnamedIndex,
  );
}

const _reserved = ':(){}', _tags = 'ABCDE';
final _escaped = RegExp(r'\\([:(){}])'), _encoded = RegExp('\uFFFD([A-E])');

String encodeEscapes(String path) => !path.contains(r'\')
    ? path
    : path.replaceAllMapped(
        _escaped,
        (m) => '\uFFFD${_tags[_reserved.indexOf(m[1]!)]}',
      );

String decodeEscaped(String segment) => !segment.contains('\uFFFD')
    ? segment
    : segment.replaceAllMapped(
        _encoded,
        (m) => _reserved[_tags.indexOf(m[1]!)],
      );
