export 'types.dart' show DuplicatePolicy, RouteMatch;

import 'input_path.dart';
import 'pattern_engine.dart';
import 'route_entry.dart';
import 'simple_engine.dart';
import 'specificity.dart';
import 'types.dart';

class Router<T> {
  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
    bool caseSensitive = true,
    bool decodePath = false,
    bool normalizePath = false,
  }) : _duplicatePolicy = duplicatePolicy,
       _caseSensitive = caseSensitive,
       _decodePath = decodePath,
       _normalizePath = normalizePath,
       _anyRoutes = RouteSet<T>(caseSensitive) {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }

  final RouteSet<T> _anyRoutes;
  final MethodTable<T> _methodRoutes = MethodTable<T>();
  final DuplicatePolicy _duplicatePolicy;
  final bool _caseSensitive;
  final bool _decodePath;
  final bool _normalizePath;
  int _nextRegistrationOrder = 0;

  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    routeSetForWrite(method).addPattern(
      path,
      data,
      duplicatePolicy ?? _duplicatePolicy,
      _nextRegistrationOrder++,
    );
  }

  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final routeSet = routeSetForWrite(method);
    final policy = duplicatePolicy ?? _duplicatePolicy;
    for (final entry in routes.entries) {
      routeSet.addPattern(
        entry.key,
        entry.value,
        policy,
        _nextRegistrationOrder++,
      );
    }
  }

  RouteMatch<T>? match(String path, {String? method}) {
    final normalized = prepareInputPath(path);
    if (normalized == null) return null;
    final routeSet = method == null
        ? null
        : _methodRoutes.lookup(normalizeMethod(method));
    return (routeSet == null ? null : routeSet.match(normalized)) ??
        _anyRoutes.match(normalized);
  }

  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final normalized = prepareInputPath(path);
    if (normalized == null) return <RouteMatch<T>>[];
    final routeSet = method == null
        ? null
        : _methodRoutes.lookup(normalizeMethod(method));
    final collected = MatchCollector<T>(
      routeSet != null ||
          _anyRoutes.needsSpecificitySort ||
          (routeSet != null && routeSet.needsSpecificitySort),
    );
    _anyRoutes.collect(normalized, 0, collected);
    if (routeSet != null) routeSet.collect(normalized, 1, collected);
    return collected.matches;
  }

  RouteSet<T> routeSetForWrite(String? method) => method == null
      ? _anyRoutes
      : _methodRoutes.forWrite(normalizeMethod(method), _caseSensitive);

  String? prepareInputPath(String path) {
    if (_decodePath && path.contains('%')) {
      try {
        path = Uri.decodeFull(path);
      } on ArgumentError {
        return null;
      }
    }
    return _normalizePath ? normalizePathInput(path) : normalizeInputPath(path);
  }
}

class RouteSet<T> {
  RouteSet(this.caseSensitive)
    : simple = SimpleEngine<T>(),
      pattern = PatternEngine<T>(caseSensitive);

  final bool caseSensitive;
  final Map<String, RouteEntry<T>> exactRoutes = <String, RouteEntry<T>>{};
  final SimpleEngine<T> simple;
  final PatternEngine<T> pattern;

  bool get needsSpecificitySort =>
      simple.hasBranchingChoices ||
      simple.root.paramChild != null ||
      pattern.needsSpecificitySort;

  void addPattern(
    String patternPath,
    T data,
    DuplicatePolicy duplicatePolicy,
    int registrationOrder,
  ) {
    if (patternPath.isEmpty || patternPath.codeUnitAt(0) != slashCode) {
      throw FormatException('Route pattern must start with "/": $patternPath');
    }

    var end = patternPath.length;
    if (end > 1 && patternPath.codeUnitAt(end - 1) == slashCode) {
      if (patternPath.codeUnitAt(end - 2) == slashCode) {
        throw FormatException('$emptySegment$patternPath');
      }
      end -= 1;
    }

    var hasReservedToken = false;
    var prevSlash = true;
    var exactDepth = 0;
    var exactStaticChars = 0;
    for (var i = 1; i < end; i++) {
      final code = patternPath.codeUnitAt(i);
      if (code == slashCode) {
        if (prevSlash) throw FormatException('$emptySegment$patternPath');
        exactDepth += 1;
        prevSlash = true;
        continue;
      }
      if (code == colonCode ||
          code == asteriskCode ||
          code == openBraceCode ||
          code == closeBraceCode ||
          code == questionCode) {
        hasReservedToken = true;
        break;
      }
      exactStaticChars += 1;
      prevSlash = false;
    }
    if (!hasReservedToken && end > 1 && !prevSlash) exactDepth += 1;

    final normalized = end == patternPath.length
        ? patternPath
        : patternPath.substring(0, end);
    final canonical = canonicalPath(normalized, caseSensitive);
    if (!hasReservedToken) {
      exactRoutes[canonical] = mergeRouteEntries(
        exactRoutes[canonical],
        newRoute(
          data,
          const <String>[],
          null,
          normalized,
          exactDepth,
          exactSpecificity,
          exactStaticChars,
          0,
          registrationOrder,
        ),
        normalized,
        duplicatePolicy,
        dupShape,
      );
      return;
    }

    List<String>? paramNames;
    var paramCount = 0;
    var staticChars = 0;
    var depth = 0;
    var node = simple.root;
    for (var cursor = end == 1 ? end : 1; cursor < end;) {
      var segmentEnd = cursor;
      var hasReservedInSegment = false;
      while (segmentEnd < end) {
        final code = patternPath.codeUnitAt(segmentEnd);
        if (code == slashCode) break;
        if (code == colonCode ||
            code == asteriskCode ||
            code == openBraceCode ||
            code == closeBraceCode ||
            code == questionCode) {
          hasReservedInSegment = true;
        }
        segmentEnd += 1;
      }
      if (segmentEnd == cursor)
        throw FormatException('$emptySegment$patternPath');

      final firstCode = patternPath.codeUnitAt(cursor);
      final doubleWildcardName = firstCode == asteriskCode
          ? readDoubleWildcardName(patternPath, cursor, segmentEnd)
          : null;
      if (doubleWildcardName != null) {
        if (segmentEnd != end) {
          throw FormatException(
            'Double wildcard must be the last segment: $normalized',
          );
        }
        final route = newRoute(
          data,
          paramNames ?? const <String>[],
          doubleWildcardName,
          normalized,
          depth,
          remainderSpecificity,
          staticChars,
          0,
          registrationOrder,
        );
        if (cursor == 1 && paramCount == 0) {
          simple.mergeFallbackRoute(route, normalized, duplicatePolicy);
        } else {
          simple.mergeWildcardRoute(node, route, normalized, duplicatePolicy);
        }
        if (paramCount > simple.maxParamDepth)
          simple.maxParamDepth = paramCount;
        return;
      }

      if (firstCode == colonCode) {
        if (!hasValidParamNameSlice(patternPath, cursor + 1, segmentEnd)) {
          pattern.add(normalized, data, duplicatePolicy, registrationOrder);
          return;
        }
        if (node.staticChild != null ||
            node.staticMap != null ||
            node.leafRoutes != null) {
          simple.hasBranchingChoices = true;
        }
        final paramName = patternPath.substring(cursor + 1, segmentEnd);
        node = node.paramChild ??= SimpleNode<T>();
        (paramNames ??= <String>[]).add(paramName);
        paramCount += 1;
      } else {
        if (hasReservedInSegment) {
          pattern.add(normalized, data, duplicatePolicy, registrationOrder);
          return;
        }
        final key = canonicalPath(
          patternPath.substring(cursor, segmentEnd),
          caseSensitive,
        );
        if (segmentEnd == end) {
          if (node.paramChild != null || node.wildcardRoute != null) {
            simple.hasBranchingChoices = true;
          }
          simple.mergeLeafRoute(
            node,
            key,
            newRoute(
              data,
              paramNames ?? const <String>[],
              null,
              normalized,
              depth + 1,
              paramCount == 0 ? exactSpecificity : singleDynamicSpecificity,
              staticChars + segmentEnd - cursor,
              0,
              registrationOrder,
            ),
            normalized,
            duplicatePolicy,
          );
          if (paramCount > simple.maxParamDepth)
            simple.maxParamDepth = paramCount;
          return;
        }
        if (node.paramChild != null) simple.hasBranchingChoices = true;
        node = node.getOrCreateStaticChildSlice(key);
        staticChars += segmentEnd - cursor;
      }

      depth += 1;
      cursor = segmentEnd + 1;
    }

    simple.mergeExactRoute(
      node,
      newRoute(
        data,
        paramNames ?? const <String>[],
        null,
        normalized,
        depth,
        paramCount == 0 ? exactSpecificity : singleDynamicSpecificity,
        staticChars,
        0,
        registrationOrder,
      ),
      normalized,
      duplicatePolicy,
    );
    if (paramCount > simple.maxParamDepth) simple.maxParamDepth = paramCount;
  }

  RouteMatch<T>? match(String normalized) {
    if (exactRoutes.isNotEmpty) {
      final exact =
          exactRoutes[canonicalPath(normalized, caseSensitive)]?.noParamsMatch;
      if (exact != null) return exact;
    }
    if (!pattern.hasAny && simple.globalFallback == null) {
      return simple.hasBranchingChoices
          ? simple.match(normalized, caseSensitive, true)
          : simple.matchStraight(normalized, caseSensitive);
    }
    final heads = pattern.heads;
    final compiled = heads[compiledBucketHigh];
    final repeated = heads[compiledBucketRepeated];
    final late = heads[compiledBucketLate];
    final deferred = heads[compiledBucketDeferred];
    return (compiled == null
            ? null
            : pattern.matchHead(compiled, normalized)) ??
        simple.match(normalized, caseSensitive, false) ??
        (late == null ? null : pattern.matchHead(late, normalized)) ??
        (repeated == null ? null : pattern.matchHead(repeated, normalized)) ??
        simple.match(normalized, caseSensitive, true) ??
        (deferred == null ? null : pattern.matchHead(deferred, normalized)) ??
        (simple.globalFallback == null
            ? null
            : simple.materialize(simple.globalFallback!, normalized, null, 1));
  }

  void collect(String normalized, int methodRank, MatchCollector<T> output) {
    final fallback = simple.globalFallback;
    if (fallback != null) {
      simple.collectSlot(fallback, normalized, null, 1, methodRank, output);
    }
    final heads = pattern.heads;
    final repeated = heads[compiledBucketRepeated];
    if (repeated != null) {
      pattern.collectHead(repeated, normalized, methodRank, output);
    }
    simple.collect(normalized, caseSensitive, methodRank, output);
    final compiled = heads[compiledBucketHigh];
    if (compiled != null) {
      pattern.collectHead(compiled, normalized, methodRank, output);
    }
    final late = heads[compiledBucketLate];
    if (late != null) {
      pattern.collectHead(late, normalized, methodRank, output);
    }
    if (exactRoutes.isNotEmpty) {
      final exact = exactRoutes[canonicalPath(normalized, caseSensitive)];
      if (exact != null) {
        simple.collectSlot(exact, normalized, null, 0, methodRank, output);
      }
    }
    final deferred = heads[compiledBucketDeferred];
    if (deferred != null) {
      pattern.collectHead(deferred, normalized, methodRank, output);
    }
  }
}

class MethodTable<T> {
  RouteSet<T>? getRoutes;
  RouteSet<T>? postRoutes;
  RouteSet<T>? putRoutes;
  RouteSet<T>? patchRoutes;
  RouteSet<T>? deleteRoutes;
  RouteSet<T>? headRoutes;
  RouteSet<T>? optionsRoutes;
  Map<String, RouteSet<T>>? extraRoutes;

  RouteSet<T> forWrite(String method, bool caseSensitive) {
    switch (method) {
      case 'GET':
        return getRoutes ??= RouteSet<T>(caseSensitive);
      case 'POST':
        return postRoutes ??= RouteSet<T>(caseSensitive);
      case 'PUT':
        return putRoutes ??= RouteSet<T>(caseSensitive);
      case 'PATCH':
        return patchRoutes ??= RouteSet<T>(caseSensitive);
      case 'DELETE':
        return deleteRoutes ??= RouteSet<T>(caseSensitive);
      case 'HEAD':
        return headRoutes ??= RouteSet<T>(caseSensitive);
      case 'OPTIONS':
        return optionsRoutes ??= RouteSet<T>(caseSensitive);
      default:
        return (extraRoutes ??= <String, RouteSet<T>>{}).putIfAbsent(
          method,
          () => RouteSet<T>(caseSensitive),
        );
    }
  }

  RouteSet<T>? lookup(String method) {
    switch (method) {
      case 'GET':
        return getRoutes;
      case 'POST':
        return postRoutes;
      case 'PUT':
        return putRoutes;
      case 'PATCH':
        return patchRoutes;
      case 'DELETE':
        return deleteRoutes;
      case 'HEAD':
        return headRoutes;
      case 'OPTIONS':
        return optionsRoutes;
      default:
        return extraRoutes?[method];
    }
  }
}

RouteEntry<T> newRoute<T>(
  T data,
  List<String> paramNames,
  String? wildcardName,
  String pattern,
  int depth,
  int specificity,
  int staticChars,
  int constraintScore,
  int registrationOrder,
) {
  validateCaptureNames(paramNames, wildcardName, pattern);
  return RouteEntry<T>(
    data,
    paramNames,
    wildcardName,
    depth,
    specificity,
    staticChars,
    constraintScore,
    registrationOrder,
  );
}

String canonicalPath(String path, bool caseSensitive) =>
    caseSensitive ? path : path.toLowerCase();

String normalizeMethod(String method) {
  var start = 0;
  var end = method.length;
  while (start < end && method.codeUnitAt(start) <= 32) start += 1;
  while (end > start && method.codeUnitAt(end - 1) <= 32) end -= 1;
  if (start == end) {
    throw ArgumentError.value(method, 'method', 'Method must not be empty.');
  }
  var unchanged = start == 0 && end == method.length;
  for (var i = start; i < end; i++) {
    final code = method.codeUnitAt(i);
    if (code >= 97 && code <= 122) {
      unchanged = false;
      break;
    }
  }
  if (unchanged) return method;
  final buffer = StringBuffer();
  for (var i = start; i < end; i++) {
    final code = method.codeUnitAt(i);
    buffer.writeCharCode(code >= 97 && code <= 122 ? code - 32 : code);
  }
  return buffer.toString();
}
