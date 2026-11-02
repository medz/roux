// ignore_for_file: public_member_api_docs

import 'model.dart';
import 'path.dart';
import 'segment_program.dart';

String normalizeMethod(String? method) => method?.trim().toUpperCase() ?? '';

Iterable<List<String>> _patterns(String path, {bool expandedPath = false}) {
  if (!expandedPath && path.contains('{')) {
    path = '/${normalizedSegments(path).join('/')}';
    expandedPath = true;
  }
  var expanded = expandGroupDelimiters(path);
  if (expanded == null) {
    path = encodeEscapes(path);
    final segments = expandedPath ? splitPath(path) : normalizedSegments(path);
    expanded = expandModifiers(segments);
    if (expanded == null) return [segments];
  }
  return expanded.expand((next) => _patterns(next, expandedPath: true));
}

// dart format off
void addRoute<T>(RouterNode<T> root, bool caseSensitive, String method, String path, T data) {// dart format on
  for (final segments in _patterns(path)) {
    var node = root;
    var unnamedIndex = 0;
    final params = <ParamSpec>[];
    var constraintDepth = 0;
    SegmentPattern? lastConstraint;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];

      if (segment.startsWith('**')) {
        node = node.wildcard ??= RouterNode<T>();
        final optional = segment.length == 2;
        final name = optional ? '_' : segment.substring(3);
        if (_name.matchAsPrefix(name)?.end != name.length) {
          throw FormatException('Invalid wildcard param name: $path');
        }
        params.add(ParamSpec(i, name, optional, rest: true));
        break;
      }

      if (_isParamSegment(segment)) {
        node = node.param ??= RouterNode<T>();

        if (segment == '*') {
          params.add(ParamSpec(i, '$unnamedIndex', true));
          unnamedIndex++;
        } else if (!_simpleParamRx.hasMatch(segment)) {
          // dart format off
        final (pattern, nextUnnamed) = compileSegmentPattern(segment, caseSensitive, unnamedIndex); // dart format on
          unnamedIndex = nextUnnamed;
          constraintDepth = i + 1;
          lastConstraint = pattern;
          params.add(ParamSpec(i, pattern, false));
        } else {
          params.add(ParamSpec(i, segment.substring(1), false));
        }
        continue;
      }

      final key = _staticKey(segment, caseSensitive);
      final children = node.statics ??= RouteIndex(key);
      node = children.putIfAbsent(key, RouterNode<T>.new);
    }

    final route = RouteData(data, params, constraintDepth, lastConstraint);
    final methods = node.methods ??= RouteIndex(method);
    methods.putIfAbsent(method, RouteBucket<T>.new).add(route);
  }
}

// dart format off
RouteMatch<T>? findRoute<T>(RouterNode<T>? node, bool caseSensitive, String method, List<String> segments, [int index = 0]) {// dart format on
  while (node != null && index < segments.length) {
    final child = node.staticChild(segments[index++], caseSensitive);
    final param = node.param;
    if (node.wildcard != null || (child != null && param != null)) {
      return findRoute(child, caseSensitive, method, segments, index) ??
          findRoute(param, caseSensitive, method, segments, index) ??
          _selectRoute(node.wildcard, method, segments);
    }
    node = child ?? param;
  }
  if (node == null) return null;
  return _selectRoute(node, method, segments) ??
      _selectRoute(node.param, method, segments, optionalTail: true) ??
      _selectRoute(node.wildcard, method, segments, optionalTail: true);
}

// dart format off
RouteMatch<T>? _selectRoute<T>(RouterNode<T>? node, String method, List<String> segments, {bool optionalTail = false}) {// dart format on
  final methods = node?.methods;
  final bucket =
      methods?[method] ?? methods?[normalizeMethod(method)] ?? methods?[''];
  if (bucket == null) return null;
  final routes = bucket.candidates(segments);
  if (routes.length == 1) {
    return routes.first.match(segments, optionalTail: optionalTail);
  }
  RouteMatch<T>? best;
  var bestDepth = -1;
  for (final route in routes) {
    // Only a deeper constraint can beat an earlier match.
    if (route.constraintDepth <= bestDepth) continue;
    if (route.match(segments, optionalTail: optionalTail) case final match?) {
      if (route.params.isEmpty || route.constraintDepth == segments.length) {
        return match;
      }
      best = match;
      bestDepth = route.constraintDepth;
    }
  }
  return best;
}

// dart format off
List<RouteMatch<T>> findAllRoutes<T>(RouterNode<T> root, bool caseSensitive, String method, String path, bool includeAny) {// dart format on
  final segments = normalizedSegments(path);
  final matches = <RouteMatch<T>>[];

  void collect(RouterNode<T>? child, {bool optionalTail = false}) {
    final methods = child?.methods;
    if (methods == null) return;
    final routes = includeAny && method.isNotEmpty
        ? [...?methods['']?.routes, ...?methods[method]?.routes]
        : (methods[method] ?? methods[''])?.routes;
    if (routes == null) return;
    for (final route in routes) {
      if (route.match(segments, allowPartial: true, optionalTail: optionalTail)
          case final match?) {
        matches.add(match);
      }
    }
  }

  void visit(RouterNode<T>? node, int index) {
    if (node == null) return;
    collect(node.wildcard);
    if (index == segments.length) {
      collect(node.param, optionalTail: true);
      collect(node);
      return;
    }
    visit(node.param, index + 1);
    visit(node.staticChild(segments[index], caseSensitive), index + 1);
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
    if (methods == null || methods.remove(method) == null) return false;
    if (methods.isEmpty) node.methods = null;
    return true;
  }

  final segment = segments[index];
  final wildcard = segment.startsWith('**');
  final key = wildcard || _isParamSegment(segment)
      ? null
      : _staticKey(segment, caseSensitive);
  final child = switch (key) {
    final value? => node.statics?[value],
    null => wildcard ? node.wildcard : node.param,
  };
  if (child == null) return false;
  final removed = _remove(child, method, segments, index + 1, caseSensitive);
  if (!child.isEmpty) return removed;
  if (key != null) {
    node.statics!.remove(key);
    if (node.statics!.isEmpty) node.statics = null;
  } else if (wildcard) {
    node.wildcard = null;
  } else {
    node.param = null;
  }

  return removed;
}

String _staticKey(String segment, bool sensitive) {
  final value = segment == r'\*' || segment == r'\*\*'
      ? segment.replaceAll(r'\', '')
      : decodeEscaped(segment);
  return sensitive ? value : value.toLowerCase();
}

bool _isParamSegment(String segment) =>
    segment.contains(':') ||
    segment.contains('(') ||
    (segment.contains('*') &&
        _syntax.allMatches(segment).any((m) => m[0] == '*'));

final _syntax = RegExp(r'\\[\s\S]|[(){}*]');
final _regexSyntax = RegExp(
  r'\\[\s\S]?|\[(?:\\[\s\S]|[^\]\\])*(?:\]|\\?$)|[()]',
);
final _literalPrefix = RegExp(r'^[a-zA-Z0-9_-]+(?=$|\\|\[|\()');
final _name = RegExp(r'[A-Za-z_][\w-]*');
final _simpleParamRx = RegExp('^:${_name.pattern}\$');
final _modifierRx = RegExp(r'^(.*:[\w-]+(?:\([^)]*\))?)([?+*])$');

// dart format off
(SegmentPattern, int) compileSegmentPattern(String segment, bool caseSensitive, int unnamedIndex) {// dart format on
  final regex = StringBuffer();
  final captures = <(String, int)>[];
  String nextName() => '$unnamedGroupPrefix${unnamedIndex++}';
  var cursor = 0;
  var tokens = 0;
  var plainParams = 0;
  var head = '';
  String? separator;

  while (cursor < segment.length) {
    tokens++;
    final code = segment.codeUnitAt(cursor);

    if (code == 58 /* : */ || code == 40 /* ( */ || code == 42 /* * */ ) {
      final named = code == 58;
      final String name;
      if (named) {
        final m = _name.matchAsPrefix(segment, cursor + 1);
        if (m == null) throw FormatException('Invalid param name: $segment');
        name = m[0]!;
        cursor = m.end;
      } else {
        name = nextName();
      }
      final outer = (name, captures.length + 1);
      final inner = <(String, int)>[];
      var body = r'[^/]+';
      if (code == 42) {
        body = r'[^/]*';
        cursor++;
      } else if (segment.startsWith('(', cursor)) {
        final end = _findRegexEnd(segment, cursor);
        final raw = segment.substring(cursor + 1, end);
        body = !raw.contains('(')
            ? raw
            : raw.replaceAllMapped(_regexSyntax, (m) {
                if (m[0] != '(' || raw.startsWith('?', m.end)) return m[0]!;
                final key = nextName();
                inner.add((key, outer.$2 + inner.length + 1));
                return '(?<$key>';
              });
        cursor = end + 1;
      } else {
        plainParams++;
      }
      regex.write('(?<$name>$body)');
      if (tokens == 1) head = body;
      if (!named) captures.add(outer);
      captures.addAll(inner);
      if (named) captures.add(outer);
      continue;
    }

    final start = cursor++;
    while (cursor < segment.length) {
      final c = segment.codeUnitAt(cursor);
      if (c == 58 /* : */ || c == 42 /* * */ ) break;
      cursor++;
    }
    final literal = decodeEscaped(segment.substring(start, cursor));
    if (tokens == 1) head = literal;
    if (tokens == 2 &&
        (caseSensitive || literal.toLowerCase() == literal.toUpperCase())) {
      separator = literal;
    }
    regex.write(RegExp.escape(literal));
  }

  // User-defined named groups can shift the generated capture positions.
  final useNames = segment.contains('(?<');
  final groups = [
    for (final (name, index) in captures)
      (
        key: normalizeUnnamedGroupKey(name),
        index: tokens == 1 && index == 1
            ? 0
            : useNames
            ? null
            : index,
        name: name,
      ),
  ];
  final source = regex.toString();
  final split = tokens == 3 && plainParams == 2 ? separator : null;
  final matcher = RegExp('^$source\$', caseSensitive: caseSensitive);
  final program = split == null
      ? SegmentProgram.compile(source, caseSensitive, groups)
      : null;
  final prefix =
      program?.prefix ??
      (head.contains('|') ? '' : _literalPrefix.stringMatch(head) ?? '');
  return (
    SegmentPattern(
      matcher,
      groups,
      prefix: prefix,
      separator: split,
      program: program,
    ),
    unnamedIndex,
  );
}

int _findRegexEnd(String s, int start) {
  var depth = 0;
  for (final m in _regexSyntax.allMatches(s, start)) {
    if (m[0] == '(') depth++;
    if (m[0] == ')' && --depth == 0) return m.start;
  }
  throw FormatException('Unclosed regex in route: $s');
}

String encodeEscapes(String path) {
  if (!path.contains('\\')) return path;
  return path
      .replaceAll(r'\:', '\uFFFDA')
      .replaceAll(r'\(', '\uFFFDB')
      .replaceAll(r'\)', '\uFFFDC')
      .replaceAll(r'\{', '\uFFFDD')
      .replaceAll(r'\}', '\uFFFDE');
}

String decodeEscaped(String segment) => !segment.contains('\uFFFD')
    ? segment
    : segment
          .replaceAll('\uFFFDA', ':')
          .replaceAll('\uFFFDB', '(')
          .replaceAll('\uFFFDC', ')')
          .replaceAll('\uFFFDD', '{')
          .replaceAll('\uFFFDE', '}');

List<String>? expandGroupDelimiters(String path) {
  if (!path.contains('{')) return null;
  var start = -1;
  var end = -1;
  var depth = 0;
  for (final m in _syntax.allMatches(path)) {
    final token = m[0];
    if (token == '(') {
      depth++;
    } else if (token == ')' && depth > 0) {
      depth--;
    } else if (token == '{' && depth == 0 && start < 0) {
      start = m.start;
    } else if (token == '}' && depth == 0 && start >= 0) {
      end = m.start;
      break;
    }
  }
  if (start < 0) return null;
  if (end < 0) throw FormatException('Unclosed group in route: $path');

  final mod = end + 1 < path.length ? path[end + 1] : '';
  final hasMod = mod == '?' || mod == '+' || mod == '*';
  final pre = path.substring(0, start);
  final body = path.substring(start + 1, end);
  final suf = path.substring(end + (hasMod ? 2 : 1));

  if (!hasMod) return ['$pre$body$suf'];
  if (mod == '?') return ['$pre$body$suf', '$pre$suf'];
  if (body.contains('/')) {
    throw FormatException('Unsupported group repetition across segments');
  }
  return ['$pre(?:$body)$mod$suf'];
}

List<String>? expandModifiers(List<String> segments) {
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (segment.isEmpty) continue;
    final last = segment.codeUnitAt(segment.length - 1);
    if (last != 63 && last != 43 && last != 42) continue; // ?, +, *
    final m = _modifierRx.firstMatch(segment);
    if (m == null) continue;
    final base = m.group(1)!;
    final mod = m.group(2)!;
    final parts = segments.toList();
    parts[i] = mod == '?'
        ? base
        : '**:${RegExp(r':([\w-]+)').firstMatch(base)?[1] ?? '_'}';
    final path = '/${parts.join('/')}';
    if (mod == '+') return [path];
    parts.removeAt(i);
    return [path, '/${parts.join('/')}'];
  }
  return null;
}
