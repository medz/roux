// ignore_for_file: public_member_api_docs

import 'model.dart';
import 'path.dart';

// dart format off
void addRoute<T>(RouterNode<T> root, Map<String, RouterNode<T>> staticRoutes, bool caseSensitive, String method, String path, T data) {// dart format on
  if (expandGroupDelimiters(path) case final groupExpanded?) {
    for (final p in groupExpanded) {
      addRoute(root, staticRoutes, caseSensitive, method, p, data);
    }
    return;
  }

  path = encodeEscapes(path);
  final segments = splitPath(path);

  if (expandModifiers(segments) case final modExpanded?) {
    for (final p in modExpanded) {
      addRoute(root, staticRoutes, caseSensitive, method, p, data);
    }
    return;
  }

  var node = root;
  var unnamedIndex = 0;
  final paramsMap = <ParamSpec>[];
  final paramsRegexp = <SegmentPattern?>[];

  for (var i = 0; i < segments.length; i++) {
    var segment = segments[i];

    // Wildcard **
    if (segment.startsWith('**')) {
      node.wildcard ??= RouterNode<T>();
      node = node.wildcard!;
      final name = segment.length == 2 ? '_' : segment.substring(3);
      final optional = segment.length == 2;
      if (name != '_' && !validParamSlice(name, 0, name.length)) {
        throw FormatException('Invalid wildcard param name: $path');
      }
      paramsMap.add(ParamSpec(-(i + 1), name, optional));
      break;
    }

    // Param
    if (segment == '*' ||
        segment.contains(':') ||
        segment.contains('(') ||
        hasSegmentWildcard(segment)) {
      node = node.param ??= RouterNode<T>();

      if (segment == '*') {
        paramsMap.add(ParamSpec(i, '$unnamedIndex', true));
        unnamedIndex++;
      } else if (segment.contains(':', 1) ||
          segment.contains('(') ||
          hasSegmentWildcard(segment) ||
          !_simpleParamRx.hasMatch(segment)) {
        // dart format off
        final (pattern, nextUnnamed) = compileSegmentPattern(segment, caseSensitive, unnamedIndex); // dart format on
        unnamedIndex = nextUnnamed;
        paramsRegexp.length = i + 1;
        paramsRegexp[i] = pattern;
        node.hasRegexParam = true;
        paramsMap.add(ParamSpec(i, pattern, false));
      } else {
        final name = segment.substring(1);
        if (!validParamSlice(name, 0, name.length)) {
          throw FormatException('Invalid param name: $path');
        }
        paramsMap.add(ParamSpec(i, name, false));
      }
      continue;
    }

    // Static
    if (segment == r'\*') {
      segment = '*';
    } else if (segment == r'\*\*') {
      segment = '**';
    }
    segment = decodeEscaped(segment);
    final key = caseSensitive ? segment : segment.toLowerCase();
    node.statics ??= {};
    node = node.statics!.putIfAbsent(key, RouterNode<T>.new);
  }

  final hasParams = paramsMap.isNotEmpty;
  final route = RouteData<T>(
    data: data,
    paramsRegexp: paramsRegexp,
    paramsMap: hasParams ? paramsMap : null,
  );

  node.methods ??= {};
  (node.methods![method] ??= []).add(route);

  if (!hasParams) {
    staticRoutes['/${segments.join('/')}'] = node;
  }
}

// dart format off
RouteMatch<T>? findRoute<T>(RouterNode<T> root, Map<String, RouterNode<T>> staticRoutes, bool caseSensitive, String method, String path) {// dart format on
  final staticNode = staticRoutes[caseSensitive ? path : path.toLowerCase()];
  if (staticNode?.methods != null) {
    final match = staticNode!.methods![method] ?? staticNode.methods![''];
    if (match != null) return match.first.materialize(const []);
  }

  final segments = splitPath(path);
  final match = _lookupTree(root, method, segments, 0, caseSensitive)?.first;
  return match?.materialize(segments);
}

// dart format off
List<RouteData<T>>? _lookupTree<T>(RouterNode<T> node, String method, List<String> segments, int index, bool caseSensitive) {// dart format on
  if (index == segments.length) {
    if (node.methods != null) {
      final match = node.methods![method] ?? node.methods![''];
      if (match != null) return match;
    }
    // optional tail: /foo matches /foo/:id? or /foo/**
    if (node.param?.methods != null) {
      final match = node.param!.methods![method] ?? node.param!.methods![''];
      if (match != null && match.first.paramsMap?.last.optional == true) {
        return match;
      }
    }
    if (node.wildcard?.methods != null) {
      final match =
          node.wildcard!.methods![method] ?? node.wildcard!.methods![''];
      if (match != null && match.first.paramsMap?.last.optional == true) {
        return match;
      }
    }
    return null;
  }

  final rawSegment = segments[index];
  final segment = caseSensitive ? rawSegment : rawSegment.toLowerCase();

  // 1. Static
  if (node.statics?[segment] case final staticChild?) {
    if (_lookupTree(staticChild, method, segments, index + 1, caseSensitive)
        case final match?) {
      return match;
    }
  }

  // 2. Param
  if (node.param != null) {
    if (_lookupTree(node.param!, method, segments, index + 1, caseSensitive)
        case final match?) {
      if (node.param!.hasRegexParam) {
        final exact =
            match.firstWhereOrNull(
              (m) =>
                  index < m.paramsRegexp.length &&
                  m.paramsRegexp[index] != null &&
                  m.paramsRegexp[index]!.regex.hasMatch(rawSegment),
            ) ??
            match.firstWhereOrNull(
              (m) =>
                  index >= m.paramsRegexp.length ||
                  m.paramsRegexp[index] == null,
            );
        return exact != null ? [exact] : null;
      }
      return match;
    }
  }

  // 3. Wildcard
  if (node.wildcard?.methods != null) {
    return node.wildcard!.methods![method] ?? node.wildcard!.methods![''];
  }

  return null;
}

// dart format off
List<RouteMatch<T>> findAllRoutes<T>(RouterNode<T> root, bool caseSensitive, String method, String path, bool includeAny) {// dart format on
  final segments = splitPath(path);
  final matches = <RouteData<T>>[];
  _findAll(root, method, segments, 0, matches, caseSensitive, includeAny);
  return matches.map((m) => m.materialize(segments)).toList();
}

// dart format off
List<RouteData<T>> _resolveMatchedRoutes<T>(bool includeAny, String method, Map<String, List<RouteData<T>>> methods) {// dart format on
  if (includeAny) return [...?methods[''], ...?methods[method]];
  return methods[method] ?? methods[''] ?? const [];
}

// dart format off
void _findAll<T>(RouterNode<T> node, String method, List<String> segments, int index, List<RouteData<T>> matches, bool caseSensitive, bool includeAny) {// dart format on
  // 1. Wildcard
  if (node.wildcard?.methods != null) {
    // dart format off
    final match = _resolveMatchedRoutes(includeAny, method, node.wildcard!.methods!); // dart format on
    if (match.isNotEmpty) matches.addAll(match);
  }

  // 2. Param
  if (node.param != null) {
    if (index < segments.length) {
      // dart format off
      _findAll(node.param!, method, segments, index + 1, matches, caseSensitive, includeAny); // dart format on
    } else if (node.param!.methods != null) {
      // dart format off
      final match = _resolveMatchedRoutes(includeAny, method, node.param!.methods!); // dart format on
      if (match.isNotEmpty && match.first.paramsMap?.last.optional == true) {
        matches.addAll(match);
      }
    }
  }

  // 3. Static
  if (index < segments.length) {
    final segment = caseSensitive
        ? segments[index]
        : segments[index].toLowerCase();
    if (node.statics?[segment] case final staticChild?) {
      // dart format off
      _findAll(staticChild, method, segments, index + 1, matches, caseSensitive, includeAny); // dart format on
    }
  }

  // 4. End of path
  if (index == segments.length && node.methods != null) {
    // dart format off
    final match = _resolveMatchedRoutes(includeAny, method, node.methods!); // dart format on
    if (match.isNotEmpty) matches.addAll(match);
  }
}

// dart format off
bool removeRoute<T>(RouterNode<T> root, Map<String, RouterNode<T>> staticRoutes, bool caseSensitive, String method, String path) {// dart format on
  if (expandGroupDelimiters(path) case final groupExpanded?) {
    var removed = false;
    for (final p in groupExpanded) {
      if (removeRoute(root, staticRoutes, caseSensitive, method, p)) {
        removed = true;
      }
    }
    return removed;
  }

  path = encodeEscapes(path);
  final segments = splitPath(path);

  if (expandModifiers(segments) case final modExpanded?) {
    var removed = false;
    for (final p in modExpanded) {
      if (removeRoute(root, staticRoutes, caseSensitive, method, p)) {
        removed = true;
      }
    }
    return removed;
  }

  final removed = _remove(root, method, segments, 0, caseSensitive);
  if (removed) {
    staticRoutes.remove(caseSensitive ? path : path.toLowerCase());
  }
  return removed;
}

// dart format off
bool _remove<T>(RouterNode<T> node, String method, List<String> segments, int index, bool caseSensitive) {// dart format on
  if (index == segments.length) {
    final methods = node.methods;
    if (methods == null || !methods.containsKey(method)) return false;
    methods.remove(method);
    if (methods.isEmpty) node.methods = null;
    return true;
  }

  final segment = segments[index];

  // Wildcard
  if (segment.startsWith('**')) {
    final child = node.wildcard;
    if (child == null) return false;
    final removed = _remove(child, method, segments, index + 1, caseSensitive);
    if (child.isEmpty) node.wildcard = null;
    return removed;
  }

  // Param
  if (_isParamSegment(segment)) {
    final child = node.param;
    if (child == null) return false;
    final removed = _remove(child, method, segments, index + 1, caseSensitive);
    if (child.isEmpty) node.param = null;
    return removed;
  }

  // Static
  var key = decodeEscaped(segment);
  if (!caseSensitive) key = key.toLowerCase();
  final child = node.statics?[key];
  if (child == null) return false;
  final removed = _remove(child, method, segments, index + 1, caseSensitive);
  if (child.isEmpty) {
    node.statics!.remove(key);
    if (node.statics!.isEmpty) node.statics = null;
  }

  return removed;
}

bool _isParamSegment(String segment) =>
    segment == '*' ||
    segment.contains(':') ||
    segment.contains('(') ||
    hasSegmentWildcard(segment);

final _simpleParamRx = RegExp(r'^:[\w-]+$');
final _modifierRx = RegExp(r'^(.*:[\w-]+(?:\([^)]*\))?)([?+*])$');

// dart format off
(SegmentPattern, int) compileSegmentPattern(String segment, bool caseSensitive, int unnamedStart) {// dart format on
  final regex = StringBuffer('^');
  final captureNames = <String>[];
  var nextUnnamed = unnamedStart;
  var cursor = 0;

  while (cursor < segment.length) {
    final code = segment.codeUnitAt(cursor);

    if (code == 58 /* : */ ) {
      final (next, name, body) = _readParamToken(segment, cursor);
      if (body == null) {
        regex.write('(?<$name>${r'[^/]+'})');
      } else {
        final (rewrittenBody, innerCaptureNames, nextIndex) =
            _rewriteUnnamedRegexGroups(body, nextUnnamed);
        regex.write('(?<$name>$rewrittenBody)');
        captureNames.addAll(innerCaptureNames);
        nextUnnamed = nextIndex;
      }
      captureNames.add(name);
      cursor = next;
      continue;
    }

    if (code == 40 /* ( */ ) {
      final end = _findRegexEnd(segment, cursor, segment.length);
      final name = toUnnamedGroupKey(nextUnnamed++);
      final body = segment.substring(cursor + 1, end);
      final (rewrittenBody, innerCaptureNames, nextIndex) =
          _rewriteUnnamedRegexGroups(body, nextUnnamed);
      regex.write('(?<$name>$rewrittenBody)');
      captureNames.add(name);
      captureNames.addAll(innerCaptureNames);
      nextUnnamed = nextIndex;
      cursor = end + 1;
      continue;
    }

    if (code == 42 /* * */ ) {
      final name = toUnnamedGroupKey(nextUnnamed++);
      regex.write('(?<$name>[^/]*)');
      captureNames.add(name);
      cursor++;
      continue;
    }

    final start = cursor++;
    while (cursor < segment.length) {
      final c = segment.codeUnitAt(cursor);
      if (c == 58 /* : */ || c == 42 /* * */ ) break;
      cursor++;
    }
    final literal = decodeEscaped(segment.substring(start, cursor));
    regex.write(RegExp.escape(literal));
  }

  regex.write(r'$');
  return (
    SegmentPattern(
      RegExp(regex.toString(), caseSensitive: caseSensitive),
      captureNames,
    ),
    nextUnnamed,
  );
}

(int, String, String?) _readParamToken(String segment, int start) {
  var nameEnd = start + 1;
  while (nameEnd < segment.length &&
      isParamCode(segment.codeUnitAt(nameEnd), nameEnd == start + 1)) {
    nameEnd++;
  }
  final name = segment.substring(start + 1, nameEnd);
  if (!validParamSlice(name, 0, name.length)) {
    throw FormatException('Invalid param name: $segment');
  }
  if (nameEnd < segment.length && segment.codeUnitAt(nameEnd) == 40 /* ( */ ) {
    final regexEnd = _findRegexEnd(segment, nameEnd, segment.length);
    return (regexEnd + 1, name, segment.substring(nameEnd + 1, regexEnd));
  }
  return (nameEnd, name, null);
}

int _findRegexEnd(String s, int start, int end) {
  var depth = 0;
  var escaped = false;
  var inClass = false;
  for (var i = start; i < end; i++) {
    final code = s.codeUnitAt(i);
    if (escaped) {
      escaped = false;
    } else if (code == 92) {
      escaped = true;
    } else if (inClass) {
      if (code == 93) inClass = false;
    } else if (code == 91) {
      inClass = true;
    } else if (code == 40) {
      depth++;
    } else if (code == 41 && --depth == 0) {
      return i;
    }
  }
  throw FormatException('Unclosed regex in route: $s');
}

// dart format off
(String, List<String>, int) _rewriteUnnamedRegexGroups(String pattern, int unnamedStart) {// dart format on
  final regex = StringBuffer();
  final captureNames = <String>[];
  var nextUnnamed = unnamedStart;
  var escaped = false;
  var inClass = false;

  for (var i = 0; i < pattern.length; i++) {
    final code = pattern.codeUnitAt(i);

    if (escaped) {
      regex.write(pattern[i]);
      escaped = false;
      continue;
    }

    if (code == 92 /* \ */ ) {
      regex.write(pattern[i]);
      escaped = true;
      continue;
    }

    if (inClass) {
      regex.write(pattern[i]);
      if (code == 93 /* ] */ ) {
        inClass = false;
      }
      continue;
    }

    if (code == 91 /* [ */ ) {
      regex.write(pattern[i]);
      inClass = true;
      continue;
    }

    if (code == 40 /* ( */ ) {
      final nextCode = i + 1 < pattern.length ? pattern.codeUnitAt(i + 1) : -1;
      if (nextCode == 63 /* ? */ ) {
        regex.write(pattern[i]);
        continue;
      }

      final name = toUnnamedGroupKey(nextUnnamed++);
      regex.write('(?<$name>');
      captureNames.add(name);
      continue;
    }

    regex.write(pattern[i]);
  }

  return (regex.toString(), captureNames, nextUnnamed);
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

String decodeEscaped(String segment) => segment
    .replaceAll('\uFFFDA', ':')
    .replaceAll('\uFFFDB', '(')
    .replaceAll('\uFFFDC', ')')
    .replaceAll('\uFFFDD', '{')
    .replaceAll('\uFFFDE', '}');

List<String>? expandGroupDelimiters(String path) {
  var start = -1;
  var depth = 0;
  for (var i = 0; i < path.length; i++) {
    final code = path.codeUnitAt(i);
    if (code == 92) {
      i++;
    } else if (code == 40) {
      depth++;
    } else if (code == 41 && depth > 0) {
      depth--;
    } else if (code == 123 /* { */ && depth == 0) {
      start = i;
      break;
    }
  }
  if (start < 0) return null;

  var end = -1;
  depth = 0;
  for (var i = start + 1; i < path.length; i++) {
    final code = path.codeUnitAt(i);
    if (code == 92) {
      i++;
    } else if (code == 40) {
      depth++;
    } else if (code == 41 && depth > 0) {
      depth--;
    } else if (code == 125 /* } */ && depth == 0) {
      end = i;
      break;
    }
  }
  if (end < 0) throw FormatException('Unclosed group in route: $path');

  final hasMod =
      end + 1 < path.length &&
      (path.codeUnitAt(end + 1) == 63 /* ? */ ||
          path.codeUnitAt(end + 1) == 43 /* + */ ||
          path.codeUnitAt(end + 1) == 42 /* * */ );
  final mod = hasMod ? path[end + 1] : null;
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
    final m = _modifierRx.firstMatch(segments[i]);
    if (m == null) continue;
    final base = m.group(1)!;
    final mod = m.group(2)!;
    final pre = segments.sublist(0, i);
    final suf = segments.sublist(i + 1);
    if (mod == '?') {
      return [
        '/${[...pre, base, ...suf].join('/')}',
        '/${[...pre, ...suf].join('/')}',
      ];
    }
    final name = RegExp(r':([\w-]+)').firstMatch(base)?.group(1) ?? '_';
    final wc = '/${[...pre, '**:$name', ...suf].join('/')}';
    return mod == '+'
        ? [wc]
        : [
            wc,
            '/${[...pre, ...suf].join('/')}',
          ];
  }
  return null;
}

bool hasSegmentWildcard(String segment) {
  var depth = 0;
  for (var i = 0; i < segment.length; i++) {
    final code = segment.codeUnitAt(i);
    if (code == 92) {
      i++;
    } else if (code == 40) {
      depth++;
    } else if (code == 41 && depth > 0) {
      depth--;
    } else if (code == 42 /* * */ && depth == 0) {
      return true;
    }
  }
  return false;
}

String toUnnamedGroupKey(int index) => '$unnamedGroupPrefix$index';

extension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
