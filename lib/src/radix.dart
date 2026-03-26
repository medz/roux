// rou3-style route operations translated to Dart.
// ignore_for_file: public_member_api_docs

import 'model.dart';

void addRoute<T>(
  RouterNode<T> root,
  Map<String, RouterNode<T>> staticRoutes,
  bool caseSensitive,
  String method,
  String path,
  T data,
  DuplicatePolicy policy,
  int order, {
  bool structured = false,
  bool? restOptional,
}) {
  if (!path.startsWith('/')) path = '/$path';

  final expandedGroups = expandGroupDelimiters(path);
  if (expandedGroups != null) {
    for (final expanded in expandedGroups) {
      addRoute(
        root,
        staticRoutes,
        caseSensitive,
        method,
        expanded,
        data,
        policy,
        order,
        structured: true,
        restOptional: restOptional,
      );
    }
    return;
  }

  path = encodeEscapes(path);
  final segments = splitPath(path);
  final expanded = expandModifiers(segments);
  if (expanded != null) {
    for (final expansion in expanded) {
      addRoute(
        root,
        staticRoutes,
        caseSensitive,
        method,
        expansion.path,
        data,
        policy,
        order,
        structured: structured || expansion.structured,
        restOptional: expansion.restOptional,
      );
    }
    return;
  }

  var node = root;
  var unnamedIndex = 0;
  final paramsMap = <ParamSpec>[];
  final paramsRegexp = <SegmentPattern?>[];
  final captureNames = <String>[];
  final shape = StringBuffer(structured ? 'struct:' : '');
  var staticChars = 0;
  var sawParam = false;
  var sawHigh = false;
  var sawLow = false;
  var sawRest = false;
  final routeCaptureNames = <String>{};

  for (var i = 0; i < segments.length; i++) {
    var segment = segments[i];

    if (segment.startsWith('**')) {
      if (i != segments.length - 1) {
        throw FormatException('Double wildcard must be the final segment: /$path');
      }
      node.wildcard ??= RouterNode<T>('**');
      node = node.wildcard!;
      final name = _readRestName(segment);
      paramsMap.add(ParamSpec(-(i + 1), name ?? '_', restOptional ?? true));
      _recordCaptureName(routeCaptureNames, captureNames, name ?? '_', path);
      shape.write('/**');
      sawRest = true;
      break;
    }

    final isDynamic =
        segment == '*' ||
        segment.contains(':') ||
        segment.contains('(') ||
        hasSegmentWildcard(segment);
    if (isDynamic) {
      node.param ??= RouterNode<T>('*');
      node = node.param!;

      if (segment == '*') {
        final name = toUnnamedGroupKey(unnamedIndex++);
        paramsMap.add(ParamSpec(i, name, true));
        _recordCaptureName(routeCaptureNames, captureNames, name, path);
        shape.write('/*');
        sawLow = true;
        continue;
      }

      final isSimpleParam =
          !segment.contains(':', 1) &&
          !segment.contains('(') &&
          !hasSegmentWildcard(segment) &&
          RegExp(r'^:[\w-]+$').hasMatch(segment);
      if (isSimpleParam) {
        final name = segment.substring(1);
        if (!validParamSlice(name, 0, name.length)) {
          throw FormatException('Invalid parameter name in route: /$path');
        }
        paramsMap.add(ParamSpec(i, name, false));
        _recordCaptureName(routeCaptureNames, captureNames, name, path);
        shape.write('/:');
        sawParam = true;
        continue;
      }

      final compiled = compileSegmentPattern(segment, caseSensitive, unnamedIndex);
      unnamedIndex = compiled.nextUnnamed;
      paramsRegexp.length = i + 1;
      paramsRegexp[i] = compiled.pattern;
      paramsMap.add(ParamSpec(i, compiled.pattern, false));
      for (final name in compiled.captureNames) {
        _recordCaptureName(routeCaptureNames, captureNames, name, path);
      }
      node.hasRegexParam = true;
      shape
        ..write('/')
        ..write(compiled.shape);
      staticChars += compiled.staticChars;
      if (compiled.lowPriority) {
        sawLow = true;
      } else {
        sawHigh = true;
      }
      continue;
    }

    if (segment == r'\*') {
      segment = '*';
    } else if (segment == r'\*\*') {
      segment = '**';
    } else {
      segment = decodeEscaped(segment);
    }

    final key = caseSensitive ? segment : segment.toLowerCase();
    node.statics ??= {};
    node = node.statics!.putIfAbsent(key, () => RouterNode<T>(key));
    shape
      ..write('/')
      ..write(key);
    staticChars += segment.length;
  }

  final hasParams = paramsMap.isNotEmpty;
  final specificity = _routeSpecificity(hasParams, structured, sawHigh, sawLow);
  final routeSpecificity = sawRest && !structured && !sawHigh && !sawLow
      ? specRem
      : specificity;
  final matchSpecificity = _matchSpecificity(hasParams, structured, sawParam, sawHigh, sawLow);
  final route = RouteData<T>(
    data: data,
    shapeKey: shape.toString().isEmpty ? '/' : shape.toString(),
    captureNames: captureNames,
    paramsMap: hasParams ? paramsMap : null,
    paramsRegexp: paramsRegexp,
    order: order,
    rank: computeRank(routeSpecificity, segments.length, staticChars, _constraintScore(sawHigh, sawLow)),
    matchRank: computeRank(
      matchSpecificity,
      segments.length,
      staticChars,
      _constraintScore(sawHigh, sawLow),
    ),
    emptyParams: structured && !hasParams,
  );

  _addMethodRoute(node, method, route, policy, path);
  if (!hasParams) {
    staticRoutes['/${segments.join('/')}'] = node;
  }
}

RouteMatch<T>? findRoute<T>(
  RouterNode<T> root,
  Map<String, RouterNode<T>> staticRoutes,
  bool caseSensitive,
  String method,
  String path,
) {
  final staticNode = staticRoutes[caseSensitive ? path : path.toLowerCase()];
  if (staticNode != null) {
    final match = _lookupMethods(staticNode.methods, method);
    if (match != null) return match.first.materialize(const []);
  }

  final segments = splitPath(path);
  final match = _lookupTree(root, method, segments, 0, caseSensitive)?.firstOrNull;
  return match?.materialize(segments);
}

List<RouteMatch<T>> findAllRoutes<T>(
  RouterNode<T> root,
  bool caseSensitive,
  String method,
  String path,
) {
  final segments = splitPath(path);
  final acc = MatchAccumulator<T>();
  _collectAll(root, method, segments, 0, caseSensitive, acc);
  return acc.results;
}

List<RouteData<T>>? _lookupTree<T>(
  RouterNode<T> node,
  String method,
  List<String> segments,
  int index,
  bool caseSensitive,
) {
  if (index == segments.length) {
    final end = _lookupMethods(node.methods, method);
    if (end != null && end.isNotEmpty) return end;

    final param = node.param;
    if (param != null) {
      final tail = _lookupMethods(param.methods, method);
      if (tail != null &&
          tail.isNotEmpty &&
          tail.first.paramsMap?.last.optional == true) {
        return tail;
      }
    }

    final wildcard = node.wildcard;
    if (wildcard != null) {
      final tail = _lookupMethods(wildcard.methods, method);
      if (tail != null &&
          tail.isNotEmpty &&
          tail.first.paramsMap?.last.optional == true) {
        return tail;
      }
    }
    return null;
  }

  final rawSegment = segments[index];
  final segment = caseSensitive ? rawSegment : rawSegment.toLowerCase();

  final staticChild = node.statics?[segment];
  if (staticChild != null) {
    final match = _lookupTree(staticChild, method, segments, index + 1, caseSensitive);
    if (match != null) return match;
  }

  final param = node.param;
  if (param != null) {
    final match = _lookupTree(param, method, segments, index + 1, caseSensitive);
    if (match != null) {
      if (param.hasRegexParam) {
        for (final route in match) {
          final pattern = index < route.paramsRegexp.length ? route.paramsRegexp[index] : null;
          if (pattern == null || pattern.regex.hasMatch(rawSegment)) {
            return [route];
          }
        }
        return null;
      }
      return match;
    }
  }

  final wildcard = node.wildcard;
  if (wildcard != null) {
    final match = _lookupMethods(wildcard.methods, method);
    if (match != null) return match;
  }

  return null;
}

void _collectAll<T>(
  RouterNode<T> node,
  String method,
  List<String> segments,
  int index,
  bool caseSensitive,
  MatchAccumulator<T> acc,
) {
  final wildcard = node.wildcard;
  if (wildcard != null) {
    _addBucketMatches(wildcard.methods, method, segments, acc);
  }

  final param = node.param;
  if (param != null) {
    _collectAll(param, method, segments, index + 1, caseSensitive, acc);
    if (index == segments.length) {
      final tail = _lookupMethods(param.methods, method);
      if (tail != null &&
          tail.isNotEmpty &&
          tail.first.paramsMap?.last.optional == true) {
        _addRoutes(tail, 1, segments, acc);
      }
    }
  }

  if (index < segments.length) {
    final rawSegment = segments[index];
    final segment = caseSensitive ? rawSegment : rawSegment.toLowerCase();
    final staticChild = node.statics?[segment];
    if (staticChild != null) {
      _collectAll(staticChild, method, segments, index + 1, caseSensitive, acc);
    }
  }

  if (index == segments.length) {
    _addBucketMatches(node.methods, method, segments, acc);
  }
}

void _addBucketMatches<T>(
  Map<String, List<RouteData<T>>>? methods,
  String method,
  List<String> segments,
  MatchAccumulator<T> acc,
) {
  if (methods == null) return;
  final any = methods[''];
  if (any != null) _addRoutes(any, 0, segments, acc);
  if (method.isNotEmpty) {
    final exact = methods[method];
    if (exact != null) _addRoutes(exact, 1, segments, acc);
  }
}

void _addRoutes<T>(
  List<RouteData<T>> routes,
  int methodRank,
  List<String> segments,
  MatchAccumulator<T> acc,
) {
  for (final route in routes) {
    acc.add(route.materialize(segments), route.rank, methodRank, route.order);
  }
}

List<RouteData<T>>? _lookupMethods<T>(
  Map<String, List<RouteData<T>>>? methods,
  String method,
) {
  if (methods == null) return null;
  return methods[method] ?? methods[''];
}

void _addMethodRoute<T>(
  RouterNode<T> node,
  String method,
  RouteData<T> route,
  DuplicatePolicy policy,
  String pattern,
) {
  node.methods ??= {};
  final bucket = node.methods!.putIfAbsent(method, () => <RouteData<T>>[]);
  final duplicateIndexes = <int>[];
  for (var i = 0; i < bucket.length; i++) {
    if (bucket[i].shapeKey == route.shapeKey) {
      duplicateIndexes.add(i);
    }
  }

  if (duplicateIndexes.isNotEmpty) {
    for (final index in duplicateIndexes) {
      final existing = bucket[index];
      if (!_sameCaptureNames(existing.captureNames, route.captureNames)) {
        throw FormatException('$dupShape$pattern');
      }
    }

    switch (policy) {
      case DuplicatePolicy.reject:
        throw FormatException('${_dupPrefix(route.paramsMap, pattern)}$pattern');
      case DuplicatePolicy.replace:
        for (var i = duplicateIndexes.length - 1; i >= 0; i--) {
          bucket.removeAt(duplicateIndexes[i]);
        }
        bucket.add(route);
      case DuplicatePolicy.keepFirst:
        return;
      case DuplicatePolicy.append:
        bucket.add(route);
    }
  } else {
    bucket.add(route);
  }
  bucket.sort((a, b) {
    final r = b.matchRank - a.matchRank;
    return r != 0 ? r : a.order - b.order;
  });
}

bool _sameCaptureNames(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (normalizeUnnamedGroupKey(a[i]) != normalizeUnnamedGroupKey(b[i])) {
      return false;
    }
  }
  return true;
}

String _dupPrefix(List<ParamSpec>? paramsMap, String pattern) {
  if (paramsMap == null || paramsMap.isEmpty) return dupShape;
  final last = paramsMap.last;
  if (last.index < 0) {
    return paramsMap.length == 1 && last.index == -1 ? dupFallback : dupWildcard;
  }
  return dupShape;
}

int _routeSpecificity(
  bool hasParams,
  bool structured,
  bool sawHigh,
  bool sawLow,
) {
  if (!hasParams) return structured ? specStruct : specExact;
  if (sawHigh || sawLow || structured) return specStruct;
  return specDyn;
}

int _matchSpecificity(
  bool hasParams,
  bool structured,
  bool sawParam,
  bool sawHigh,
  bool sawLow,
) {
  if (!hasParams && !structured) return 5;
  if (sawHigh || (structured && !hasParams)) return 4;
  if (sawParam && !structured) return 3;
  if (hasParams || sawLow || structured) return 2;
  return 1;
}

int _constraintScore(bool sawHigh, bool sawLow) => sawHigh ? 2 : sawLow ? 1 : 0;

class CompiledSegmentPattern {
  const CompiledSegmentPattern(
    this.pattern,
    this.shape,
    this.captureNames,
    this.staticChars,
    this.lowPriority,
    this.nextUnnamed,
  );

  final SegmentPattern pattern;
  final String shape;
  final List<String> captureNames;
  final int staticChars;
  final bool lowPriority;
  final int nextUnnamed;
}

class ModifierExpansion {
  const ModifierExpansion(this.path, this.structured, [this.restOptional]);

  final String path;
  final bool structured;
  final bool? restOptional;
}

CompiledSegmentPattern compileSegmentPattern(
  String segment,
  bool caseSensitive,
  int unnamedStart,
) {
  final regex = StringBuffer('^');
  final shape = StringBuffer();
  final captureNames = <String>[];
  var staticChars = 0;
  var nextUnnamed = unnamedStart;
  var cursor = 0;
  var lastWasCapture = false;

  while (cursor < segment.length) {
    final code = segment.codeUnitAt(cursor);
    if (code == colonCode) {
      if (lastWasCapture) {
        throw FormatException('Unsupported segment syntax in route: /$segment');
      }
      final (next, name, body) = _readParamToken(segment, cursor);
      final groupName = name;
      if (body != null) {
        regex.write('(?<$groupName>$body)');
        shape.write('($body)');
      } else {
        regex.write('(?<$groupName>[^/]+)');
        shape.write('(:)');
      }
      captureNames.add(groupName);
      cursor = next;
      lastWasCapture = true;
      continue;
    }

    if (code == asteriskCode) {
      final name = toUnnamedGroupKey(nextUnnamed++);
      regex.write('(?<$name>[^/]*)');
      shape.write('(*)');
      captureNames.add(name);
      cursor++;
      lastWasCapture = false;
      continue;
    }

    final start = cursor++;
    while (cursor < segment.length) {
      final next = segment.codeUnitAt(cursor);
      if (next == colonCode || next == asteriskCode) break;
      cursor++;
    }
    final literal = resolveEscapePlaceholders(segment.substring(start, cursor));
    regex.write(RegExp.escape(literal));
    shape.write(RegExp.escape(caseSensitive ? literal : literal.toLowerCase()));
    staticChars += literal.length;
    lastWasCapture = false;
  }

  regex.write(r'$');
  return CompiledSegmentPattern(
    SegmentPattern(
      RegExp(regex.toString(), caseSensitive: caseSensitive),
      captureNames,
    ),
    shape.toString(),
    captureNames.map(normalizeUnnamedGroupKey).toList(),
    staticChars,
    false,
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
    throw FormatException('Invalid parameter name in route: /$segment');
  }
  if (nameEnd < segment.length && segment.codeUnitAt(nameEnd) == 40) {
    final regexEnd = _findRegexEnd(segment, nameEnd, segment.length);
    return (regexEnd + 1, name, segment.substring(nameEnd + 1, regexEnd));
  }
  return (nameEnd, name, null);
}

String encodeEscapes(String path) => path
    .replaceAll(r'\:', '\uFFFDA')
    .replaceAll(r'\(', '\uFFFDB')
    .replaceAll(r'\)', '\uFFFDC')
    .replaceAll(r'\{', '\uFFFDD')
    .replaceAll(r'\}', '\uFFFDE')
    .replaceAll(r'\*', '\uFFFDW');

String decodeEscaped(String segment) => resolveEscapePlaceholders(segment)
    .replaceAll('\uFFFDW', '*');

String resolveEscapePlaceholders(String value) => value
    .replaceAll('\uFFFDA', ':')
    .replaceAll('\uFFFDB', '(')
    .replaceAll('\uFFFDC', ')')
    .replaceAll('\uFFFDD', '{')
    .replaceAll('\uFFFDE', '}');

List<ModifierExpansion>? expandModifiers(List<String> segments) {
  final rx = RegExp(r'^(.*:[\w-]+(?:\([^)]*\))?)([?+*])$');
  for (var i = 0; i < segments.length; i++) {
    final match = rx.firstMatch(segments[i]);
    if (match == null) continue;
    final base = match.group(1)!;
    final modifier = match.group(2)!;
    final pre = segments.sublist(0, i);
    final suf = segments.sublist(i + 1);
    if (modifier == '?') {
      return [
        ModifierExpansion('/${[...pre, base, ...suf].join('/')}', true),
        ModifierExpansion('/${[...pre, ...suf].join('/')}', true),
      ];
    }
    final name = RegExp(r':([\w-]+)').firstMatch(base)?.group(1) ?? '_';
    final wildcard = '/${[...pre, '**:$name', ...suf].join('/')}';
    if (modifier == '+') return [ModifierExpansion(wildcard, false, false)];
    return [
      ModifierExpansion(wildcard, false, true),
      ModifierExpansion('/${[...pre, ...suf].join('/')}', true),
    ];
  }
  return null;
}

List<String>? expandGroupDelimiters(String path) {
  final start = _findStructuredBrace(path);
  if (start < 0) return null;
  final end = _findGroupEnd(path, start);
  final hasMod = end + 1 < path.length &&
      (path.codeUnitAt(end + 1) == questionCode ||
          path.codeUnitAt(end + 1) == plusCode ||
          path.codeUnitAt(end + 1) == asteriskCode);
  final mod = hasMod ? path[end + 1] : null;
  final pre = path.substring(0, start);
  final body = path.substring(start + 1, end);
  final suf = path.substring(end + (hasMod ? 2 : 1));
  if (!hasMod) return ['$pre$body$suf'];
  if (mod == '?') return ['$pre$body$suf', '$pre$suf'];
  if (body.contains('/')) {
    throw FormatException('unsupported group repetition across segments');
  }
  return ['$pre(?:$body)$mod$suf'];
}

int _findStructuredBrace(String pattern) {
  var depth = 0;
  for (var i = 0; i < pattern.length; i++) {
    final code = pattern.codeUnitAt(i);
    if (code == 92) {
      i++;
      continue;
    }
    if (code == 40) {
      depth++;
      continue;
    }
    if (code == 41 && depth > 0) {
      depth--;
      continue;
    }
    if (code == openBraceCode && depth == 0) return i;
  }
  return -1;
}

int _findGroupEnd(String pattern, int start) {
  var depth = 0;
  for (var i = start; i < pattern.length; i++) {
    final code = pattern.codeUnitAt(i);
    if (code == 92) {
      i++;
      continue;
    }
    if (code == 40) {
      depth++;
      continue;
    }
    if (code == 41 && depth > 0) {
      depth--;
      continue;
    }
    if (code == openBraceCode && depth == 0) {
      depth = -1;
      continue;
    }
    if (code == closeBraceCode && depth == -1) return i;
  }
  throw FormatException('Unclosed group in route: $pattern');
}

bool hasSegmentWildcard(String segment) {
  var depth = 0;
  for (var i = 0; i < segment.length; i++) {
    final code = segment.codeUnitAt(i);
    if (code == 92) {
      i++;
      continue;
    }
    if (code == 40) {
      depth++;
      continue;
    }
    if (code == 41 && depth > 0) {
      depth--;
      continue;
    }
    if (code == asteriskCode && depth == 0) return true;
  }
  return false;
}

List<String> splitPath(String path) {
  if (path == '/') return const [];
  final parts = path.split('/');
  final segments = parts.sublist(1);
  if (segments.isNotEmpty && segments.last.isEmpty) {
    return segments.sublist(0, segments.length - 1);
  }
  return segments;
}

String toUnnamedGroupKey(int index) => '$unnamedGroupPrefix$index';

String? _readRestName(String segment) {
  if (segment == '**') return '_';
  if (!segment.startsWith('**:')) {
    throw FormatException('Invalid wildcard segment: /$segment');
  }
  final name = segment.substring(3);
  if (!validParamSlice(name, 0, name.length)) {
    throw FormatException('Invalid parameter name in route: /$segment');
  }
  return name;
}

int _findRegexEnd(String pattern, int start, int end) {
  var depth = 0;
  var escaped = false;
  var inClass = false;
  for (var i = start; i < end; i++) {
    final code = pattern.codeUnitAt(i);
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
  throw FormatException('Unclosed regex in route: $pattern');
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

void _recordCaptureName(
  Set<String> seen,
  List<String> captureNames,
  String name,
  String path,
) {
  final normalized = normalizeUnnamedGroupKey(name);
  if (!seen.add(normalized)) {
    throw FormatException('Duplicate capture name in route: $path');
  }
  captureNames.add(name);
}
