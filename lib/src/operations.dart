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
      ];
  final List<String> parts;
  final List<String?> names;
  final bool sensitive;
  final rows = Bindings<T>();
  int pivot = -1;
  String before = '', after = '';

  bool add(List<String> next, String method, T data) {
    if (next.length != parts.length) return false;
    var changed = -1;
    for (var i = 0; i < next.length; i++) {
      final text = next[i];
      if (text == parts[i]) continue;
      if (names[i] != null || !isPlainSegment(text)) return false;
      if (_sameLiteral(text, parts[i])) continue;
      if (changed >= 0) return false;
      changed = i;
    }
    if (changed >= 0) {
      pivot = changed;
      before = pivot == 0 ? '/' : '/${next.take(pivot).join('/')}/';
      after = pivot + 1 == parts.length
          ? ''
          : '/${next.skip(pivot + 1).join('/')}';
      rows.rekey('', literalCase(parts[pivot], sensitive));
    }
    final key = changed < 0 ? '' : next[changed];
    rows.add(literalCase(key, sensitive), method, data);
    return true;
  }

  bool addRaw(String path, String method, T data) {
    if (pivot < 0 || !path.startsWith(before) || !path.endsWith(after)) {
      return false;
    }
    final end = path.length - after.length;
    if (end <= before.length) return false;
    final key = path.substring(before.length, end);
    if (!isPlainSegment(key)) return false;
    rows.add(literalCase(key, sensitive), method, data);
    return true;
  }

  bool _sameLiteral(String a, String b) =>
      a == b || !sensitive && a.toLowerCase() == b.toLowerCase();

  String? selector(List<String> actual, {bool removal = false}) {
    if (actual.length != parts.length) return null;
    for (var i = 0; i < actual.length; i++) {
      final val = actual[i];
      if (names[i] != null) {
        if (removal &&
            (_literalKey(val, sensitive) != null || val.startsWith('**'))) {
          return null;
        }
      } else if (i != pivot && !_sameLiteral(val, parts[i])) {
        return null;
      }
    }
    return pivot < 0 ? '' : literalCase(actual[pivot], sensitive);
  }

  String? remove(List<String> parts, String method) {
    final key = selector(parts, removal: true);
    return key != null && rows.remove(key, method) ? key : null;
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
      split(root, '');
      return;
    }
    RouterNode<T> node = root;
    for (var i = 0; i < pivot; i++) {
      if (names[i] != null) {
        node = node.param = RouterNode<T>();
      } else {
        final child = RouterNode<T>(literalCase(parts[i], sensitive));
        node.statics = child;
        node = child;
      }
    }
    node.statics = _SharedChildren(this);
  }

  void split(RouterNode<T> root, String key) {
    final route = pivot < 0 ? parts : (List.of(parts)..[pivot] = key);
    rows.take(
      key,
      (method, data) => _insert(root, sensitive, method, null, route, data),
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
  RouteEntry<RouterNode<T>>? _written;
  @override
  RouterNode<T>? operator [](String name) =>
      _written?[name] ??
      ((literal == null || literal == name) && shape.rows.contains(row ?? name)
          ? shape
          : null);
  @override
  RouterNode<T> addSibling(RouterNode<T> value) =>
      _written?.addSibling(value) ?? (_written = value);
  @override
  RouteEntry<RouterNode<T>>? without(String name) {
    final other = _written = _written?.without(name), id = row;
    return (id == null ? !shape.rows.isEmpty : shape.rows.contains(id))
        ? this
        : other;
  }
}

bool _plainPattern(List<String> parts) =>
    parts.isNotEmpty &&
    parts.every((p) => p.startsWith(':') ? isName(p, 1) : isPlainSegment(p));

Iterable<List<String>> _patterns(
  String path, {
  bool expandedPath = false,
  bool canonical = false,
}) {
  if (canonical) return [path.substring(1).split('/')];
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
  final depth = canonicalDepth(path);
  if (depth > 0) {
    root.literals.addLiteral(
      literalCase(path, caseSensitive),
      method,
      data,
      depth,
    );
    return;
  }
  final plain = depth < 0;
  for (final parts in _patterns(path, canonical: plain)) {
    final share = root.isEmpty && (plain || _plainPattern(parts));
    final leading = plain ? 0 : _foldLiterals(parts, caseSensitive);
    if (leading > 0 && leading == parts.length) {
      root.literals.addLiteral('/${parts.join('/')}', method, data, leading);
      continue;
    }
    if (parts.isNotEmpty) {
      final first = parts.first;
      final c = first.isEmpty ? 128 : first.codeUnitAt(0);
      // Escapes, patterns and Unicode can change the first character during matching.
      root.heads |= c >= 128 || c == 58 || c == 40 || c == 42 || c == 92
          ? -1
          : 1 << (c & 31);
    }
    final shared = root.shared;
    if (share) {
      final shape = shared ?? SharedShape<T>(parts, caseSensitive);
      if (shape.add(parts, method, data)) {
        if (shape.pivot >= 0) {
          shape.mount(root);
          if (shape.pivot == 0) root.heads = -1;
        }
        root.shared = shape;
        continue;
      }
    }
    if (shared != null && root.isEmpty) shared.mount(root);
    root.shared = null;
    _insert(
      root,
      caseSensitive,
      method,
      plain ? null : path,
      parts,
      data,
      leading,
    );
  }
}

void _insert<T>(
  RouterNode<T> root,
  bool caseSensitive,
  String method,
  String? pattern,
  List<String> segments,
  T data, [
  int leading = 0,
]) {
  // A missing source denotes prevalidated literals and named parameters.
  final plain = pattern == null;
  RouterNode<T> node = root;
  final route = RouteData(method, data);
  List<Object>? params;
  var nextCapture = 0, unnamedIndex = 0;

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];

    final key = i < leading
        ? segment
        : plain
        ? (segment.startsWith(':') ? null : literalCase(segment, caseSensitive))
        : _literalKey(segment, caseSensitive);
    if (key != null) {
      final children = node.statics ??= RouterNode<T>(key);
      var child = children[key];
      if (child is SharedShape<T>) {
        final shape = child, id = (children as _SharedChildren<T>).row ?? key;
        if (i + 1 < shape.parts.length && shape.names[i + 1] == null) {
          child = children.addSibling(RouterNode<T>(key));
          child.statics = _SharedChildren(
            shape,
            literalCase(shape.parts[i + 1], caseSensitive),
            id,
          );
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
      if (!isName(name)) {
        throw FormatException('Invalid wildcard param name: $pattern');
      }
      capture = Wildcard(normalizeUnnamedGroupKey(name), optional, true);
    } else if (segment == '*') {
      capture = Wildcard('${unnamedIndex++}', true, false);
    } else if (plain || segment.startsWith(':') && isName(segment, 1)) {
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
    final first = route.plan;
    if (first == null) {
      route.plan = capture;
      route.captureStart = i;
    } else {
      final plan = params ??= [first];
      if (i > nextCapture) plan.add(i - nextCapture);
      plan.add(capture);
    }
    nextCapture = i + 1;
    if (rest) break;
  }

  if (params != null) route.plan = params.toList(growable: false);
  final methods = node.methods ??= route;
  final first = methods[method] ?? methods.addSibling(route);
  if (!identical(first, route)) {
    (first.alternatives ??= RouteBucket<T>(first)).add(route);
  }
}

int _foldLiterals(List<String> parts, bool sensitive) {
  var i = 0;
  for (; i < parts.length; i++) {
    final key = _literalKey(parts[i], sensitive);
    if (key == null || key.isEmpty || key == '.' || key == '..') break;
    parts[i] = key;
  }
  return i;
}

@pragma('vm:prefer-inline')
RouteMatch<T>? lookupRoute<T>(
  RouteRoot<T> root,
  bool sensitive,
  String method,
  String path,
) {
  if (path.isEmpty || path == '/') {
    return findRoute(root, sensitive, method, const []);
  }
  if (path.length > 1) {
    final c = path.codeUnitAt(1), bit = 1 << (c & 31);
    if (root.literals.hasHead(c)) {
      final hit = root.literals.literal(path, method);
      if (hit != null) return hit;
    } else if (root.heads & bit == 0 &&
        path.codeUnitAt(0) == 47 &&
        c != 46 &&
        c != 47 &&
        !path.contains('/..')) {
      return null;
    }
  }
  final parts = normalizedSegments(path);
  final normalized = root.literals.normalizedKey(path, parts, sensitive);
  if (normalized != null) {
    final hit = root.literals.literal(normalized, method);
    if (hit != null) return hit;
  }
  final shape = root.shared;
  if (shape != null) return shape.find(parts, method);
  return findRoute(root, sensitive, method, parts);
}

// dart format off
RouteMatch<T>? findRoute<T>(RouterNode<T> node, bool caseSensitive, String method, List<String> segments, [int index = 0]) {// dart format on
  while (index < segments.length) {
    final child = node.staticChild(segments[index], caseSensitive),
        param = node.param;
    final next = param ?? child;
    if (next == null) break;
    index++;
    if (child != null && param != null) {
      final hit = findRoute(child, caseSensitive, method, segments, index);
      if (hit != null) return hit;
    }
    final wildcard = node.wildcard;
    if (wildcard != null) {
      return findRoute(next, caseSensitive, method, segments, index) ??
          _select(wildcard, method, segments);
    }
    node = next;
  }
  if (node.methods == null && node is SharedShape<T>) {
    return node.find(segments, method);
  }
  if (index < segments.length) return _select(node.wildcard, method, segments);
  return _select(node, method, segments) ??
      _select(node.param, method, segments, optionalTail: true) ??
      _select(node.wildcard, method, segments, optionalTail: true);
}

// dart format off
RouteMatch<T>? _select<T>(RouterNode<T>? node, String method, List<String> segments, {bool optionalTail = false}) {// dart format on
  final first = node?.methods?.forMethod(method);
  if (first == null) return null;
  final bucket = first.alternatives;
  return bucket == null
      ? first.match(segments, optionalTail: optionalTail)
      : bucket.match(segments, optionalTail);
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

  visit(root.shared ?? root, 0);
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
  final depth = canonicalDepth(path);
  if (depth > 0) {
    return root.literals.remove(literalCase(path, caseSensitive), method);
  }
  var removed = false;
  for (final segments in _patterns(path, canonical: depth < 0)) {
    final shared = root.shared;
    if (shared != null) {
      if (shared.remove(segments, method) != null) {
        if (shared.rows.isEmpty) {
          root.shared = null;
          root.statics = null;
          root.param = null;
        }
        removed = true;
        continue;
      }
    }
    final leading = depth < 0 ? 0 : _foldLiterals(segments, caseSensitive);
    final hit = leading > 0 && leading == segments.length
        ? root.literals.remove('/${segments.join('/')}', method)
        : _remove(root, method, segments, 0, caseSensitive, leading);
    if (hit) removed = true;
  }
  return removed;
}

// dart format off
bool _remove<T>(RouterNode<T> node, String method, List<String> segments, int index, bool caseSensitive, int leading) {// dart format on
  if (index == segments.length) {
    final methods = node.methods;
    if (methods?[method] == null) return false;
    node.methods = methods!.without(method);
    return true;
  }

  final segment = segments[index];
  final key = index < leading ? segment : _literalKey(segment, caseSensitive);
  final wildcard = key == null && segment.startsWith('**');
  final child = switch (key) {
    final value? => node.statics?[value],
    null => wildcard ? node.wildcard : node.param,
  };
  if (child == null) return false;
  if (child is SharedShape<T>) {
    final id = child.remove(segments, method);
    if (id == null) return false;
    if (!child.rows.contains(id)) node.statics = node.statics!.without(key!);
    return true;
  }
  final removed = _remove(
    child,
    method,
    segments,
    index + 1,
    caseSensitive,
    leading,
  );
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
  return literalCase(value, sensitive);
}

final _segmentTokens = RegExp(r':([A-Za-z_][\w-]*)|[:(*]|([^:*]+)');
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
