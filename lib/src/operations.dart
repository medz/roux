// ignore_for_file: public_member_api_docs

import 'model.dart';
import 'literal.dart';
import 'path.dart';
import 'segment_program.dart';

class RouteRoot<T> extends RouterNode<T> {
  final literals = LiteralRoutes<T>();
  SharedShape<T>? shared;
  int heads = 0;
}

// A table with a common pattern only needs one copy of its literals and capture names.
class SharedShape<T> extends RouterNode<T> {
  SharedShape(this.parts, this.sensitive)
    : names = [
        for (final p in parts)
          p.startsWith(':') ? normalizeUnnamedGroupKey(p.substring(1)) : null,
      ],
      literals = [for (final p in parts) sensitive ? p : p.toLowerCase()];
  final List<String> parts, literals;
  final List<String?> names;
  final bool sensitive;
  final rows = Bindings<T>();
  int pivot = -1;
  String before = '', after = '';

  bool add(List<String> next, String method, T data) {
    if (next.length != parts.length) return false;
    var changed = pivot;
    for (var i = 0; i < parts.length; i++) {
      if (next[i] == parts[i] || i == pivot && _plainSegment(next[i])) continue;
      if (changed >= 0 || names[i] != null || !_plainSegment(next[i])) {
        return false;
      }
      changed = i;
    }
    if (changed != pivot) _setPivot(changed);
    final selector = pivot < 0 ? '' : next[pivot];
    rows.add(sensitive ? selector : selector.toLowerCase(), method, data);
    return true;
  }

  void _setPivot(int index) {
    pivot = index;
    before = pivot == 0 ? '/' : '/${parts.take(pivot).join('/')}/';
    after = pivot + 1 == parts.length
        ? ''
        : '/${parts.skip(pivot + 1).join('/')}';
    rows.rekey('', literals[pivot]);
  }

  @override
  bool get isEmpty => rows.isEmpty;

  bool addRaw(String path, String method, T data) {
    if (pivot < 0 || !path.startsWith(before) || !path.endsWith(after)) {
      return false;
    }
    final end = path.length - after.length;
    if (end <= before.length) return false;
    final key = path.substring(before.length, end);
    if (!_plainSegment(key)) return false;
    rows.add(sensitive ? key : key.toLowerCase(), method, data);
    return true;
  }

  String? selector(List<String> actual, {bool removal = false}) {
    if (actual.length != parts.length) return null;
    for (var i = 0; i < actual.length; i++) {
      final val = actual[i];
      if (names[i] != null) {
        if (removal &&
            (_literalKey(val, sensitive) != null || val.startsWith('**'))) {
          return null;
        }
      } else if (i != pivot &&
          val != literals[i] &&
          (sensitive || val.toLowerCase() != literals[i])) {
        return null;
      }
    }
    return pivot < 0
        ? ''
        : sensitive
        ? actual[pivot]
        : actual[pivot].toLowerCase();
  }

  Map<String, String> params(List<String> actual) {
    final values = Captures();
    for (var i = 0; i < names.length; i++) {
      final n = names[i];
      if (n != null) values[n] = actual[i];
    }
    return values;
  }

  // Attach the shared suffix to the trie. A conflicting literal splits only its own row.
  void mount(RouteRoot<T> root) {
    if (pivot < 0) {
      rows.take(
        '',
        (method, data) =>
            _insert(root, sensitive, method, parts.join('/'), parts, data, 0),
      );
      return;
    }
    RouterNode<T> node = root;
    for (var i = 0; i < pivot; i++) {
      if (names[i] != null) {
        node = node.param = RouterNode<T>();
      } else {
        final child = RouterNode<T>(literals[i]);
        node.statics = child;
        node = child;
      }
    }
    node.statics = _SharedChildren(this);
  }

  void split(RouterNode<T> root, String key) {
    final route = List.of(parts)..[pivot] = key;
    final path = route.join('/');
    rows.take(
      key,
      (method, data) => _insert(root, sensitive, method, path, route, data, 0),
    );
  }

  RouteMatch<T>? find(List<String> parts, String method) {
    final key = selector(parts);
    final cell = key == null ? null : rows.findCell(key, method);
    return cell == null ? null : RouteMatch(rows.value(cell), params(parts));
  }

  void collect(
    List<String> parts,
    String method,
    bool any,
    List<RouteMatch<T>> out,
  ) {
    final key = selector(parts);
    if (key != null) {
      rows.allValues(
        key,
        method,
        any,
        (v) => out.add(RouteMatch(v, params(parts))),
      );
    }
  }
}

class _SharedChildren<T> extends RouteEntry<RouterNode<T>> {
  _SharedChildren(this.shape, [this.literal, this.row]) : super(null);
  final SharedShape<T> shape;
  final String? literal, row;
  @override
  RouterNode<T>? operator [](String name) =>
      super[name] ??
      ((literal == null || name == literal) && shape.rows.contains(row ?? name)
          ? shape
          : null);
  @override
  RouteEntry<RouterNode<T>>? without(String name) {
    final rest = super.without(name);
    final key = row;
    return (key == null ? !shape.rows.isEmpty : shape.rows.contains(key))
        ? this
        : rest;
  }
}

bool _plainSegment(String key) {
  if (key.isEmpty || key == '.' || key == '..') return false;
  for (var i = 0; i < key.length; i++) {
    final c = key.codeUnitAt(i);
    if (c == 47 || isPatternUnit(c)) return false;
  }
  return true;
}

bool _plainPattern(List<String> parts) {
  for (final p in parts) {
    if (!(p.startsWith(':') && _isName(p, 1)) && !_plainSegment(p)) {
      return false;
    }
  }
  return true;
}

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
void addRoute<T>(RouteRoot<T> root, bool caseSensitive, String method, String path, T data) {// dart format on
  if (root.shared?.addRaw(path, method, data) ?? false) return;
  final depth = literalDepth(path);
  if (depth > 0) {
    root.literals.addLiteral(
      caseSensitive ? path : path.toLowerCase(),
      method,
      data,
      depth,
    );
    return;
  }
  for (final segments in _patterns(path)) {
    var leading = 0;
    for (; leading < segments.length; leading++) {
      final k = _literalKey(segments[leading], caseSensitive);
      if (k == null || k.isEmpty || k == '.' || k == '..') break;
      segments[leading] = k;
    }
    final literalKey = leading == segments.length && leading > 0
        ? '/${segments.join('/')}'
        : null;
    if (literalKey != null) {
      root.literals.addLiteral(literalKey, method, data, segments.length);
      continue;
    }
    if (leading > 0) root.heads |= 1 << (segments.first.codeUnitAt(0) & 31);
    final shared = root.shared;
    if (root.isEmpty) {
      if (leading < segments.length &&
          !path.contains(r'\') &&
          !path.contains('{') &&
          !path.contains('\uFFFD') &&
          _plainPattern(segments)) {
        final shape = shared ?? SharedShape<T>(segments, caseSensitive);
        if (shape.add(segments, method, data)) {
          if (shape.pivot >= 0 && root.isEmpty) shape.mount(root);
          root.shared = shape;
          continue;
        }
      }
      shared?.mount(root);
    }
    root.shared = null;
    _insert(root, caseSensitive, method, path, segments, data, leading);
  }
}

void _insert<T>(
  RouterNode<T> root,
  bool caseSensitive,
  String method,
  String path,
  List<String> segments,
  T data,
  int leading,
) {
  RouterNode<T> node = root;
  final route = RouteData(method, data);
  List<Object>? params;
  var nextCapture = 0, unnamedIndex = 0;

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];

    final key = i < leading ? segment : _literalKey(segment, caseSensitive);
    if (key != null) {
      final children = node.statics ??= RouterNode<T>(key);
      var child = children[key];
      if (child is SharedShape<T>) {
        final shape = child,
            id = caseSensitive
                ? segments[shape.pivot]
                : segments[shape.pivot].toLowerCase();
        if (i + 1 < shape.parts.length && shape.names[i + 1] == null) {
          child = children.addSibling(RouterNode<T>(key));
          child.statics = _SharedChildren(shape, shape.literals[i + 1], id);
        } else {
          shape.split(root, id);
          child = children[key];
        }
      }
      node = child ?? children.addSibling(RouterNode<T>(key));
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

String? _literalPath(List<String> parts, bool sensitive) {
  if (parts.isEmpty) return null;
  final keys = <String>[];
  for (final part in parts) {
    final key = _literalKey(part, sensitive);
    if (key == null || key.isEmpty || key == '.' || key == '..') return null;
    keys.add(key);
  }
  return '/${keys.join('/')}';
}

@pragma('vm:prefer-inline')
RouteMatch<T>? lookupRoute<T>(
  RouteRoot<T> root,
  bool sensitive,
  String method,
  String path,
) {
  if (path.isEmpty || path == '/') {
    return _select(root, method, const []) ??
        _select(root.param, method, const [], optionalTail: true) ??
        _select(root.wildcard, method, const [], optionalTail: true);
  }
  if (root.literals.possible(path)) {
    final direct = root.literals.literal(path, method);
    if (direct != null) return direct;
  }
  if (path.length > 1) {
    final c = path.codeUnitAt(1);
    if (c < 128 &&
        root.heads & (1 << (c & 31)) == 0 &&
        !root.literals.possible(path) &&
        root.shared == null &&
        root.param == null &&
        root.wildcard == null &&
        root.statics is! _SharedChildren<T> &&
        path.codeUnitAt(0) == 47 &&
        c != 46 &&
        c != 47 &&
        !path.contains('/..')) {
      return null;
    }
  }
  final parts = normalizedSegments(path);
  if (!root.literals.isEmpty) {
    final other = root.literals.normalizedKey(path, parts, sensitive);
    if (other != null && other != path) {
      final hit = root.literals.literal(other, method);
      if (hit != null) return hit;
    }
  }
  final shape = root.shared;
  if (shape != null) return shape.find(parts, method);
  return findRoute(root, sensitive, method, parts);
}

// dart format off
RouteMatch<T>? findRoute<T>(RouterNode<T> node, bool caseSensitive, String method, List<String> segments, [int index = 0]) {// dart format on
  while (index < segments.length) {
    var child = node.staticChild(segments[index++], caseSensitive);
    if (child is SharedShape) {
      final hit = (child as SharedShape<T>).find(segments, method);
      if (hit != null) return hit;
      child = null;
    }
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
List<RouteMatch<T>> findAllRoutes<T>(RouteRoot<T> root, bool caseSensitive, String method, String path, bool includeAny) {// dart format on
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
      if (node is SharedShape<T>) {
        node.collect(segments, method, includeAny, matches);
        return;
      }
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

  final shared = root.shared;
  if (shared == null) {
    visit(root, 0);
  } else {
    shared.collect(segments, method, includeAny, matches);
  }
  if (!root.literals.isEmpty) {
    root.literals.collectLiterals(
      path,
      segments,
      caseSensitive,
      method,
      includeAny,
      matches,
    );
  }
  return matches;
}

// dart format off
bool removeRoute<T>(RouteRoot<T> root, bool caseSensitive, String method, String path) {// dart format on
  final depth = literalDepth(path);
  if (depth > 0) {
    return root.literals.remove(
      caseSensitive ? path : path.toLowerCase(),
      method,
    );
  }
  var removed = false;
  for (final segments in _patterns(path)) {
    final shared = root.shared;
    if (shared != null) {
      final key = shared.selector(segments, removal: true);
      if (key != null && shared.rows.remove(key, method)) {
        if (shared.rows.isEmpty) {
          root.shared = null;
          root.statics = null;
          root.param = null;
        }
        removed = true;
        continue;
      }
    }
    final key = _literalPath(segments, caseSensitive);
    final hit = key == null
        ? _remove(root, method, segments, 0, caseSensitive)
        : root.literals.remove(key, method);
    if (hit) removed = true;
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
  if (child is SharedShape<T>) {
    final id = child.selector(segments, removal: true);
    if (id == null || !child.rows.remove(id, method)) return false;
    if (!child.rows.contains(id)) node.statics = node.statics!.without(key!);
    return true;
  }
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
bool _isName(String text, [int start = 0]) {
  for (var i = start; i < text.length; i++) {
    final c = text.codeUnitAt(i), lower = c | 32;
    if (lower >= 97 && lower <= 122 || c == 95) continue;
    if (i == start || c != 45 && (c < 48 || c > 57)) return false;
  }
  return start < text.length;
}

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
